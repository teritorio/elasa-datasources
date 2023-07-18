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


class TeritorioOntology < Connector
  def setup(kiba)
    ontology = JSON.parse(URI.open(@settings['url']).read)

    i18n = ontology['superclass'].collect{ |_superclass_id, superclasses|
      superclasses['class'].collect{ |_class_id, classes|
        if classes['subclass']
          classes['subclass'].collect{ |_subclass_id, subclasses|
            if subclasses['osm_tags'].size == 1 && subclasses['osm_tags'][0].size
              [subclasses['osm_tags'][0], subclasses['label']]
            end
          }
        elsif classes['osm_tags'].size == 1 && classes['osm_tags'][0].size
          [[classes['osm_tags'][0], classes['label']]]
        end
      }
    }.flatten(2).collect{ |i18n|
      [i18n[0].keys[0], i18n[0].values[0], i18n[1]]
    }.group_by(&:first).transform_values { |values|
      {
        values: values.to_h{ |_, value, i18n|
          [
            value,
            { '@default:full' => i18n },
          ]
        }
      }
    }
    kiba.source(MockSource, :i18n, { 'i18n' => i18n })

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
