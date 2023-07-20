# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class I18nSource < Source
  def i18n
    super.merge(
      JSON.load(File.read(@settings['url']))
    )
  end

  def each
    super([])
  end
end
