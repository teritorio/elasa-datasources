# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/sources/tourism_system'

class TestTourismSystemSource < Test::Unit::TestCase
  def test_date
    assert_equal(
      ['2023-12-02', '2023-12-02', 'Dec 02'],
      TourismSystemSource.openning([{
        'type' => '09.01.05',
        'startDate' => '2023-12-02T00:00:00+01:00',
        'endDate' => '2023-12-02T23:59:59+01:00',
      }])
    )
  end

  def test_day
    assert_equal(
      ['2023-12-02', '2023-12-02', 'Dec 02 Th,Fr 10:00-21:00'],
      TourismSystemSource.openning([{
        'type' => '09.01.05',
        'startDate' => '2023-12-02T00:00:00+01:00',
        'endDate' => '2023-12-02T23:59:59+01:00',
        'days' => [{
          'type' => '09.03.02',
          'days' => [
            { 'day' => '09.02.05', 'schedules' => [{ 'startTime' => '10:00:00', 'endTime' => '21:00:00' }] },
            { 'day' => '09.02.06', 'schedules' => [{ 'startTime' => '10:00:00', 'endTime' => '21:00:00' }] },
          ]
        }]
      }])
    )
  end

  def test_day_hour
    assert_equal(
      ['2023-12-02', '2023-12-03', 'Dec 02-Dec 03 14:00-16:00'],
      TourismSystemSource.openning([{
        'type' => '09.01.05',
        'startDate' => '2023-12-02T00:00:00+01:00',
        'endDate' => '2023-12-03T23:59:59+01:00',
        'days' => [{
          'type' => '09.03.02',
          'days' => [{
            'day' => '09.02.08',
            'schedules' => [{
              'startTime' => '14:00:00',
              'endTime' => '16:00:00'
            }]
          }]
        }]
      }])
    )
  end

  def test_periods
    assert_equal(
      ['2023-04-20', '2023-04-22', 'Apr 20 14:30-16:30;Apr 21-Apr 22 10:30+,14:30+'],
      TourismSystemSource.openning([{
        'type' => '09.01.05',
        'startDate' => '2023-04-20T00:00:00+02:00',
        'endDate' => '2023-04-20T23:59:59+02:00',
        'days' => [{
          'type' => '09.03.02',
          'days' => [
            { 'day' => '09.02.08', 'schedules' => [{ 'startTime' => '14:30:00', 'endTime' => '16:30:00' }] }
          ]
        }]
      }, {
        'type' => '09.01.05',
        'startDate' => '2023-04-21T00:00:00+02:00',
        'endDate' => '2023-04-22T23:59:59+02:00',
        'days' => [{
          'type' => '09.03.02',
          'days' => [
            { 'day' => '09.02.08', 'schedules' => [{ 'startTime' => '10:30:00' }, { 'startTime' => '14:30:00' }] }
          ]
        }]
      }])
    )
  end
end
