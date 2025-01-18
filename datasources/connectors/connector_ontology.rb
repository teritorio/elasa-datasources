# frozen_string_literal: true
# typed: true

require 'yaml'
require 'kiba'
require 'http'


require 'sorbet-runtime'

require_relative 'connector'

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

class ConnectorOntology < Connector
  def fetch_ontology_tags(source_filter)
    ontology = JSON.parse(HTTP.follow.get(@settings['ontology_url']).body)

    properties_extras = T.let([], T::Array[T.untyped])
    ontology_tags = ontology['group'].select{ |superclass_id, _superclasses|
      !source_filter ||
        source_filter.key?(superclass_id)
    }.collect{ |superclass_id, superclasses|
      superclasses['group'].select{ |class_id, _classes|
        !source_filter ||
          !source_filter[superclass_id] ||
          source_filter[superclass_id].key?(class_id)
      }.collect{ |class_id, classes|
        if classes['group']
          classes['group'].select{ |subclass_id, _subclasses|
            !source_filter ||
              !source_filter[superclass_id] ||
              !source_filter[superclass_id][class_id] ||
              source_filter[superclass_id][class_id].key?(subclass_id)
          }.collect{ |subclass_id, subclasses|
            [subclasses['osm_selector'], subclasses['properties_extra'], subclasses['label'], ["#{@settings['url']}##{superclass_id}-#{class_id}-#{subclass_id}"]]
          }
        else
          [[classes['osm_selector'], classes['properties_extra'], classes['label'], ["#{@settings['url']}##{superclass_id}-#{class_id}"]]]
        end
      }
    }.flatten(2).compact.collect{ |osm_selector, properties_extra, label, origin|
      splits = osm_selector&.collect{ |osm_tag|
        osm_tag[1..-2].split('][').collect{ |ot|
          ot.split(/(=|~=|=~|!=|!~|~)/, 2).collect{ |s| unquote(s) }
        }
      } || []
      properties_extras += properties_extra
      [osm_selector, properties_extra, splits, label, origin]
    }

    [ontology, ontology_tags, ontology['properties_extra'].slice(*properties_extras.uniq)]
  end

  def parse_ontology_schema(ontology_tags, properties_extra)
    schema = ontology_tags.collect{ |_tags, _properties_extra, splits, _label, _origin|
      splits.collect{ |split|
        split.select{ |_k, o, _v|
          o.nil? || o[0] != '!'
        }.collect{ |k, o, v|
          [k, o == '=' ? v : nil]
        }
      }
    }.flatten(2).group_by(&:first).transform_values{ |vs|
      r = vs.collect(&:second).uniq
      if r == [nil]
        { 'type' => 'string' }
      else
        { 'enum' => r.compact }
      end
    }

    properties_extra_schema = properties_extra.values.inject(&:deep_merge_array).transform_values{ |values|
      if values['values'].nil?
        { 'type' => 'string' }
      elsif values['is_array']
        { 'type' => 'array', 'items' => { 'enum' => values['values'].pluck('value') } }
      else
        { 'enum' => values['values'].pluck('value') }
      end
    }

    schema.deep_merge_array(properties_extra_schema)
  end

  def parse_ontology_i18n(ontology_tags, properties_extra)
    i18n = ontology_tags.collect{ |osm_selector, extra, splits, label, origin|
      splits.collect{ |split|
        [osm_selector, extra, split, label, origin]
      }
    }.flatten(1).collect{ |osm_selector, extra, split, label, origin|
      split = split.select{ |s| !%w[name access ref].include?(s[0]) }
      [osm_selector, extra, split, label, origin]
    }.select{ |_osm_selector, _extra, split, _label, _origin|
      split.size == 1
    }.group_by{ |_osm_selector, _extra, split, _label, _origin|
      split[0][0]
    }.transform_values { |values|
      {
        'values' => values.to_h{ |_osm_selector, _properties_extra, split, label, _origin|
          [
            split[0][2],
            { '@default:full' => label },
          ]
        }
      }
    }

    properties_extra_i18n = properties_extra.values.inject(&:deep_merge_array).transform_values{ |values|
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
    i18n.deep_merge_array(properties_extra_i18n)
  end

  def parse_ontology(source_filter)
    ontology, ontology_tags, properties_extras = fetch_ontology_tags(source_filter)

    schema = parse_ontology_schema(ontology_tags, properties_extras)
    i18n = parse_ontology_i18n(ontology_tags, properties_extras)

    # FIXME: should be translated, rather than removed
    (schema.keys - i18n.keys).each{ |key|
      schema.delete(key)
    }

    osm_selector = ontology_tags.collect{ |tags, properties_extra, _splits, label, origin|
      {
        'name' => label,
        # 'icon' =>
        'select' => tags,
        'interest' => properties_extras.slice(*properties_extra).values.inject(&:deep_merge_array)&.transform_values{ |_values|
          # TODO: support values
          nil
        },
        'sources' => origin,
      }
    }

    [ontology, schema, i18n, osm_selector]
  end
end
