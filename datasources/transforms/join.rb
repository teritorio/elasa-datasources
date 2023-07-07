# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class JoinTransformer < Transformer
  def initialize(settings)
    super(settings)
    @key = settings['key']

    @rows = {}
  end

  def process_tags(current_tags, update_tags)
    # Set non already existing tags
    update_tags.update(current_tags)
  end

  def process(row)
    key = row[:properties][:tags][@key]
    if @rows.key?(key)
      @rows[key][:properties][:tags] = process_tags(
        @rows[key][:properties][:tags],
        row[:properties][:tags],
      )
    else
      @rows[key] = row
    end
    @rows[key][:destination_id] = @settings['destination_id']

    nil
  end

  def close(&block)
    puts "#{self.class.name}: #{@rows.size}"

    @rows.values.each(&block)
  end
end
