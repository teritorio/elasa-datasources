# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'

require_relative 'transformer'


class ValidateReportIssueUrlTemplateTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(metadata: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(metadata)
    metadata.data.collect{ |k, m| [k, m.report_issue_url_template] }.select{ |t| !t[1].nil? }.each{ |k, url|
      url = T.must(url)

      # Check we can parse the URL
      URI.parse(url.gsub('}', '').gsub('{', ''))

      # Extract place holders
      placeholders = url.scan(/{(.*?)}/).flatten

      # Ensure lon and lat are included
      if !placeholders.include?('lon') || !placeholders.include?('lat')
        raise "#{k}: report_issue_url_template should include both {lon} and {lat} placeholders: #{url}"
      end

      placeholders -= %w[lon lat]

      if placeholders.any?
        raise "#{k}: report_issue_url_template contains unknown placeholders: #{placeholders.join(', ')}"
      end
    }
    metadata
  end

  sig { override.params(row: Row).returns(T.untyped) }
  def process_data(row)
    row
  end
end
