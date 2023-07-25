# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require_relative 'source'


class SchemaSource < Source
  def load(urls)
    urls&.collect{ |url|
      JSON.parse(File.read(url))
    }
  end

  def schema
    super.deep_merge_array({
      schema: load(@settings['schema'])&.inject({}, &:deep_merge_array),
      i18n: load(@settings['i18n'])&.inject({}, &:deep_merge_array),
    })
  end

  def each
    super([])
  end
end
