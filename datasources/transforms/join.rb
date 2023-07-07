# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class JoinTransformer < Transformer
  def initialize(settings)
    super(settings)
    @key = settings['key']
    @full_join= settings['full_join']

    @rows = {}
    @rows_without_key = []
  end

  def process_tags(current_tags, update_tags)
    # Set non already existing tags
    update_tags.update(current_tags)
  end

  def process(row)
    key = row[:properties][:tags][@key]
    if !key.nil?
      if @rows.key?(key)
        @rows[key][:properties][:tags] = process_tags(
          @rows[key][:properties][:tags],
          row[:properties][:tags],
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
