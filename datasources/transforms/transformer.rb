# frozen_string_literal: true
# typed: true

require 'moneta'
require 'digest/sha1'


class Transformer
  extend T::Sig
  extend T::Helpers

  abstract!

  class TransformerSettings < T::InexactStruct
    const :cache_data, T.nilable(Integer)
  end

  Settings = TransformerSettings

  extend T::Generic

  SettingsType = type_member{ { upper: TransformerSettings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    T.assert_type!(settings, TransformerSettings) # FIXME: Manually assert type, because type is not asserted automatically, because of genereics ? (why?)
    @settings = settings
    @has_metadata = false
    @has_schema = false
    @has_i18n = false
    @has_osm_tags = false
    @count_input_row = 0
    @count_output_row = 0

    return unless @settings.cache_data

    @cache = Moneta::Adapters::File.new(dir: '/cache')
  end

  sig { params(data: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(data)
    data
  end

  sig { params(data: Source::SchemaRow).returns(T.nilable(Source::SchemaRow)) }
  def process_schema(data)
    data
  end

  sig { params(data: Source::OsmTagsRow).returns(T.nilable(Source::OsmTagsRow)) }
  def process_osm_tags(data)
    data
  end

  Row = T.type_alias {
    {
      destination_id: String,
      type: String,
      properties: T.nilable(T::Hash[T.untyped, T.untyped]),
      geometry: T.nilable(T::Hash[T.untyped, T.untyped]),
    }
  }

  sig { params(row: Row).returns(String) }
  def process_data_cache_key(row)
    Digest::SHA1.hexdigest([row[:destination_id], row[:geometry], @settings].to_json)
  end

  sig { params(row: Row).returns(T.untyped) }
  def process_data(row); end

  def process(row)
    type, data = row
    case type
    when :metadata
      d = process_metadata(data)
      if d&.data.present?
        @has_metadata = true
        [type, d]
      end
    when :schema
      d = process_schema(data)
      if d.present?
        @has_schema = data.schema.present?
        @has_i18n = data.i18n.present?
        [type, d]
      end
    when :osm_tags
      d = process_osm_tags(data)
      if d&.data.present?
        @has_osm_tags = true
        [type, d]
      end
    when :data
      @count_input_row += 1

      if !@cache.nil? && !(cache_key = process_data_cache_key(data)).nil? && @cache&.key?(cache_key)
        d = T.cast(JSON.parse(@cache.load(cache_key)), T.any(Hash, T::Array[Hash]))
        if !d.is_a?(Array)
          d = [d]
        end
        d = d.collect{ |dd|
          dd = dd.transform_keys(&:to_sym)
          dd[:properties] = dd[:properties].transform_keys(&:to_sym)
          dd[:properties][:tags] = dd[:properties][:tags].transform_keys(&:to_sym) if dd[:properties][:tags].present?
          dd[:properties][:natives] = dd[:properties][:natives].transform_keys(&:to_sym) if dd[:properties][:natives].present?
          dd
        }
      else
        d = process_data(data)

        @cache&.store(cache_key, d.to_json, expires: @settings.cache_data)
      end

      if !d.nil?
        d = [d] if !d.is_a?(Array)
        d.each{ |dd|
          @count_output_row += 1
          yield [type, dd]
        }
        nil # Return nothing as we already yielded the data
      end
    else raise "Not support stream item #{type}"
    end
  end

  def close_metadata; end

  def close_schema; end

  def close_osm_tags; end

  def close_data; end

  def close
    close_metadata{ |data|
      if data.data.present?
        @has_metadata = true
        yield [:metadata, data]
      end
    }

    close_schema { |data|
      if data.present?
        @has_schema = data.schema.present?
        @has_i18n = data.i18n.present?
        yield [:schema, data]
      end
    }

    close_osm_tags { |data|
      if data.data.present?
        @has_osm_tags = true
        yield [:osm_tags, data]
      end
    }

    close_data { |data|
      if !data.nil?
        @count_output_row += 1
        yield [:data, data]
      end
    }

    count = @count_output_row == @count_input_row ? @count_input_row.to_s : "#{@count_input_row} -> #{@count_output_row}"
    log = "    ~ #{self.class.name}: #{count}"
    log += ' +metadata' if @has_metadata
    log += ' +schema' if @has_schema
    log += ' +i18n' if @has_i18n
    log += ' +osm_tags' if @has_osm_tags
    logger.info(log)
  end
end
