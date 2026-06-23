# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_v3_cdt87'


class TourinsoftV3Cdt87 < Tourinsoft
  def self.source_class
    TourinsoftV3Cdt87Source
  end
end
