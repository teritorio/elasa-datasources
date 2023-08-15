# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

class HashExcep < Hash
  def [](key)
    raise "Missing key \"#{key}\" in Hash" if !key?(key)

    super(key)
  end
end

class Source
  def initialize(job_id, destination_id, settings)
    @job_id = job_id
    @destination_id = destination_id
    @settings = settings
    @attribution = settings['attribution']
  end

  def schema
    {
      destination_id: @destination_id,
    }
  end

  def osm_tags
    {
      destination_id: @destination_id,
      data: [],
    }
  end

  def select(_feat)
    true
  end

  def map_destination_id(_feat)
    @destination_id
  end

  def map_source(_feat)
    @attribution
  end

  def map_native_properties(_feat, _properties)
    nil
  end

  def each(raw)
    schema_data = schema
    yield [:schema, schema_data]
    osm_tags_data = osm_tags
    yield [:osm_tags, osm_tags_data]

    log = "    > #{self.class.name}, #{@destination_id.inspect}: #{raw.size}"
    log += ' +schema' if schema_data[:schema].present?
    log += ' +i18n' if schema_data[:i18n].present?
    log += ' +osm_tags' if osm_tags_data&.dig(:data).present?
    logger.info(log)
    bad = {
      filtered_out: 0,
      missing_id: 0,
      missing_updated_at: 0,
      missing_geometry: 0,
      null_island_geometry: 0,
      missing_tags: 0,
      pass: 0,
    }

    raw.each{ |r|
      begin
        if !select(r)
          bad[:filtered_out] += 1
          next
        end

        check = !@settings['allow_partial_source']

        id = map_id(r)
        if check && id.blank?
          bad[:missing_id] += 1
          raise 'Missing id'
        end

        updated_at = map_updated_at(r)
        if check && updated_at.blank?
          bad[:missing_updated_at] += 1
          raise 'Missing updated_at'
        end

        geometry = map_geometry(r)
        if check && geometry.blank?
          bad[:missing_geometry] += 1
          raise 'Missing geometry'
        end

        geometry = map_geometry(r)
        if check && geometry[:type] == 'Point' && geometry[:coordinates] == [0.0, 0.0]
          bad[:null_island_geometry] += 1
          raise 'Null island geometry'
        end

        tags = map_tags(r)
        if check && tags.blank?
          bad[:missing_tags] += 1
          next
        end

        properties = {
          destination_id: map_destination_id(r),
          type: 'Feature',
          geometry: geometry,
          properties: { tags: {} }.merge({
            id: id,
            updated_at: updated_at,
            source: map_source(r),
            tags: tags&.compact_blank,
            natives: map_native_properties(r, @settings['native_properties'] || {})&.compact_blank,
          }.compact_blank),
        }.compact_blank
        yield [:data, properties]

        bad[:pass] += 1
      rescue StandardError => e
        logger.debug(['Native', JSON.dump(r)].join("\n"))
        logger.debug(['OSM Tags', JSON.dump(tags)].join("\n")) if tags
        logger.debug("#{e}\n\n")
        nil
      end
    }
    bad = bad.select{ |_k, v| v != 0 }.to_h.compact_blank
    return unless !bad.empty? && bad[:pass] != raw.size

    logger.info("    ! #{bad.inspect}")
  end
end
