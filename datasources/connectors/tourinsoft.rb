# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

require_relative 'connector'
require_relative '../sources/tourinsoft'


class Tourinsoft < Connector
  def each
    @settings['syndications'].select{ |name, _syndication|
      @source_filter.nil? || name.start_with?(@source_filter)
    }.each{ |name, syndication|
      yield [
        self,
        name,
        [self.class.source_class, @settings.merge({ 'syndication' => syndication })]
      ]
    }
  end
end
