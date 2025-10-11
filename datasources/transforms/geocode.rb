# frozen_string_literal: true
# typed: true

require 'http'
require 'csv'
require 'rgeo'
require 'rgeo-geojson'

require_relative 'transformer'


class GeocoderTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @geocode_errors = Hash.new{ |h, k| h[k] = 0 }
    @rows = []
  end

  ADDR_FIELDS = %w[street hamlet postcode city country].freeze

  sig { params(row: Row).returns(T.nilable(String)) }
  def process_data_cache_key(row)
    return if row[:properties][:tags][:addr].nil?

    Digest::SHA1.hexdigest([row[:properties][:tags][:addr].to_a.sort, @settings].to_json)
  end

  def process_data(row)
    @rows << row
    nil
  end

  def self.split_by_addr(features)
    groups = features.group_by{ |f|
      addr = f.dig(:properties, :tags, :addr)
      next(false) if addr.nil?

      ADDR_FIELDS.any?{ |k| addr[k].present? }
    }
    [
      groups[true] || [],
      groups[false] || []
    ]
  end

  def geocode(features, &block)
    addrs = features.collect{ |f|
      addr = f.dig(:properties, :tags, :addr)
      [
        addr['postcode'],
        ADDR_FIELDS.collect{ |k| addr[k] }.compact.join(' ')
      ]
    }
    geocode_query(addrs).zip(features).each { |addr, f|
      if !addr['latitude'].presence || !addr['longitude'].presence
        @geocode_errors[:no_result] += 1
      elsif !%w[locality street housenumber].include?(addr['result_type'])
        @geocode_errors[:bad_level_of_detail] += 1
      elsif !(addr['result_score']&.to_f&.>= 0.7)
        @geocode_errors[:low_score] += 1
      else
        f[:geometry] = {
          type: 'Point',
          coordinates: [addr['longitude'].to_f, addr['latitude'].to_f],
        }
        f[:properties][:tags] = f[:properties][:tags].deep_merge(
          # Do not add addr fields, as it will change the cache key
          source: { geometry: 'BAN - ETALAB-2.0' },
        )
        f[:properties][:natives]['full_geocoding'] = addr['result_label']
      end

      block.call(f)
    }
  end

  def geocode_query(addrs)
    csv_data = CSV.generate { |csv|
      csv << %w[postcode query]
      addrs.each{ |addr| csv << addr }
    }
    resp = HTTP.post('https://api-adresse.data.gouv.fr/search/csv/', form: {
      delimiter: ',',
      encoding: 'utf-8',
      columns: 'query',
      postcode: 'postcode',
      data: HTTP::FormData::Part.new(csv_data, content_type: 'text/csv', filename: 'yes_i_am_csv.csv')
    })

    if !resp.status.success?
      raise "Fails geocoding #{resp.body}"
    end

    CSV.parse(resp.body.to_s, col_sep: ',', headers: true)
  end

  def close_data(&block)
    with_addr, without_addr = self.class.split_by_addr(@rows)

    @geocode_errors[:without_addr] = without_addr.size if without_addr.any?
    without_addr.each(&block)

    geocode(with_addr, &block)
  end

  def close
    super
    logger.info("    ! #{@geocode_errors.inspect}") if @geocode_errors.any?
  end
end
