# frozen_string_literal: true
# typed: true

require 'nokogiri'
require_relative 'destination'

class Gpx < Destination
  def close_data(destination_id, rows)
    rows.each{ |feat|
      type = feat[:geometry]['type']
      next if type == 'Point'

      geom = feat[:geometry]['coordinates']
      geom = [geom] if type == 'LineString'

      builder = Nokogiri::XML::Builder.new { |xml|
        xml.gpx {
          xml.trk {
            geom.collect{ |multi_line|
              xml.trkseg {
                multi_line.collect{ |line|
                  xml.trkpt(lon: line[0], lat: line[1])
                }
              }
            }
          }
        }
      }

      ref = feat[:properties][:tags][:ref]
      File.write("#{destination_id.gsub('/', '_')}-#{ref[:ref]}.gpx", builder.to_xml) if !ref.nil?
    }
  end
end
