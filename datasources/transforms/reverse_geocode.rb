# frozen_string_literal: true
# typed: true

require 'http'
require 'csv'

require_relative 'transformer'


class ReverseGeocode < Transformer
  extend T::Generic
  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super(settings)
    @rows = []
  end

  def process_data(row)
    @rows << row
    nil
  end

  def close_data
    logger.info("#{self.class.name}: #{@rows.size}")

    # TODO: geocoder uniquement ceux qui ont besoin d'un adresse

    # TODO: supporter tous les type de geom

    lon_lats = @rows.collect{ |f| f[:geometry][:coordinates] }
    addrs = reverse_query(lon_lats)
    @rows.zip(addrs).each { |f, addr|
      if addr['result_city']
        if !f[:properties][:tags].key?(:addr)
          f[:properties][:tags][:addr] = {
            street: addr['result_name'],
            postcode: addr['result_postcode'],
            city: addr['result_city'],
          }
          f[:properties][:tags]['source:addr'] = 'BAN - ETALAB-2.0'
        elsif !f[:properties][:tags][:addr].key?('postcode') || !f[:properties][:tags][:addr].key?('city')
          f[:properties][:tags][:addr]['postcode'] = addr['result_postcode']
          f[:properties][:tags][:addr]['city'] = addr['result_city']
          f[:properties][:tags]['source:addr'] = 'BAN - ETALAB-2.0'
        end
      end

      yield f
    }
  end

  def reverse_query(lon_lats)
    csv_data = CSV.generate { |csv|
      csv << %w[lon lat]
      lon_lats.each{ |ll| csv << ll }
    }
    resp = HTTP.post('https://api-adresse.data.gouv.fr/reverse/csv/', form: {
      delimiter: ',',
      encoding: 'utf-8',
      data: HTTP::FormData::Part.new(csv_data, content_type: 'text/csv', filename: 'yes_i_am_csv.csv')
    })

    if !resp.status.success?
      raise "Fails reverse geocoding #{resp.body}"
    end

    CSV.parse(resp.body.to_s, col_sep: ',', headers: true)
  end
end
