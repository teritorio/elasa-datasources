# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_sirtaqui'


class TourinsoftSirtaqui < Tourinsoft
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    super(TourinsoftSirtaquiSource, multi_source_id, attribution, settings, source_filter, path)
  end
end
