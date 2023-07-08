# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class JoinTransformer < Transformer
  def initialize(settings)
    super(settings)
    @key = settings['key']
    @full_join = settings['full_join']

    @rows = {}
    @rows_without_key = []
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
      source.each{ |key, value|
        out["source:#{key}"] = value
      }
    end

    out
  end

  def process(row)
    key = row[:properties][:tags][@key]
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

  def close(&block)
    puts "#{self.class.name}: #{@rows.size + @rows_without_key.size}"

    @rows.values.each(&block)
    @rows_without_key.each(&block)
  end
end
