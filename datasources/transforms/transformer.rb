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
      d = process_data(data)
      d.nil? ? nil : [type, d]
    else Raise "Not support stream item #{type}"
    end
  end

  def close_i18n; end

  def close_data; end

  def close
    close_i18n { |data|
      yield [:i18n, data]
    }

    close_data { |data|
      yield [:data, data]
    }
  end
end
