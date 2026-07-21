# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

module TourinsoftV3Helpers
  include TourinsoftSirtaquiMixin

  def jp_first_present(object, *paths)
    paths.lazy.map { |path| jp_first(object, path) }.find(&:present?)
  end

  def first_present(hash, *keys)
    keys.lazy.map { |k| hash[k] }.find(&:itself)
  end

  module_function :first_present

  @@days = HashExcep[{
    'lundi' => 'Mo',
    'mardi' => 'Tu',
    'mercredi' => 'We',
    'jeudi' => 'Th',
    'vendredi' => 'Fr',
    'samedi' => 'Sa',
    'dimanche' => 'Su',
  }]

  def date_on_off(periode_ouvertures)
    current_time = Time.current.strftime('%Y-%m-%d')
    periode_ouverture_next = periode_ouvertures.collect{ |periode_ouverture|
      [
        periode_ouverture['Datededebut'] || periode_ouverture['Datedebut'],
        periode_ouverture['Datedefin'] || periode_ouverture['Datefin'],
        periode_ouverture,
      ]
    }.select{ |datededebut, datedefin, _periode_ouverture|
      !(datededebut.nil? && datedefin.nil?) &&
        (datedefin.nil? || datedefin[0..9] >= current_time)
    }.min_by{ |datededebut, datedefin, _periode_ouverture|
      [datededebut || '0', datedefin || '9999']
    }

    return if periode_ouverture_next.nil?

    date_on = periode_ouverture_next[0]&.[](0..9)
    date_off = periode_ouverture_next[1]&.[](0..9)
    periode_ouverture = periode_ouverture_next[2]

    [periode_ouverture, date_on, date_off]
  end

  module_function :date_on_off

  def openning(periode_ouvertures)
    return nil if periode_ouvertures.blank?

    # close_days = convert(periode_ouvertures['Joursdefermeture']) ## TODO

    date_ons = []
    date_offs = []

    result = periode_ouvertures.collect { |periode_ouverture|
      hours = (
        if periode_ouverture.key?('Heuredouverture1')
          %w[Heuredouverture1 Heuredefermeture1 Heuredouverture2 Heuredefermeture2].collect{ |h| periode_ouverture[h] }.map{ |h|
            h.nil? ? nil : h[..-4]
          }.each_slice(2).collect { |open, close|
            open.nil? ? nil : open + (close.nil? ? '+' : "-#{close}")
          }.compact.join('; ')
        else
          %w[lundi mardi mercredi jeudi vendredi samedi dimanche].collect{ |d|
            [%w[heuredebut1 heurefin1 heuredebut2 heurefin2].collect{ |h| periode_ouverture["#{d}#{h}"] }.map{ |h|
              h.nil? ? nil : h[..-4]
            }, @@days[d]]
          }.group_by(&:first).transform_values{ |hours_days|
            hours_days.collect(&:last)
          }.collect{ |hours, days|
            if hours[1].nil? && hours[2].nil? && !hours[3].nil?
              hours[1] = hours[3]
              hours[3] = nil
            end

            dayss = days.size == 7 ? '' : "#{days.join(',')} "

            days_hours = hours.each_slice(2).collect { |open, close|
              open.nil? ? nil : (open + (close.nil? ? '+' : "-#{close}"))
            }.compact_blank

            next if days_hours.empty?

            dayss + days_hours.join(',')
          }.flatten.compact.join('; ')
        end
      )

      date_on = first_present(periode_ouverture, 'Datedebut', 'Datededebut')&.[](0..9)
      date_off = first_present(periode_ouverture, 'Datefin', 'Datedefin')&.[](0..9)

      date_ons << date_on
      date_offs << date_off

      dates = TourinsoftSirtaquiMixin::FORMAT_MONTH_RANGE.call(date_on, date_off)

      [dates, hours].compact.join(' ')
    }.compact_blank.join(';').presence
    [date_ons.compact.min, date_offs.compact.max, result]
  end

  module_function :openning
end
