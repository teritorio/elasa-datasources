# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_cdt50'
require_relative '../destinations/geojson'


class TourinsoftCdt50 < Tourinsoft
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(TourinsoftCdt50Source, multi_source_id, attribution, settings, source_filter, path)
  end
end
