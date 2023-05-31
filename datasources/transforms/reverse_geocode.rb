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

    # TODO: geocoder uniquement ceux qui ont besoin d'un adresse

    # TODO: supporter tous les type de geom

    lon_lats = @rows.collect{ |f| f[:geometry][:coordinates] }
    addrs = reverse_query(lon_lats)
    @rows.zip(addrs).each { |f, addr|
      if !f[:properties][:tags].key?(:addr) && addr['result_city']
        f[:properties][:tags][:addr] = {
          street: addr['result_name'],
          postcode: addr['result_postcode'],
          city: addr['result_city'],
        }
        f[:properties][:tags]['source:addr'] = 'BAN - ETALAB-2.0'
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
