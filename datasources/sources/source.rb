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
  def initialize(source_id, attribution, settings)
    @source_id = source_id
    @attribution = attribution
    @settings = settings
  end

  def map_destination_id(_feat)
    nil
  end

  def map_source(_feat)
    @attribution
  end

  def map_native_properties(_feat, _properties)
    nil
  end

  def each(raw)
    puts "#{self.class.name}: #{raw.size}"

    raw.each{ |r|
      begin
        id = map_id(r)
        next if id.blank?

        updated_at = map_updated_at(r)
        next if updated_at.blank?

        geometry = map_geometry(r)
        next if geometry.blank? || (geometry[:type] == 'Point' && geometry[:coordinates] == [0.0, 0.0])

        tags = map_tags(r)
        next if tags.blank?

        yield ({
          destination_id: map_destination_id(r),
          type: 'Feature',
          geometry: geometry,
          properties: {
            id: id,
            updated_at: updated_at,
            source: map_source(r),
            tags: tags.compact_blank,
            natives: @settings['native_properties'] && map_native_properties(r, @settings['native_properties'])&.compact_blank,
          }.compact_blank,
        }.compact_blank)
      rescue StandardError => e
        puts 'Native', JSON.dump(r)
        puts 'OSM Tags', JSON.dump(tags) if tags
        raise e
      end
    }
  end
end
