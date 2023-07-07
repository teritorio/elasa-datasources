# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'csv'
require_relative '../sources/overpass'


class Overpass < CsvConnector
  def self.source_class
    OverpassSource
  end
end
