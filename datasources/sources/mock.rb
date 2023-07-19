# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class MockSource < Source
  def i18n
    @settings['i18n']
  end

  def each
    super([])
  end
end
