# frozen_string_literal: true
# typed: true

class Transformer
  def initialize(settings)
    @settings = settings
    @has_i18n = false
    @count_input_row = 0
    @count_output_row = 0
  end

  def process_i18n(data)
    data
  end

  def process(row)
    type, data = row
    case type
    when :i18n
      d = process_i18n(data)
      @has_i18n = true if d.present?
      [type, d]
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

  def close_data; end

  def close
    close_i18n { |data|
      if data.present?
        @has_i18n = true
        yield [:i18n, data]
      end
    }

    close_data { |data|
      if !data.nil?
        @count_output_row += 1
        yield [:data, data]
      end
    }

    count = @count_output_row == @count_input_row ? @count_input_row.to_s : "#{@count_input_row} -> #{@count_output_row}"
    puts "    ~ #{self.class.name}: #{count}#{@has_i18n ? ' +i18n' : ''}"
  end
end
