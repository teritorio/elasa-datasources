# frozen_string_literal: true
# typed: true

require 'csv'

class Destination
  extend T::Sig
  extend T::Helpers

  abstract!

  def initialize(metadata_only: false)
    @metadata_only = metadata_only

    @destinations_metadata = T.let(Hash.new { |h, k|
      h[k] = Source::MetadataRow.new
    }, T::Hash[T.nilable(String), Source::MetadataRow])
    @destinations_schema = T.let(Hash.new { |h, k|
      h[k] = Source::SchemaRow.new
    }, T::Hash[T.nilable(String), Source::SchemaRow])
    @destinations_osm_tags = T.let(Hash.new { |h, k|
      h[k] = Source::OsmTagsRow.new
    }, T::Hash[T.nilable(String), Source::OsmTagsRow])

    @destinations_data = Hash.new { |h, k|
      h[k] = []
    }
  end

  sig { params(data: Source::MetadataRow).void }
  def write_metadata(data)
    @destinations_metadata[data.destination_id] = T.must(@destinations_metadata[data.destination_id]).deep_merge_array(data.serialize.except(:destination_id))
  end

  sig { params(data: Source::SchemaRow).void }
  def write_schema(data)
    @destinations_schema[data.destination_id] = T.must(@destinations_schema[data.destination_id]).deep_merge_array(data.serialize.except(:destination_id))
  end

  sig { params(data: Source::OsmTagsRow).void }
  def write_osm_tags(data)
    @destinations_osm_tags[data.destination_id] = T.must(@destinations_osm_tags[data.destination_id]).deep_merge_array(data.serialize.except(:destination_id))
  end

  def write_data(row)
    @destinations_data[row[:destination_id]] << row.except(:destination_id)
  end

  def write(row)
    type, data = row
    case type
    when :metadata then write_metadata(data)
    when :schema then write_schema(data)
    when :osm_tags then write_osm_tags(data)
    when :data then write_data(data)
    else raise "Not support stream item #{type}"
    end
  end

  sig { params(destination_id: T.nilable(String)).returns(String) }
  def destination_path_base(destination_id)
    destination_id.nil? ? '' : "#{destination_id.gsub('/', '_')}."
  end

  sig { params(destination_id: T.nilable(String), data: Source::MetadataRow).void }
  def close_metadata(destination_id, data)
    destination = destination_path_base(destination_id)
    data.data.delete(nil)
    content = T.cast(data.data.transform_keys{ |key| key&.gsub('/', '_') }, T::Hash[String, Source::Metadata])
    File.write("#{destination}metadata.json", JSON.pretty_generate(content))

    column_names = content.values.collect{ |source| source.name&.keys }.compact.flatten.uniq
    content_csv = CSV.generate { |csv|
      csv << ['id'] + column_names.collect{ |lang| "name:#{lang}" } + ['attribution']
      content.each { |id, source|
        csv << [id] + column_names.collect{ |lang| source.name&.[](lang) } + [source.attribution]
      }
    }
    File.write("#{destination}metadata.csv", content_csv)
  end

  sig { params(destination_id: T.nilable(String), data: Source::SchemaRow).void }
  def close_schema(destination_id, data)
    destination = destination_path_base(destination_id)
    File.write("#{destination}schema.json", JSON.pretty_generate(data.schema))
    File.write("#{destination}i18n.json", JSON.pretty_generate(data.i18n))
  end

  sig { params(destination_id: T.nilable(String), data: Source::OsmTagsRow).void }
  def close_osm_tags(destination_id, data)
    destination = destination_path_base(destination_id)
    File.write("#{destination}osm_tags.json", JSON.pretty_generate(data.data.collect{ |t| t.serialize.compact_blank }))
  end

  sig { abstract.params(destination_id: String, rows: T.untyped).void }
  def close_data(destination_id, rows); end

  def close
    all_destination_ids = @destinations_metadata.collect{ |destination_id, row|
      next if row.blank?

      logger.info("    < #{self.class.name}: #{destination_id}: +metadata")
      close_metadata(destination_id, row)

      row.data.keys
    }.flatten.compact.uniq

    if !@metadata_only
      all_destination_ids.each{ |destination_id|
        rows = @destinations_data[destination_id] || []
        logger.info("    < #{self.class.name}: #{destination_id}: #{rows.size}")
        close_data(destination_id, rows)
      }
      lost_destination_ids = @destinations_data.keys - all_destination_ids
      raise "Missing medatadata for destination ids: #{lost_destination_ids.join(', ')}" if lost_destination_ids.present?
    end

    @destinations_schema.each{ |destination_id, row|
      next if row.blank?

      logger.info("    < #{self.class.name}: #{destination_id}: +schema") if row.schema.present?
      logger.info("    < #{self.class.name}: #{destination_id}: +i18n") if row.i18n.present?
      close_schema(destination_id, row)
    }

    @destinations_osm_tags.each{ |destination_id, row|
      next if row.blank? || row.data.blank?

      logger.info("    < #{self.class.name}: #{destination_id}: +osm_tags")
      close_osm_tags(destination_id, row)
    }
  end
end
