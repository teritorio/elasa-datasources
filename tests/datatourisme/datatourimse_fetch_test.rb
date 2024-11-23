# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'
require 'dotenv/load'
require 'http'

require_relative '../../datasources/sources/datatourisme'

class TestDatatourismeFetch < Test::Unit::TestCase
  @@api_key = ENV.fetch('DATATOURISME_API_KEY')
  @@flow_key = ENV.fetch('DATATOURISME_FLOW_KEY')

  def setup
    @url = "https://diffuseur.datatourisme.fr/webservice/#{@@flow_key}/#{@@api_key}"
  end

  def test_datatourisme_fetch_headers
    response = HTTP.follow.get(@url)

    assert_true(response.status.success?)
    assert_true(response.headers['content-type'].include?('application/sparql-results+json'))
  end

  def test_datatourisme_fetch_data
    datas = DatatourismeSource.fetch("#{@@flow_key}/#{@@api_key}")

    assert_not_nil(datas)
    assert_true(datas.is_a?(Array))
  end
end
