# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_cdt50'


class TourinsoftCdt50 < Tourinsoft
  def self.source_class
    TourinsoftCdt50Source
  end
end
