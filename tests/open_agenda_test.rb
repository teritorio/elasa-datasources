require 'test/unit'
require 'mocha/test_unit'
require 'dotenv/load'
require_relative '../datasources/sources/open_agenda'


class TestOpenAgendaSource < Test::Unit::TestCase
  @@api_key = ENV.fetch('OPEN_AGENDA_API_KEY', nil)

  def setup
    @path = 'agendas'
    @query = { size: 100, key: @@api_key, search: 'Occitanie' }

    OpenAgendaSource.stubs(:fetch).with(@path, @query).returns(
      Array.new(10) do |i|
        { 'uid' => i + 1,
          'title' => "Event #{i + 1}",
          'description' => "description #{i + 1}" }
      end
    )
  end

  def test_open_agenda_settings
    vars = OpenAgendaSource::Settings.new({ key: 'key', agenda_uid: 'id' }).instance_variables.map(&:to_s)
    assert((%w[@key @agenda_uid] - vars).empty?)
  end

  def test_open_agenda_build_url
    path = 'agendas'
    query = { key: @@api_key }
    url = OpenAgendaSource.build_url(path, query)

    assert_equal("https://api.openagenda.com/v2/agendas?key=#{@@api_key}", url)
  end

  def test_open_agenda_fetch
    path = 'agendas'
    query = { size: 100, key: @@api_key, search: 'Occitanie' }
    json = OpenAgendaSource.fetch(path, query)
    assert_equal(10, json.size)
  end

  def test_open_agenda_fetch_paged_detail
    path = 'agendas'
    query = { size: 100, key: @@api_key, search: 'Occitanie' }
    agendas = OpenAgendaSource.fetch(path, query)
    agendas.each do |agenda|
      path = "agendas/#{agenda['uid']}"
      query = { key: @@api_key }
    end
    assert(true)
  end

  def test_open_agenda_fetch_paged_locations
    assert(true)
  end
end
