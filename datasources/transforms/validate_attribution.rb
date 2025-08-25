# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'

require_relative 'transformer'


class ValidateAttributionTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(metadata: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(metadata)
    metadata.data.collect{ |k, m| [k, m.attribution] }.filter{ |k, attribution| !attribution.nil? }.each{ |k, attribution|
      a = T.must(attribution)
      if !a.start_with?('<a') || !a.end_with?('</a>')
        raise "#{k}: attribution should starts with \"<a\" and ends with \"</a>\""
      end
      if !a.include?('target="_blank"')
        raise "#{k}: attribution should include 'target=\"_blank\"'"
      end
    }
    metadata
  end
end
