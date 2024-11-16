# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'
require 'dotenv/load'
require 'http'
require_relative '../../datasources/sources/open_agenda'


class TestOpenAgendaFetch < Test::Unit::TestCase
  @@api_key = ENV.fetch('OPEN_AGENDA_API_KEY')

  def test_open_agenda_fetch_all_agendas
    total = HTTP.follow.get("https://api.openagenda.com/v2/agendas?key=#{@@api_key}&search=Occitanie&official=1").parse['total']
    agendas = OpenAgendaSource.fetch('agendas', { key: @@api_key, search: 'Occitanie', official: 1 }, 'agendas')

    assert_equal(total, agendas.size)
  end
end
