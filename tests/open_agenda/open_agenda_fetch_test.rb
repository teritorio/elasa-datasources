# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'
require 'http'
require './datasources/sources/open_agenda'


class TestOpenAgendaFetch < Test::Unit::TestCase
  @@api_key = '4d2d1e06a4044b4485b798a9efce4c9c'
  @@agenda_uid = 83_339_747

  def test_open_agenda_fetch_all_agenda_event
    total = HTTP.follow.get("https://api.openagenda.com/v2/agendas/#{@@agenda_uid}/events?key=#{@@api_key}&size=1&timings[gte]=#{Time.now.utc.to_date}").parse['total']
    agendas = OpenAgendaSource.fetch("agendas/#{@@agenda_uid}/events", { key: @@api_key, 'timings[gte]' => Time.now.utc.to_date })

    assert_equal(total, agendas.size)
  end

  def test_open_agenda_fetch_raise_error_on_incomplete_data
    assert_raise do
      OpenAgendaSource.fetch('agendas/-1/events', { key: @@api_key, 'timings[gte]' => Time.now.utc.to_date }, max_retry: 0, sleeping_time: 0.00)
    end
  end
end
