# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft_v3'
require_relative '../sources/tourinsoft_v3_cdt66'


class TourinsoftV3Cdt66 < TourinsoftV3
  def self.source_class
    TourinsoftV3Cdt66Source
  end
end
