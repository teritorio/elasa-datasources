# frozen_string_literal: true
# typed: true

require 'jsonpath'

require_relative 'transformer'


class JoinTransformer < Transformer
  def initialize(settings)
    super(settings)
    @path = "$.#{settings['key']}"
    @full_join = settings['full_join']

    @i18n = {}
    @rows = {}
    @rows_without_key = []
  end

  def process_i18n(data)
    @i18n = @i18n.merge(data)
  end

  def process_tags(current_tags, update_tags, current_source, update_source)
    # Set non already existing tags
    out = {}
    source = {}
    update = false
    (current_tags.keys + update_tags.keys).each{ |key|
      if current_tags.key?(key)
        out[key] = current_tags[key]
        source[key] = current_source if current_source
      elsif update_tags.key?(key)
        out[key] = update_tags[key]
        source[key] = update_source if update_source
        update = true
      end
    }

    if update
      out[:source] = (out[:source] || {}).merge(source)
    end

    out
  end

  def process_data(row)
    key = JsonPath.on(row[:properties][:tags], @path)
    if !key.nil?
      if @rows.key?(key)
        @rows[key][:properties][:tags] = process_tags(
          @rows[key][:properties][:tags],
          row[:properties][:tags],
          @rows[key][:properties][:source],
          row[:properties][:source],
        )
      else
        @rows[key] = row
      end
      @rows[key][:destination_id] = @settings['destination_id']
    elsif @full_join
      row[:destination_id] = @settings['destination_id']
      @rows_without_key << row
    end

    nil
  end

  def close_i18n
    yield @i18n
  end

  def close_data(&block)
    @rows.values.each(&block)
    @rows_without_key.each(&block)
  end
end
