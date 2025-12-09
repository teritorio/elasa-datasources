# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/sources/tourinsoft_v3_sirtaqui'

class TestTourinsoftV3SirtaquiSource < Test::Unit::TestCase
  def test_date
    assert_equal(
      ['3024-09-21', '3024-09-22', 'Sep 21-Sep 22 12:00+'],
      TourinsoftV3SirtaquiSource.openning([{
        'Heuredefermeture1' => nil,
        'Heuredouverture2' => nil,
        'Datededebut' => '3024-09-21T00:00:00',
        'Heuredefermeture2' => nil,
        'Datedefin' => '3024-09-22T00:00:00',
        'Heuredouverture1' => '12:00:00',
        'Joursdefermeture' => []
        }])
    )
  end
end
