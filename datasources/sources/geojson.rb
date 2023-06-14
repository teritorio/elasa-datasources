# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'open-uri'
require 'cgi'
require 'sorbet-runtime'
require_relative 'source'


class GeoJsonSource < Source
  def initialize(source_id, attribution, settings, path)
    super(source_id, attribution, settings, path)
    @source_url = settings[:source_url]
  end

  def fetch(url)
    body = (
      if url.start_with?('file://')
        File.read(url[('file://'.size)..])
      else
        resp = HTTP.follow.get(url)
        if !resp.status.success?
          raise [url, resp].inspect
        end

        resp.body
      end
    )

    JSON.parse(body)['features']
  end

  def each
    raw = fetch(@source_url)
    puts "#{self.class.name}: #{raw.size}"

    raw.each { |r|
      yield ({
        type: 'Feature',
        geometry: r['geometry'],
        properties: {
          id: r['properties']['id'],
          updated_at: r['properties']['updated_at'],
          source: r['properties']['source'],
          tags: r['properties']['tags'].compact_blank,
        }
    })
    }
  end
end
