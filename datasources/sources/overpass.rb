# frozen_string_literal: true
# typed: true

require 'active_support/all'
require 'cgi'

require 'sorbet-runtime'

require_relative 'csv'


class OverpassSource < CsvSource
  def initialize(destination_id, settings)
    settings['col_sep'] = "\t"
    settings['id'] ||= '@id'
    settings['lon'] ||= '@lon'
    settings['lat'] ||= '@lat'
    settings['timestamp'] ||= '@timestamp'
    settings['overpass_url'] ||= 'https://overpass-api.de/api'
    settings['attribution'] = '<a href="https://osm.org">© OpenStreetMap</a>'
    if settings['query'].nil?
      settings['out_tags'] = settings['out_tags'] || ['name']
      out_tags = settings['out_tags'].collect{ |t| "\"#{t}\"" }.join(',')
      filters_tags = settings['filter_tags'].collect{ |k, v| "[\"#{k}\"=\"#{v}\"]" }.join
      relation_id = settings['relation_id']
      settings['query'] = <<~QUERY
        [out:csv(::id,::lat,::lon,::timestamp,#{out_tags})][timeout:25];
        area(#{3_600_000_000 + relation_id})->.a;
        nwr#{filters_tags}(area.a);
        out meta center qt;
      QUERY
    end
    data = CGI.escape(settings['query'])
    settings['url'] = "#{settings['overpass_url']}/interpreter?data=#{data}"

    super(destination_id, settings)
  end

  def osm_tags
    super().merge(@settings['filter_tags'], @settings['out_tags'].to_h{ |key| [key, nil] })
  end
end
