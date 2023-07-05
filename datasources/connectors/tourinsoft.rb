# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourinsoft'


class Tourinsoft < Connector
  def initialize(source_class, multi_source_id, attribution, settings, source_filter, path)
    super(multi_source_id, attribution, settings, source_filter, path)

    settings['syndications'].select{ |name, _syndication|
      source_filter.nil? || name.start_with?(source_filter)
    }.each{ |name, syndication|
      yield [
        self,
        name,
        [source_class, name, attribution, settings.merge({ 'syndication' => syndication })]
      ]
    }
  end
end
