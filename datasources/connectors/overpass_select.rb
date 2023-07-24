# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'csv'
require_relative '../sources/overpass_select'


class OverpassSelect < CsvConnector
  def self.source_class
    OverpassSelectSource
  end
end
