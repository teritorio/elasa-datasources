# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class RefsIntegrityTransformer < Transformer
  extend T::Generic
  SettingsType = type_member{ { upper: Transformer::TransformerSettings } } # Generic param

  sig { params(settings: Transformer::TransformerSettings).void }
  def initialize(settings)
    super(settings)
    @ids = []
    @refs = []
  end

  def process_data(row)
    @ids << row['id']
    @refs << row['refs']
    row
  end

  def close_data
    logger.info("#{self.class.name}: #{@ids.size}")

    missing_ids = @refs.flatten - @ids
    raise "Referencial integrity fails for refs #{missing_ids.join(', ')}" if missing_ids.present?
  end
end
