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
  def initialize(source_id, attribution, _settings, path)
    @source_id = source_id
    @attribution = attribution
    @path = path
  end

  def each(raw)
    puts "#{self.class.name}: #{raw.size}"

    raw.each{ |r|
      begin
        osm = map(r)
        if !osm.nil?
          yield osm
        end
      rescue StandardError => e
        puts 'Native', JSON.dump(r)
        puts 'OSM', JSON.dump(osm)
        raise e
      end
    }
  end
end
