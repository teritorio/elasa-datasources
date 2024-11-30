# frozen_string_literal: true

require 'test/unit'
require './datasources/sources/open_agenda'


class TestOpenAgendaSettings < Test::Unit::TestCase
  def test_open_agenda_expected_settings
    settings = OpenAgendaSource::Settings.new({ key: 'key', agenda_uid: 'id' })
    instance_vars = settings.instance_variables.map(&:to_s)

    expected_vars = %w[@key @agenda_uid]
    assert((expected_vars - instance_vars).empty?)
  end

  def test_open_agenda_with_unexpected_settings
    assert_raise(ArgumentError) do
      OpenAgendaSource::Settings.new({ key: 'key', agenda_uid: 'id', unexpected: 'unexpected' })
    end
  end

  def test_open_agenda_missing_settings
    assert_raise(ArgumentError) do
      OpenAgendaSource::Settings.new({})
    end
  end
end
