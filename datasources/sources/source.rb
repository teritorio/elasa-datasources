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
end
