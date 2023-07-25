# frozen_string_literal: true
# typed: true

require 'active_support/all'

require_relative 'transformer'


class MetadataMerge < Transformer
  def initialize(settings)
    super(settings)
    destination_id = settings['destination_id']

    @destinations_schema = {
      destination_id: destination_id
    }
    @destinations_osm_tags = {
      destination_id: destination_id
    }

    @rows = []
  end

  def process_schema(data)
    @destinations_schema = @destinations_schema.deep_merge_array(data.except(:destination_id))
    nil
  end

  def process_osm_tags(data)
    @destinations_osm_tags = @destinations_osm_tags.deep_merge_array(data.except(:destination_id))
    nil
  end

  def process_data(row)
    @rows << row
    nil
  end

  def close_schema
    yield @destinations_schema
  end

  def close_osm_tags
    yield @destinations_osm_tags
  end

  def close_data(&block)
    @rows.each(&block)
  end
end
