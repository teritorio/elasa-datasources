# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_v3_sirtaqui'


class TourinsoftV3Sirtaqui < Tourinsoft
  def self.source_class
    TourinsoftV3SirtaquiSource
  end
end
