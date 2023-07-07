# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/geotrek'


class Geotrek < Connector
  def each
    yield [
      self,
      @multi_source_id,
      [GeotrekSource, @settings]
    ]
  end
end
