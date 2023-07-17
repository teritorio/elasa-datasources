# frozen_string_literal: true
# typed: true

class Transformer
  def initialize(settings)
    @settings = settings
  end

  def process_i18n(data)
    data
  end

  def process(row)
    type, data = row
    case type
    when :i18n
      d = process_i18n(data)
      d.nil? ? nil : [type, d]
    when :data
      begin
        d = process_data(data)
        d.nil? ? nil : [type, d]
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
      if !data.nil?
        yield [:i18n, data]
      end
    }

    close_data { |data|
      if !data.nil?
        yield [:data, data]
      end
    }
  end
end
