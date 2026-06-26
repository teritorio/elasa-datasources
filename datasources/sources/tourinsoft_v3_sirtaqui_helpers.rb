# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

module TourinsoftSirtaquiHelpers
  include TourinsoftSirtaquiMixin

  def jp_first_present(object, *paths)
    paths.lazy.map { |path| jp_first(object, path) }.find(&:present?)
  end

  def first_present(hash, *keys)
    keys.lazy.map { |k| hash[k] }.find(&:itself)
  end

  module_function :first_present

  def valid_url(id, tag, url)
    return if url.blank?

    valid = url =~ URI::DEFAULT_PARSER.make_regexp && url.start_with?('https://') && url.split('/')[2].include?('.') && !url.split('/')[2].include?(' ')
    if !valid
      logger.info("Invalid URL for #{id}: #{tag}=#{url}")
    end
    valid ? url : nil
  end

  def route(routes, distance)
    routes&.select{ |r| !r['Modedelocomotion'].nil? }&.collect{ |r|
      practice = r['Modedelocomotion']['ThesLibelle']
      duration = r['Tempsdeparcours']
      # distance = distance.gsub(',', '.').to_f
      difficulty = r['Difficulte'] && r['Difficulte']['ThesLibelle']

      practice_slug = TourinsoftSirtaquiMixin::PRACTICES[practice]

      duration &&= route_duration(duration)

      {
        "#{practice_slug}": {
          difficulty: TourinsoftSirtaquiMixin::DIFFICULTIES[difficulty],
          duration: duration,
          length: distance,
        }.compact_blank
      }.compact_blank
    }
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat.last['GmapLongitude'].to_f,
        feat.last['GmapLatitude'].to_f
      ]
    }
  end

  def addr(address)
    return nil if address.nil?

    {
      street: [address['Adresse1'], address['Adresse1suite'], address['Adresse2'], address['Adresse3']].compact_blank.join(', '),
      postcode: address['CodePostal'],
      city: address['Commune'],
    }.compact_blank
  end

  def pdfs(pdf)
    {
      'en-US' => jp(pdf, '.FichePDFGB.Url')&.first,
      'fr-FR' => jp(pdf, '.FichePDFFR.Url')&.first,
      'es-ES' => jp(pdf, '.FichePDFES.Url')&.first,
    }.compact_blank
  end

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
