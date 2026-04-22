# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_v3_cdt66'


class TourinsoftV3Cdt66 < Tourinsoft
  def self.source_class
    TourinsoftV3Cdt66Source
  end
end
