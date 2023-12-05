# frozen_string_literal: true
# typed: true

require 'active_support/all'

require_relative 'transformer'


class MetadataMerge < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :destination_id, String
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: Settings).void }
  def initialize(settings)
    super(settings)
    destination_id = settings.destination_id

    @destinations_metadata = Source::MetadataRow.new(
      destination_id: destination_id
    )
    @destinations_schema = Source::SchemaRow.new(
      destination_id: destination_id
    )
    @destinations_osm_tags = Source::OsmTagsRow.new(
      destination_id: destination_id,
      data: [],
    )

    @rows = []
  end

  sig { params(data: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(data)
    data = data.serialize.except('destination_id')
    # Remove nil destination data
    data['data'].delete(nil)
    @destinations_metadata = @destinations_metadata.deep_merge_array(data)
    nil
  end

  sig { params(data: Source::SchemaRow).returns(T.nilable(Source::SchemaRow)) }
  def process_schema(data)
    data = data.serialize.except('destination_id')
    # Remove nil destination data
    data['schema']&.delete(nil)
    data['i18n']&.delete(nil)
    @destinations_schema = @destinations_schema.deep_merge_array(data)
    nil
  end

  sig { params(data: Source::OsmTagsRow).returns(T.nilable(Source::OsmTagsRow)) }
  def process_osm_tags(data)
    data = data.serialize.except('destination_id')
    # Remove nil destination data
    data['data'].delete(nil)
    @destinations_osm_tags = @destinations_osm_tags.deep_merge_array(data)
    nil
  end

  def process_data(row)
    @rows << row
    nil
  end

  def close_metadata
    yield @destinations_metadata
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
