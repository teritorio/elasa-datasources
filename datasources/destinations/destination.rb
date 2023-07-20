# frozen_string_literal: true
# typed: true

class Destination
  def initialize(path)
    @path = path

    @destinations = Hash.new { |h, k|
      h[k] = []
    }
  end

  def write_i18n(data)
    destination_id = data.delete(:destination_id).to_s.gsub('/', '_')

    return if !data.present?

    File.write("#{@path}/#{destination_id}.i18n.json", JSON.pretty_generate(data))
  end

  def write_osm_tags(data)
    destination_id = data.delete(:destination_id).gsub('/', '_')

    return if !data.present?

    File.write("#{@path}/#{destination_id}.osm_data.json", JSON.pretty_generate(data))
  end

  def write_data(row)
    @destinations[row[:destination_id]] << row.except(:destination_id)
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

  def close
    @destinations.each{ |destination_id, rows|
      puts "    < #{self.class.name}: #{destination_id}: #{rows.size}"

      close_data(destination_id, rows)
    }
  end
end
