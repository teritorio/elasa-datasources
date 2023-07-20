# frozen_string_literal: true
# typed: true

class Transformer
  def initialize(settings)
    @settings = settings
    @has_i18n = false
    @has_osm_tags = false
    @count_input_row = 0
    @count_output_row = 0
  end

  def process_i18n(data)
    data
  end

  def process_osm_tags(data)
    data
  end

  def process(row)
    type, data = row
    case type
    when :i18n
      d = process_i18n(data)
      if d.present?
        @has_i18n = true
        [type, d]
      end
    when :osm_tags
      d = process_osm_tags(data)
      if d.present?
        @has_osm_tags = true
        [type, d]
      end
    when :data
      @count_input_row += 1
      begin
        d = process_data(data)
        if !d.nil?
          @count_output_row += 1
          [type, d]
        end
      rescue StandardError => e
        puts "#{e}\n\n"
        nil
      end
    else Raise "Not support stream item #{type}"
    end
  end

  def close_i18n; end

  def close_osm_tags; end

  def close_data; end

  def close
    close_i18n { |data|
      if data.present?
        @has_i18n = true
        yield [:i18n, data]
      end
    }

    close_osm_tags { |data|
      if data.present?
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
    log += ' +i18' if @has_i18n
    log += ' +osm_tags' if @has_osm_tags
    puts log
  end
end
