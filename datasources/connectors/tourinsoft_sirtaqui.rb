# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'tourinsoft'
require_relative '../sources/tourinsoft_sirtaqui'


class TourinsoftSirtaqui < Tourinsoft
  def self.source_class
    TourinsoftSirtaquiSource
  end
end
