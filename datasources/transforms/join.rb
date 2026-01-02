# frozen_string_literal: true
# typed: true

require 'jsonpath'

require_relative 'transformer'


class JoinTransformer < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :source_ids, T.nilable(T::Array[String])
    const :destination_id, String
    const :key, String
    const :full_join, T::Boolean, default: false
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @path = "$.#{settings.key}"

    @rows = {}
    @rows_without_key = []
  end

  def process_tags(current_tags, update_tags, current_source, update_source)
    # Set non already existing tags
    out = {}
    sources = {}
    update = T.let(false, T::Boolean)
    (current_tags.keys + update_tags.keys).each{ |key|
      if current_tags.key?(key)
        out[key] = current_tags[key]
        sources[key] = current_source if current_source
      elsif update_tags.key?(key)
        out[key] = update_tags[key]
        sources[key] = update_source if update_source
        update = true
      end
    }

    if update
      out[:sources] = (out[:sources] || {}).merge(sources)
    end

    out.compact_blank
  end

  def process_data(row)
    return row if @settings.destination_id != row[:destination_id]

    key = JsonPath.on(row[:properties][:tags].transform_keys(&:to_s), @path)
    if key.present?
      if @rows.key?(key)
        @rows[key][:properties][:tags] = process_tags(
          @rows[key][:properties][:tags] || {},
          row[:properties][:tags] || {},
          @rows[key][:properties][:sources],
          row[:properties][:sources],
        )
        @rows[key][:properties][:natives] = process_tags(
          @rows[key][:properties][:natives] || {},
          row[:properties][:natives] || {},
          @rows[key][:properties][:sources],
          row[:properties][:sources],
        )
      else
        @rows[key] = row
      end
      @rows[key][:destination_id] = @settings.destination_id
    elsif @settings.full_join
      row[:destination_id] = @settings.destination_id
      @rows_without_key << row
    end

    nil
  end

  def close_data(&block)
    @rows.values.each(&block)
    @rows_without_key.each(&block)
  end
end
