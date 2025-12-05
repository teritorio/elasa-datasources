# frozen_string_literal: true
# typed: true

require 'json'
require 'json-schema'
require 'jsonpath'

require_relative 'transformer'


class ValidateReportIssueTransformer < Transformer
  extend T::Generic

  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(metadata: Source::MetadataRow).returns(T.nilable(Source::MetadataRow)) }
  def process_metadata(metadata)
    metadata.data.select{ |_k, m| m.report_issue&.url_template }.each{ |k, m|
      r = T.must(m.report_issue)
      url_template = r.url_template
      value_extractors = r.value_extractors

      # Check we can parse the URL
      URI.parse(url_template.gsub('}', '').gsub('{', ''))

      # Extract place holders
      placeholders = url_template.scan(/{(.*?)}/).flatten.collect{ |s|
        ['.', '/', '?', '&'].include?(s[0]) ? s[1..] : s
      }.compact.collect{ |s|
        ['*'].include?(s[-1]) ? s[..-1] : s
      }.compact.collect{ |s|
        s.reverse.split(':')[0]&.reverse
      }.compact.collect{ |s|
        s.split(',')
      }.flatten.compact.uniq
      value_extractors_keys = (value_extractors&.keys || []).sort

      # Ensure all placeholders have value extractors
      if placeholders != value_extractors_keys
        xor = (placeholders | value_extractors_keys) - (placeholders & value_extractors_keys)
        raise "#{k}: report_issue placeholders and value_extractors keys do not match on keys: #{xor.join(', ')}"
      end

      # Try to compile each extractor as JsonPath
      value_extractors&.collect{ |key, extractor|
        begin
          JsonPath.new(extractor)
        rescue StandardError => e
          raise "#{k}: report_issue value_extractor for key #{key} is not a valid JSONPath: #{extractor} (#{e.message})"
        end
      }
    }
    metadata
  end

  sig { override.params(row: Row).returns(T.untyped) }
  def process_data(row)
    row
  end
end
