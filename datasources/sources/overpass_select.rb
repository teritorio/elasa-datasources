# frozen_string_literal: true
# typed: true

require 'active_support/all'
require 'cgi'

require 'sorbet-runtime'

require_relative 'overpass'


class OverpassSelectSource < OverpassSource
  def initialize(job_id, destination_id, settings)
    query = (
      if settings['query']
        settings['query']
      else
        @selectors = (
          if settings['select'].is_a?(String)
            settings['select']
          else
            settings['select'].collect{ |k, v| v.nil? ? "[#{k}]" : "[#{k}=#{v}]" }.join
          end
        )
        area_id = 3_600_000_000 + settings['relation_id']
        "
[out:json][timeout:25];
area(#{area_id})->.a;
nwr#{@selectors}(area.a);
out center meta;
"
      end
    )

    super(job_id, destination_id, settings.merge({ 'query' => query }))
  end

  def osm_tags
    return if !@settings['select'] || @settings['select'].is_a?(String)

    super().merge({
      data: [{
        select: @selectors,
        interest: @settings['interest']&.to_h{ |key| [key, nil] },
        source: [[@job_id, @destination_id].uniq.join(', ')]
      }]
    })
  end
end
