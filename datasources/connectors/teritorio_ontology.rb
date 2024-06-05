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

    osm_tags_extras = T.let([], T::Array[T.untyped])
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
            [subclasses['osm_tags'], subclasses['osm_tags_extra'], subclasses['label'], ["#{@settings['url']}##{superclass_id}-#{class_id}-#{subclass_id}"]]
          }
        else
          [[classes['osm_tags'], classes['osm_tags_extra'], classes['label'], ["#{@settings['url']}##{superclass_id}-#{class_id}"]]]
        end
      }
    }.flatten(2).compact.collect{ |osm_tags, osm_tags_extra, label, origin|
      splits = osm_tags.collect{ |osm_tag|
        osm_tag[1..-2].split('][').collect{ |ot|
          ot.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
        }
      }
      osm_tags_extras += osm_tags_extra
      [osm_tags, osm_tags_extra, splits, label, origin]
    }

    [ontology, ontology_tags, ontology['osm_tags_extra'].slice(*osm_tags_extras.uniq)]
  end

  def parse_ontology(source_filter)
    ontology, ontology_tags, osm_tags_extra = fetch_ontology_tags(source_filter)

    schema = ontology_tags.collect{ |_tags, _tags_extra, splits, _label, _origin|
      splits.collect{ |split|
        split.collect{ |k, _o, v|
          [k, v]
        }
      }
    }.flatten(2).group_by(&:first).transform_values{ |vs|
      r = vs.collect(&:second).uniq
      if r.include?(nil)
        { 'type' => 'string' }
      else
        { 'enum' => r }
      end
    }

    osm_tags_extra_schema = osm_tags_extra.values.inject(&:merge).transform_values{ |values|
      if values['values'].nil?
        { 'type' => 'string' }
      else
        { 'enum' => values['values'].pluck('value') }
      end
    }
    schema = schema.deep_merge_array(osm_tags_extra_schema)

    i18n = ontology_tags.select{ |osm_tags, _tags_extra, splits, _label, _origin|
      osm_tags.split('][').size == 1 && splits.size == 1
    }.group_by{ |_osm_tags, _tags_extra, splits, _label, _origin|
      splits[0][0][0]
    }.transform_values { |values|
      {
        'values' => values.to_h{ |_osm_tags, _tags_extra, splits, label, _origin|
          [
            splits[0][0][2],
            { '@default:full' => label },
          ]
        }
      }
    }

    osm_tags_extra_i18n = osm_tags_extra.values.inject(&:merge).transform_values{ |values|
      {
        '@default' => values['label'].compact_blank,
        'values' => values['values'].to_h { |h|
          [
            h['value'],
            { '@default:full' => h['label'] },
          ]
        }.compact_blank
      }.compact_blank
    }.compact_blank
    i18n = i18n.deep_merge_array(osm_tags_extra_i18n)

    # FIXME: should be translated, rather than removed
    (schema.keys - i18n.keys).each{ |key|
      schema.delete(key)
    }

    osm_tags = ontology_tags.collect{ |tags, tags_extra, _splits, label, origin|
      {
        'name' => label,
        # 'icon' =>
        'select' => tags,
        'interest' => osm_tags_extra.slice(*tags_extra).values.inject(&:merge)&.transform_values{ |_values|
          # TODO: support values
          nil
        },
        'sources' => origin,
      }
    }

    [ontology, schema, i18n, osm_tags]
  end

  def setup(kiba)
    source_filter = @settings['filters']
    output_prefix = @settings['output_prefix'] ? "#{@settings['output_prefix']}-" : ""

    ontology, schema, i18n, osm_tags = parse_ontology(source_filter)
    kiba.source(MockSource, @job_id, nil, nil, MockSource::Settings.from_hash({
      'schema' => {
        'type' => 'object',
        'additionalProperties' => false,
        'properties' => schema,
      },
      'i18n' => i18n,
      'osm_tags' => osm_tags,
    }))

    kiba.source(MetadataSource, @job_id, nil, nil, MetadataSource::Settings.from_hash({
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
              "#{output_prefix}#{superclass_id}-#{class_id}-#{subclass_id}",
              subclasses['label'],
              OverpassSelectSource::Settings.from_hash(@settings.merge({ 'select' => subclasses['osm_tags'], 'with_osm_tags' => false })),
            )
          }
        else
          kiba.source(
            OverpassSelectSource,
            @job_id,
            "#{output_prefix}#{superclass_id}-#{class_id}",
            classes['label'],
            OverpassSelectSource::Settings.from_hash(@settings.merge({ 'select' => classes['osm_tags'], 'with_osm_tags' => false })),
          )
        end
      }
    }

    kiba.transform(OsmTags, OsmTags::Settings.from_hash({}))

    return unless @settings['georeverse']

    kiba.transform(ReverseGeocode, Transformer::TransformerSettings.from_hash({}))
  end
end
