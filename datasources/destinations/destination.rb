# frozen_string_literal: true
# typed: true

class Destination
  def initialize(path)
    @path = path

    @destinations_i18n = Hash.new { |h, k|
      h[k] = {}
    }
    @destinations_osm_tags = Hash.new { |h, k|
      h[k] = {}
    }

    @destinations_data = Hash.new { |h, k|
      h[k] = []
    }
  end

  def write_i18n(data)
    @destinations_i18n[data[:destination_id]] = @destinations_i18n[data[:destination_id]].deep_merge(data.except(:destination_id))
  end

  def write_osm_tags(data)
    @destinations_osm_tags[data[:destination_id]] = @destinations_osm_tags[data[:destination_id]].deep_merge(data.except(:destination_id))
  end

  def write_data(row)
    @destinations_data[row[:destination_id]] << row.except(:destination_id)
  end

  def write(row)
    type, data = row
    case type
    when :i18n then write_i18n(data)
    when :osm_tags then write_osm_tags(data)
    when :data then write_data(data)
    else Raise "Not support stream item #{type}"
    end
  end

  def close_i18n(destination_id, data)
    destination_id = destination_id.gsub('/', '_')
    File.write("#{@path}/#{destination_id}.i18n.json", JSON.pretty_generate(data))
  end

  def close_osm_tags(destination_id, data)
    destination_id = destination_id.gsub('/', '_')
    File.write("#{@path}/#{destination_id}.osm_data.json", JSON.pretty_generate(data))
  end

  def close
    @destinations_data.each{ |destination_id, rows|
      puts "    < #{self.class.name}: #{destination_id}: #{rows.size}"
      close_data(destination_id, rows)
    }

    @destinations_i18n.each{ |destination_id, row|
      next if row.blank?

      puts "    < #{self.class.name}: #{destination_id}: +i18n"
      close_i18n(destination_id, row)
    }

    @destinations_osm_tags.each{ |destination_id, row|
      next if row.blank?

      puts "    < #{self.class.name}: #{destination_id}: +osm_data"
      close_osm_tags(destination_id, row)
    }
  end
end
