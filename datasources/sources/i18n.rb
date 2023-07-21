# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class I18nSource < Source
  def i18n
    @settings['urls'].collect{ |url| JSON.parse(File.read(url)) }.inject(super, &:deep_merge)
  end

  def each
    super([])
  end
end
