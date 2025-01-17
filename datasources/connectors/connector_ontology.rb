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

  def parse_ontology_schema(ontology_tags, osm_tags_extra)
    schema = ontology_tags.collect{ |_tags, _tags_extra, splits, _label, _origin|
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

    osm_tags_extra_schema = osm_tags_extra.values.inject(&:deep_merge_array).transform_values{ |values|
      if values['values'].nil?
        { 'type' => 'string' }
      elsif values['is_array']
        { 'type' => 'array', 'items' => { 'enum' => values['values'].pluck('value') } }
      else
        { 'enum' => values['values'].pluck('value') }
      end
    }

    schema.deep_merge_array(osm_tags_extra_schema)
  end

  def parse_ontology_i18n(ontology_tags, osm_tags_extra)
    i18n = ontology_tags.collect{ |osm_tags, tags_extra, splits, label, origin|
      splits.collect{ |split|
        [osm_tags, tags_extra, split, label, origin]
      }
    }.flatten(1).collect{ |osm_tags, tags_extra, split, label, origin|
      split = split.select{ |s| !%w[name access ref].include?(s[0]) }
      [osm_tags, tags_extra, split, label, origin]
    }.select{ |_osm_tags, _tags_extra, split, _label, _origin|
      split.size == 1
    }.group_by{ |_osm_tags, _tags_extra, split, _label, _origin|
      split[0][0]
    }.transform_values { |values|
      {
        'values' => values.to_h{ |_osm_tags, _tags_extra, split, label, _origin|
          [
            split[0][2],
            { '@default:full' => label },
          ]
        }
      }
    }

    osm_tags_extra_i18n = osm_tags_extra.values.inject(&:deep_merge_array).transform_values{ |values|
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
    i18n.deep_merge_array(osm_tags_extra_i18n)
  end

  def parse_ontology(source_filter)
    ontology, ontology_tags, osm_tags_extra = fetch_ontology_tags(source_filter)

    schema = parse_ontology_schema(ontology_tags, osm_tags_extra)
    i18n = parse_ontology_i18n(ontology_tags, osm_tags_extra)

    # FIXME: should be translated, rather than removed
    (schema.keys - i18n.keys).each{ |key|
      schema.delete(key)
    }

    osm_tags = ontology_tags.collect{ |tags, tags_extra, _splits, label, origin|
      {
        'name' => label,
        # 'icon' =>
        'select' => tags,
        'interest' => osm_tags_extra.slice(*tags_extra).values.inject(&:deep_merge_array)&.transform_values{ |_values|
          # TODO: support values
          nil
        },
        'sources' => origin,
      }
    }

    [ontology, schema, i18n, osm_tags]
  end
end
