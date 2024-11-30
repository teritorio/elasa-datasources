# frozen_string_literal: true

require 'test/unit'
require './datasources/sources/datatourisme'

class TestDatatourismeSettings < Test::Unit::TestCase
  def test_datatourisme_expected_settings
    settings = DatatourismeSource::Settings.new({ app_key: 'app_key', source_id: 'id' })
    instance_vars = settings.instance_variables.map(&:to_s)

    expected_vars = %w[@app_key @source_id]
    assert((expected_vars - instance_vars).empty?)
  end

  def test_datatourisme_with_unexpected_settings
    assert_raise(ArgumentError) do
      DatatourismeSource::Settings.new({ app_key: 'app_key', source_id: 'id', unexpected: 'unexpected' })
    end
  end

  def test_datatourisme_missing_settings
    assert_raise(ArgumentError) do
      DatatourismeSource::Settings.new({})
    end
  end
end
