# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'
require 'dotenv/load'
require 'http'
require_relative '../../datasources/sources/open_agenda'


class TestOpenAgendaFetch < Test::Unit::TestCase
  @@api_key = ENV.fetch('OPEN_AGENDA_API_KEY')

  def setup
    @agenda_uid = 214_147
  end

  def test_open_agenda_fetch_all_agendas_in_occitanie
    total = HTTP.follow.get("https://api.openagenda.com/v2/agendas?key=#{@@api_key}&search=Occitanie&official=1").parse['total']
    agendas = OpenAgendaSource.fetch('agendas', { key: @@api_key, search: 'Occitanie', official: 1 }, 'agendas')

    assert_equal(total, agendas.size)
  end

  def test_open_agenda_fetch_all_events_in_occitanie
    total = HTTP.follow.get("https://api.openagenda.com/v2/agendas/#{@agenda_uid}/events?key=#{@@api_key}").parse['total']
    events = OpenAgendaSource.fetch("agendas/#{@agenda_uid}/events", { key: @@api_key }, 'events', 300)

    assert_equal(total, events.size)
  end

  def test_open_agenda_fetch_all_agendas_in_aquitaine
    total = HTTP.follow.get("https://api.openagenda.com/v2/agendas?key=#{@@api_key}&search=Aquitaine&official=1").parse['total']
    agendas = OpenAgendaSource.fetch('agendas', { key: @@api_key, search: 'Aquitaine', official: 1 }, 'agendas')

    assert_equal(total, agendas.size)
  end

  def test_open_agenda_fetch_raise_error_on_incomplete_data
    assert_raise do
      OpenAgendaSource.fetch('agendas', { key: @@api_key, search: 'Normandie', official: 1 }, 'agendas', max_retry: 0, sleeping_time: 0.00)
    end
  end
end
