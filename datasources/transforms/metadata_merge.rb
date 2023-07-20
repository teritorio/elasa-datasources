# frozen_string_literal: true
# typed: true

require 'active_support/all'

require_relative 'transformer'


class MetadataMerge < Transformer
  def initialize(settings)
    super(settings)
    destination_id = settings['destination_id']

    @destinations_i18n = {
      destination_id: destination_id
    }
    @destinations_osm_tags = {
      destination_id: destination_id
    }
  end

  def process_i18n(data)
    @destinations_i18n = @destinations_i18n.deep_merge(data.except(:destination_id))
    nil
  end

  def process_osm_tags(data)
    @destinations_osm_tags = @destinations_osm_tags.deep_merge(data.except(:destination_id))
    nil
  end

  def process_data(row)
    row
  end

  def close_i18n
    yield @destinations_i18n
  end

  def close_osm_tags
    yield @destinations_osm_tags
  end
end
