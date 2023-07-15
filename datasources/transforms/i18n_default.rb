# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'

require_relative 'transformer'


class I18nDefaultTransformer < Transformer
  def initialize(settings)
    super(settings)

    @i18n_default = JSON.parse(File.new('datasources/transforms/i18n_default.json').read)
  end

  def process_i18n(i18n)
    @i18n_default.merge(i18n)
  end

  def process_data(row)
    row
  end
end
