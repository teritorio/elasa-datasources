# frozen_string_literal: true
# typed: true

class Destination
  def initialize(path)
    @path = path
  end

  def write_i18n(data)
    File.write("#{@path}/i18n.json", JSON.pretty_generate(data))
  end

  def write(row)
    type, data = row
    case type
    when :i18n then write_i18n(data)
    when :data then write_data(data)
    else Raise "Not support stream item #{type}"
    end
  end
end
