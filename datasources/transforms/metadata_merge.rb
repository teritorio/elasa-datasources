# frozen_string_literal: true
# typed: true

class MetadataMerge < Transformer
  def initialize(settings)
    super(settings)

    @destinations_i18n = Hash.new { |h, k|
      h[k] = {}
    }
    @destinations_osm_tags = Hash.new { |h, k|
      h[k] = {}
    }
  end

  def process_i18n(data)
    @destinations_i18n[data[:destination_id]] = @destinations_i18n[data[:destination_id]].deep_merge(data)
    nil
  end

  def process_osm_tags(data)
    @destinations_osm_tags[data[:destination_id]] = @destinations_osm_tags[data[:destination_id]].deep_merge(data)
    nil
  end

  def process_data(row)
    row
  end

  def close_i18n(&block)
    @destinations_i18n.values.each(&block)
  end

  def close_osm_tags(&block)
    @destinations_osm_tags.values.each(&block)
  end
end
