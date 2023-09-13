# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'
require 'http'


require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/overpass_select'
require_relative '../sources/mock'
require_relative '../transforms/osm_tags'
require_relative '../transforms/reverse_geocode'

# Backport ruby 3.2
def unquote(self_)
  s = self_.dup

  case self_[0, 1]
  when "'", '"', '`'
    s[0] = ''
  end

  case self_[-1, 1]
  when "'", '"', '`'
    s[-1] = ''
  end

  s
end

class TeritorioOntology < Connector
  def fetch_ontology_tags(source_filter)
    ontology = JSON.parse(HTTP.follow.get(@settings['url']).body)

    ontology_tags = ontology['superclass'].select{ |superclass_id, _superclasses|
      !source_filter ||
        source_filter.key?(superclass_id)
    }.collect{ |superclass_id, superclasses|
      superclasses['class'].select{ |class_id, _classes|
        !source_filter ||
          !source_filter[superclass_id] ||
          source_filter[superclass_id].key?(class_id)
      }.collect{ |class_id, classes|
        if classes['subclass']
          classes['subclass'].select{ |subclass_id, _subclasses|
            !source_filter ||
              !source_filter[superclass_id] ||
              !source_filter[superclass_id][class_id] ||
              source_filter[superclass_id][class_id].key?(subclass_id)
          }.collect{ |subclass_id, subclasses|
            [subclasses['osm_tags'], subclasses['label'], ["#{@settings['url']}##{superclass_id}-#{class_id}-#{subclass_id}"]]
          }
        else
          [[classes['osm_tags'], classes['label'], ["#{@settings['url']}##{superclass_id}-#{class_id}"]]]
        end
      }
    }.flatten(2).compact.collect{ |osm_tags, label, origin|
      split = osm_tags[1..-2].split('][').collect{ |osm_tag|
        osm_tag.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
      }
      [osm_tags, split, label, origin]
    }

    [ontology, ontology_tags, ontology['osm_tags_extra']]
  end

  def parse_ontology(source_filter)
    ontology, ontology_tags, osm_tags_extra = fetch_ontology_tags(source_filter)

    schema = ontology_tags.collect{ |_tags, split, _label, _origin|
      split.collect{ |k, _o, v|
        [k, v]
      }
    }.flatten(1).group_by(&:first).transform_values{ |vs|
      r = vs.collect(&:second).uniq
      if r.include?(nil)
        { 'type' => 'string' }
      else
        { 'enum' => r }
      end
    }

    i18n = ontology_tags.select{ |osm_tags, _split, _label, _origin|
      osm_tags.split('][').size == 1
    }.group_by{ |_osm_tags, split, _label, _origin|
      split[0][0]
    }.transform_values { |values|
      {
        'values' => values.to_h{ |_osm_tags, split, label, _origin|
          [
            split[0][2],
            { '@default:full' => label },
          ]
        }
      }
    }

    # FIXME: should be translated, rather than removed
    (schema.keys - i18n.keys).each{ |key|
      schema.delete(key)
    }

    osm_tags_extra = osm_tags_extra.to_h{ |key|
      [key, nil]
    }

    osm_tags = ontology_tags.collect{ |tags, _split, _label, origin|
      {
        select: tags,
        interest: osm_tags_extra,
        sources: origin,
      }
    }

    [ontology, schema, i18n, osm_tags]
  end

  def setup(kiba)
    source_filter = @settings['filters']

    ontology, schema, i18n, osm_tags = parse_ontology(source_filter)
    kiba.source(MockSource, @job_id, @job_id, nil, MockSource::Settings.from_hash({
      'schema' => {
        'type' => 'object',
        'additionalProperties' => false,
        'properties' => schema,
      },
      'i18n' => i18n,
      'osm_tags' => osm_tags,
    }))

    kiba.source(MetadataSource, @job_id, @job_id, nil, MetadataSource::Settings.from_hash({
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
        'datasources/schemas/tags/hosting.schema.json',
        'datasources/schemas/tags/restaurant.schema.json',
        'datasources/schemas/tags/osm.schema.json',
        'datasources/schemas/tags/any.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
        'datasources/schemas/tags/hosting.i18n.json',
        'datasources/schemas/tags/restaurant.i18n.json',
        'datasources/schemas/tags/osm.i18n.json',
      ]
    }))

    if @source_filter.present?
      source_filter = @source_filter.split('-').reverse.inject(nil){ |sum, i| { i => sum } }
    end

    ontology['superclass'].select{ |superclass_id, _superclasses|
      !source_filter ||
        source_filter.key?(superclass_id)
    }.each{ |superclass_id, superclasses|
      superclasses['class'].select{ |class_id, _classes|
        !source_filter ||
          !source_filter[superclass_id] ||
          source_filter[superclass_id].key?(class_id)
      }.each{ |class_id, classes|
        if classes['subclass']
          classes['subclass'].select{ |subclass_id, _subclasses|
            !source_filter ||
              !source_filter[superclass_id] ||
              !source_filter[superclass_id][class_id] ||
              source_filter[superclass_id][class_id].key?(subclass_id)
          }.each{ |subclass_id, subclasses|
            kiba.source(
              OverpassSelectSource,
              @job_id,
              "#{superclass_id}-#{class_id}-#{subclass_id}",
              subclasses['label'],
              OverpassSelectSource::Settings.from_hash(@settings.merge({ 'select' => subclasses['osm_tags'] })),
            )
          }
        else
          kiba.source(
            OverpassSelectSource,
            @job_id,
            "#{superclass_id}-#{class_id}",
            classes['label'],
            OverpassSelectSource::Settings.from_hash(@settings.merge({ 'select' => classes['osm_tags'] })),
          )
        end
      }
    }

    kiba.transform(OsmTags, OsmTags::Settings.from_hash({}))

    return unless @settings['georeverse']

    kiba.transform(ReverseGeocode, Transformer::TransformerSettings.from_hash({}))
  end
end
