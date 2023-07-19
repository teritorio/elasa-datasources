# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/teritorio_osm'
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
  def setup(kiba)
    ontology = JSON.parse(URI.open(@settings['url']).read)

    ontology_tags = ontology['superclass'].collect{ |_superclass_id, superclasses|
      superclasses['class'].collect{ |_class_id, classes|
        if classes['subclass']
          classes['subclass'].collect{ |_subclass_id, subclasses|
            [subclasses['osm_tags'], subclasses['label']]
          }
        elsif [[classes['osm_tags'], classes['label']]]
        end
      }
    }.flatten(2).compact.collect{ |osm_tags, label|
      osm_tags = osm_tags[1..-2].split('][').collect{ |osm_tag|
        osm_tag.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
      }
      [osm_tags, label]
    }

    i18n = ontology_tags.select{ |osm_tags, _label| osm_tags.size == 1 }.group_by{ |osm_tags, _label| osm_tags[0][0] }.transform_values { |values|
      {
        values: values.to_h{ |osm_tags, _label|
          [
            osm_tags[0][1],
            { '@default:full' => i18n },
          ]
        }
      }
    }
    kiba.source(MockSource, @multi_source_id, { i18n: i18n })

    osm_tags = (
      ontology_tags.collect{ |osm_tags, _label|
        osm_tags.collect{ |k, _o, v| [k, v] }
      }.flatten(1) +
      ontology['osm_tags_extra'].collect{ |key|
        [key, nil]
      }
    ).group_by(&:first).transform_values{ |_k, v| v.nil? || v.include?(nil) ? nil : v }
    kiba.source(MockSource, @multi_source_id, { osm_tags: osm_tags })

    source_filter = @source_filter&.split('-')
    ontology['superclass'].each{ |superclass_id, superclasses|
      next if source_filter && source_filter.size >= 1 && source_filter[0] != superclass_id

      superclasses['class'].each{ |class_id, classes|
        next if source_filter && source_filter.size >= 2 && source_filter[1] != class_id

        if classes['subclass']
          classes['subclass'].each{ |subclass_id, subclasses|
            next if source_filter && source_filter.size >= 3 && source_filter[2] != subclass_id

            kiba.source(
              TeritorioOsmSource,
              "#{superclass_id}-#{class_id}-#{subclass_id}",
              @settings.merge({ 'select' => subclasses['osm_tags'] }),
            )
          }
        else
          kiba.source(
            TeritorioOsmSource,
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
