# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'


class Connector
  def initialize(multi_source_id, settings, source_filter, path)
    @multi_source_id = multi_source_id
    @settings = settings
    @source_filter = source_filter
    @path = path
  end

  def each
    yield [
      self.class.source_class,
      @multi_source_id,
      @settings,
    ]
  end

  def setup(kiba, params)
    kiba.source(*params)
  end
end
