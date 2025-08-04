# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class SanitizeTagsTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  def deep_apply(object, &proc)
    if object.is_a?(Array)
      object.each_with_object([]) { |v, a|
        a << deep_apply(v, &proc)
      }
    elsif object.is_a?(Hash)
      object.each_with_object({}) { |(k, v), h|
        h[proc.call(k)] = deep_apply(v, &proc)
      }
    else
      proc.call(object)
    end
  end

  def sanitize(object)
    if object.is_a?(String)
      object.strip
    else
      object
    end
  end

  def process_data(row)
    if !row[:properties][:tags].nil?
      row[:properties][:tags] = deep_apply(row[:properties][:tags]) { |o| sanitize(o) }
    end
    if !row[:properties][:natives].nil?
      row[:properties][:natives] = deep_apply(row[:properties][:natives]) { |o| sanitize(o) }
    end
    row
  end
end
