# frozen_string_literal: true
# typed: true

require_relative 'csv'

require 'sorbet-runtime'

require_relative 'source'


class InseeBpeSource < CsvSource
  class Settings < CsvSource::Settings
    const :code_labels, T::Hash[String, T::Hash[String, String]]
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  def metadatas
    super + @settings.code_labels.collect{ |code, name|
      MetadataRow.new({
        data: {
          "#{code[0]}-#{code[0..1]}-#{code}" => Metadata.from_hash({
            'name' => name,
            'attribution' => @settings.metadata.attribution,
            'report_issue' => @settings.metadata.report_issue,
          })
        }.compact_blank
      })
    }
  end

  def select?(feat)
    super && @settings.code_labels.include?(feat['TYPEQU'])
  end
end
