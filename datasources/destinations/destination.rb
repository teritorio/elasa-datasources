# frozen_string_literal: true
# typed: true

class Destination
  extend T::Sig
  extend T::Helpers
  abstract!

  def initialize(path)
    @path = path

    @destinations_metadata = Hash.new { |h, k|
      h[k] = {}
    }
    @destinations_schema = Hash.new { |h, k|
      h[k] = {}
    }
    @destinations_osm_tags = Hash.new { |h, k|
      h[k] = {}
    }

    @destinations_data = Hash.new { |h, k|
      h[k] = []
    }
  end

  def write_metadata(data)
    @destinations_metadata[data[:destination_id]] = @destinations_metadata[data[:destination_id]].deep_merge_array(data.except(:destination_id))
  end

  def write_schema(data)
    @destinations_schema[data[:destination_id]] = @destinations_schema[data[:destination_id]].deep_merge_array(data.except(:destination_id))
  end

  def write_osm_tags(data)
    @destinations_osm_tags[data[:destination_id]] = @destinations_osm_tags[data[:destination_id]].deep_merge_array(data.except(:destination_id))
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

  def close_metadata(destination_id, data)
    destination = destination_id.nil? ? '' : "#{destination_id.gsub('/', '_')}."
    File.write("#{@path}/#{destination}metadata.json", JSON.pretty_generate(data[:data]))
  end

  def close_schema(destination_id, data)
    destination = destination_id.nil? ? '' : "#{destination_id.gsub('/', '_')}."
    File.write("#{@path}/#{destination}schema.json", JSON.pretty_generate(data[:schema]))
    File.write("#{@path}/#{destination}i18n.json", JSON.pretty_generate(data[:i18n]))
  end

  def close_osm_tags(destination_id, data)
    destination = destination_id.nil? ? '' : "#{destination_id.gsub('/', '_')}."
    File.write("#{@path}/#{destination}osm_tags.json", JSON.pretty_generate(data[:data]))
  end

  sig { abstract.params(destination_id: String, rows: T.untyped).void }
  def close_data(destination_id, rows); end

  def close
    @destinations_data.each{ |destination_id, rows|
      logger.info("    < #{self.class.name}: #{destination_id}: #{rows.size}")
      close_data(destination_id, rows)
    }

    @destinations_metadata.each{ |destination_id, row|
      next if row.blank?

      logger.info("    < #{self.class.name}: #{destination_id}: +metadata")
      close_metadata(destination_id, row)
    }

    @destinations_schema.each{ |destination_id, row|
      next if row.blank?

      logger.info("    < #{self.class.name}: #{destination_id}: +metadata") if row[:metadata].present?
      logger.info("    < #{self.class.name}: #{destination_id}: +schema") if row[:schema].present?
      logger.info("    < #{self.class.name}: #{destination_id}: +i18n") if row[:i18n].present?
      close_schema(destination_id, row)
    }

    @destinations_osm_tags.each{ |destination_id, row|
      next if row.blank? || row[:data].blank?

      logger.info("    < #{self.class.name}: #{destination_id}: +osm_tags")
      close_osm_tags(destination_id, row)
    }
  end
end
