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

    ontology_tags = ontology['superclass'].collect{ |_superclass_id, superclasses|
      superclasses['class'].collect{ |_class_id, classes|
        if classes['subclass']
          classes['subclass'].collect{ |_subclass_id, subclasses|
            [subclasses['osm_tags'], subclasses['label']]
          }
        else
          [[classes['osm_tags'], classes['label']]]
        end
      }
    }.flatten(2).compact.collect{ |osm_tags, label|
      osm_tags = osm_tags[1..-2].split('][').collect{ |osm_tag|
        osm_tag.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
      }
      [osm_tags, label]
    }

    [ontology, ontology_tags, ontology['osm_tags_extra']]
  end

  def parse_ontology
    ontology, ontology_tags, osm_tags_extra = fetch_ontology_tags

    i18n = ontology_tags.select{ |osm_tags, _label|
      osm_tags.size == 1
    }.group_by{ |osm_tags, _label|
      osm_tags[0][0]
    }.transform_values { |values|
      {
        'values' => values.to_h{ |osm_tags, label|
          [
            osm_tags[0][2],
            { '@default:full' => label },
          ]
        }
      }
    }

    osm_tags = ontology_tags.collect(&:first).flatten(1).collect{ |k, _o, v|
      [k, v]
    }.group_by(&:first).transform_values{ |vs|
      r = vs.collect(&:last).uniq
      r.include?(nil) ? nil : r
    }

    osm_tags_extra = osm_tags_extra.to_h{ |key|
      [key, nil]
    }

    [ontology, i18n, osm_tags, osm_tags_extra]
  end

  def setup(kiba)
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

    ontology, i18n, osm_tags, osm_tags_extra = parse_ontology
    kiba.source(MockSource, @job_id, @job_id, { i18n: i18n })
    kiba.source(MockSource, @job_id, @job_id, { osm_tags: {
      select: osm_tags,
      interest: osm_tags_extra,
    } })

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
