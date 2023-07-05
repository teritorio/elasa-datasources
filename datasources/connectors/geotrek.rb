# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/geotrek'


class Geotrek < Connector
  def initialize(multi_source_id, settings, source_filter, path)
    super(multi_source_id, settings, source_filter, path)
    yield [
      self,
      multi_source_id,
      [GeotrekSource, settings]
    ]
  end
end
