# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class LogTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  def process_metadata(data)
    puts "Metadata: #{data.inspect}"
    data
  end

  def process_schema(data)
    puts "Schema: #{data.inspect}"
    data
  end

  def process_data(row)
    puts "Data: #{row.inspect}"
    row
  end
end
