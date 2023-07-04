# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/sources/tourinsoft_sirtaqui'

class TestTourinsoftSirtaquiSource < Test::Unit::TestCase
  def test_date
    assert_equal(
      ['2023-11-01', '2023-12-22', 'Nov 01-Dec 22'],
      TourinsoftSirtaquiSource.openning('01/11/2023|22/12/2023')
    )
  end

  def test_hour_multi
    assert_equal(
      ['2023-10-21', '2023-12-31', 'Oct 21-Nov 05 Tu,We,Th,Fr,Sa 10:00-12:30,15:30-19:00;Nov 06-Dec 31 We,Th,Fr,Sa 15:30-19:00'],
      TourinsoftSirtaquiSource.openning('21/10/2023|05/11/2023|10:00|12:30|15:30|19:00|Lundi-Dimanche#06/11/2023|31/12/2023|||15:30|19:00|Lundi-Mardi-Dimanche')
    )
  end

  def test_hour_no_clode
    assert_equal(
      ['2023-10-21', '2023-11-05', 'Oct 21-Nov 05 Tu,We,Th,Fr,Sa,Su 10:00+'],
      TourinsoftSirtaquiSource.openning('21/10/2023|05/11/2023|10:00||||Lundi')
    )
  end
end
