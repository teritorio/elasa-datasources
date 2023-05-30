# frozen_string_literal: true
# typed: true

require 'http'
require 'csv'

class ReverseGeocode
  def initialize
    @rows = []
  end

  def process(row)
    @rows << row
    nil
  end

  def close
    puts "#{self.class.name}: #{@rows.size}"

    lon_lats = @rows.collect{ |f| f[:geometry][:coordinates] }
    addrs = reverse_query(lon_lats)
    @rows.zip(addrs).each { |f, addr|
      # There is an adresse defined by addr:* ?
      has_addr = f[:properties][:tags].keys.find{ |k| k.start_with?('addr:') }

      if !has_addr && addr['result_city']
        f[:properties][:tags]['addr:street'] = addr['result_name']
        f[:properties][:tags]['addr:postcode'] = addr['result_postcode']
        f[:properties][:tags]['addr:city'] = addr['result_city']
        f[:properties][:tags]['source:addr:street'] = 'BAN - ETALAB-2.0'
        f[:properties][:tags]['source:addr:postcode'] = 'BAN - ETALAB-2.0'
        f[:properties][:tags]['source:addr:city'] = 'BAN - ETALAB-2.0'
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
      raise 'Fails reverse geocoding', resp.body
    end

    CSV.parse(resp.body.to_s, col_sep: ',', headers: true)
  end
end
