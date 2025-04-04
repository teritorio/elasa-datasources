# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'


class TourinsoftV3SirtaquiSource < TourinsoftV3Source
  extend T::Sig
  include TourinsoftSirtaquiMixin

  class Settings < TourinsoftV3Source::Settings
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

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

  sig { returns(SchemaRow) }
  def schema
    super.with(
      i18n: {
        'route' => {
          'values' => TourinsoftSirtaquiMixin::PRACTICES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr-FR' => v } } }
        }
      }.merge(
        *TourinsoftSirtaquiMixin::PRACTICES.values.collect { |practice|
          {
            "route:#{practice}:difficulty" => {
              'values' => TourinsoftSirtaquiMixin::DIFFICULTIES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr-FR' => v } } }
            }
          }
        }
      )
    )
  end

  def map_geometry(feat)
    {
      type: 'Point',
      coordinates: [
        feat['GmapLongitude'].to_f,
        feat['GmapLatitude'].to_f
      ]
    }
  end

  def addr(feat)
    return nil if feat.dig('AdresseCompletes', 0).nil?

    {
      street: [feat['AdresseCompletes'][0]['Adresse1'], feat['AdresseCompletes'][0]['Adresse2'], feat['AdresseCompletes'][0]['Adresse3']].compact_blank.join(', '),
      postcode: feat['AdresseCompletes'][0]['CodePostal'],
      city: feat['AdresseCompletes'][0]['Commune'],
    }.compact_blank
  end

  def pdfs(feat)
    {
      'en-US' => jp(feat, '.Fichierss[*].FichePDFGB.Url')&.first,
      'fr-FR' => jp(feat, '.Fichierss[*].FichePDFFR.Url')&.first,
      'es-ES' => jp(feat, '.Fichierss[*].FichePDFES.Url')&.first,
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

  def self.date_on_off(periode_ouvertures)
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

  def self.openning(periode_ouvertures)
    return nil if periode_ouvertures.blank?

    periode_ouverture, date_on, date_off = date_on_off(periode_ouvertures)

    return nil if periode_ouverture.nil?

    # close_days = convert(periode_ouvertures['Joursdefermeture']) ## TODO

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
          hours.each_slice(2).collect { |open, close|
            dayss = days.size == 7 ? '' : "#{days.join(',')} "
            open.nil? ? nil : (dayss + open + (close.nil? ? '+' : "-#{close}"))
          }
        }.flatten.compact.join('; ')
      end
    )

    dates = TourinsoftSirtaquiMixin::FORMAT_MONTH_RANGE.call(date_on, date_off)

    [date_on, date_off, [dates, hours].compact.join(' ')]
  end

  def map_tags(feat)
    r = feat

    date_on, date_off, osm_openning_hours = self.class.openning(r['PeriodeOuvertures'])

    id = map_id(r)
    {
      ref: {
        'FR:CRTA': id,
      },
      name: { 'fr-FR' => r['SyndicObjectName'] }.compact_blank,
      description: { 'fr-FR' => jp_first(r, '.DescriptionsCommercialess[*].Descriptioncommerciale') }.compact_blank,
      website: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Site web (URL)")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      'website:details': { 'fr-FR' => @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Téléphone filaire" || @.TypedaccesTelecom.ThesLibelle=="Téléphone cellulaire")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      email: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Mél")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.ReseauxSociauxs[*].Facebook')),
      twitter: valid_url(id, :twitter, jp_first(r, '.ReseauxSociauxs[*].X')),
      instagram: valid_url(id, :instagram, jp_first(r, '.ReseauxSociauxs[*].Instagram')),
      linkedin: jp_first(r, '.ReseauxSociauxs[*].Linkedin'),
      pinterest: jp_first(r, '.ReseauxSociauxs[*].Pinterest'),
      # jp_first(r, '.ReseauxSociauxs[0].GoogleMyBusiness'),
      image: jp(r, '.Photoss[*].Photo.Url'),
      addr: addr(r),
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r['LocomotionTempDifficultes'], r['Distance'])&.inject({
        gpx_trace: jp_first(r, '.Fichierss[*].TraceGPX.Url'),
        pdf: pdfs(r),
      }, :merge)&.compact_blank,
      'capacity:beds': jp_first(r, '.Capacites[*].Nombretotaldelits')&.to_i,
      'capacity:rooms': jp_first(r, '.Capacites[*].Nombretotaldechambres')&.to_i,
      # 'capacity:persons': r['CAPA']&.to_i,
      # 'capacity:caravans': r['NBRECARAVANES']&.to_i,
      # 'capacity:cabins': r['NBREMHOME']&.to_i,
      # 'capacity:pitches': r['NBREEMP']&.to_i,
      opening_hours: osm_openning_hours,
      stars: ['Campings', 'Hébergements locatifs (meublés et chambres d\'hôtes)', 'Hôtels', 'Résidences', 'Villages Vacances'].include?(r['ObjectTypeName']) ? TourinsoftSirtaquiMixin::CLASS[r.dig('ClassementPrefectoral', 'ThesLibelle')] : nil,
      internet_access: jp(r, '.PrestationsConfortss[*][?(@.ThesLibelle=="Wifi")]').any? ? 'wlan' : nil,
    }.merge(
        r['ObjectTypeName'] == 'Fêtes et manifestations' && {
          start_date: date_on,
          end_date: date_off,
          event: jp(r, '.ClassificationCategoriesFMAs[*].ThesLibelle').collect{ |t| TourinsoftSirtaquiMixin::EVENT_TYPE[t] }.uniq,
        } || {},
        r['ObjectTypeName'] == 'Restauration' ? cuisines(jp(r, '.ClassificationTypeCuisines[*].ThesLibelle')) : {},
        r['ObjectTypeName'] == 'Hôtel' ? { tourism: 'hotel' } : {},
      )
  end
end
