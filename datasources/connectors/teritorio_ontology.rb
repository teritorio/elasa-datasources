# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'

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
  def fetch_ontology_tags
    ontology = JSON.parse(URI.open(@settings['url']).read)

    ontology_tags = ontology['superclass'].collect{ |superclass_id, superclasses|
      superclasses['class'].collect{ |class_id, classes|
        if classes['subclass']
          classes['subclass'].collect{ |subclass_id, subclasses|
            [subclasses['osm_tags'], subclasses['label'], "#{@settings['url']}##{superclass_id}-#{class_id}-#{subclass_id}"]
          }
        else
          [[classes['osm_tags'], classes['label'], "#{@settings['url']}##{superclass_id}-#{class_id}"]]
        end
      }
    }.flatten(2).compact.collect{ |osm_tags, label, origin|
      osm_tags = osm_tags[1..-2].split('][').collect{ |osm_tag|
        osm_tag.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
      }
      [osm_tags, label, origin]
    }

    [ontology, ontology_tags, ontology['osm_tags_extra']]
  end

  def parse_ontology
    ontology, ontology_tags, osm_tags_extra = fetch_ontology_tags

    schema = ontology_tags.collect{ |tags, _label, _origin|
      tags.collect{ |k, _o, v|
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

    i18n = ontology_tags.select{ |osm_tags, _label, _origin|
      osm_tags.size == 1
    }.group_by{ |osm_tags, _label, _origin|
      osm_tags[0][0]
    }.transform_values { |values|
      {
        'values' => values.to_h{ |osm_tags, label, _origin|
          [
            osm_tags[0][2],
            { '@default:full' => label },
          ]
        }
      }
    }

    # FIXME should be translated, rather than removed
    (schema.keys - i18n.keys).each{ |key|
      schema.delete(key)
    }

    osm_tags = ontology_tags.collect{ |tags, _label, origin|
      tags.collect{ |k, _o, v|
        [k, v, origin]
      }
    }.flatten(1).group_by(&:first).transform_values{ |vs|
      vs.group_by(&:second).transform_values{ |s|
        r = s.collect(&:last).uniq
        r.include?(nil) ? nil : r
      }
    }

    osm_tags_extra = osm_tags_extra.to_h{ |key|
      [key, { nil => [@settings['url']] }]
    }

    [ontology, schema, i18n, osm_tags, osm_tags_extra]
  end

  def setup(kiba)
    ontology, schema, i18n, osm_tags, osm_tags_extra = parse_ontology
    kiba.source(MockSource, @job_id, @job_id, {
      schema: {
        'type' => 'object',
        'additionalProperties' => false,
        'properties' => schema,
      },
      i18n: i18n,
      osm_tags: {
        select: osm_tags,
        interest: osm_tags_extra,
      },
    })

    kiba.source(SchemaSource, @job_id, @job_id, {
      'schema' => [
        'datasources/schemas/tags/base.schema.json',
        'datasources/schemas/tags/hosting.schema.json',
        'datasources/schemas/tags/restaurant.schema.json',
        'datasources/schemas/tags/any.schema.json',
      ],
      'i18n' => [
        'datasources/schemas/tags/base.i18n.json',
        'datasources/schemas/tags/hosting.i18n.json',
        'datasources/schemas/tags/restaurant.i18n.json',
      ]
    })

    source_filter = (
      if @source_filter.blank?
        @settings['filters']
      else
        @source_filter.split('-').reverse.inject(nil){ |sum, i| { i => sum } }
      end
    )

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
              @settings.merge({ 'select' => subclasses['osm_tags'] }),
            )
          }
        else
          kiba.source(
            OverpassSelectSource,
            @job_id,
            "#{superclass_id}-#{class_id}",
            @settings.merge({ 'select' => classes['osm_tags'] }),
          )
        end
      }
    }

    kiba.transform(OsmTags, {})

    return unless @settings['georeverse']

    kiba.transform(ReverseGeocode)
  end
end
