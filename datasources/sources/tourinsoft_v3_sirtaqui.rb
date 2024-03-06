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

  def jp(object, path)
    JsonPath.on(object, "$.#{path}")
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
          'values' => TourinsoftSirtaquiMixin::PRACTICES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr' => v } } }
        }
      }.merge(
        *TourinsoftSirtaquiMixin::PRACTICES.values.collect { |practice|
          {
            "route:#{practice}:difficulty" => {
              'values' => TourinsoftSirtaquiMixin::DIFFICULTIES.compact.to_a.to_h(&:reverse).transform_values{ |v| { '@default:full' => { 'fr' => v } } }
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
    nil if feat.dig('AdresseCompletes', 0).nil?

    {
      street: [feat['AdresseCompletes'][0]['Adresse1'], feat['AdresseCompletes'][0]['Adresse2'], feat['AdresseCompletes'][0]['Adresse3']].compact_blank.join(', '),
      postcode: feat['AdresseCompletes'][0]['CodePostal'],
      city: feat['AdresseCompletes'][0]['Commune'],
    }.compact_blank
  end

  def pdfs(feat)
    {
      'en' => jp(feat, '.Fichierss[*].FichePDFGB.Url')&.first,
      'fr' => jp(feat, '.Fichierss[*].FichePDFFR.Url')&.first,
      'es' => jp(feat, '.Fichierss[*].FichePDFES.Url')&.first,
    }.compact_blank
  end

  def map_tags(feat)
    r = feat

    # if r['OUVERTURECOMPLET']
    #   date_on, date_off, osm_openning_hours = self.class.openning(
    #     r['OUVERTURECOMPLET'],
    #     :openning_seven_days
    #   )
    # elsif r['OUVERTURE'] || r['DATESCOMPLET']
    #   date_on, date_off, osm_openning_hours = self.class.openning(
    #     r['OUVERTURE'] || r['DATESCOMPLET'],
    #     :openning_one_days
    #   )
    # end

    id = map_id(r)
    {
      ref: {
        'FR:CRTA': id,
      },
      name: { fr: r['SyndicObjectName'] }.compact_blank,
      description: { fr: jp(r, '.DescriptionsCommercialess[*].Descriptioncommerciale')&.first }.compact_blank,
      website: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Site web (URL)")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      'website:details': { fr: @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID']) }.compact_blank,
      phone: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Téléphone filaire")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      email: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Mél")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      facebook: valid_url(id, :facebook, jp(r, '.ReseauxSociauxs[*].Facebook')&.first),
      twitter: valid_url(id, :twitter, jp(r, '.ReseauxSociauxs[*].Twitter')&.first),
      instagram: valid_url(id, :instagram, jp(r, '.ReseauxSociauxs[*].Instagram')&.first),
      'contact:linkedin': jp(r, '.ReseauxSociauxs[*].Linkedin')&.first,
      'contact:pinterest': jp(r, '.ReseauxSociauxs[*].Pinterest')&.first,
      # jp(r, '.ReseauxSociauxs[0].GoogleMyBusiness')&.first,
      image: jp(r, '.Photoss[*].Photo.Url')&.compact_blank,
      addr: addr(r),
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r['LocomotionTempDifficultes'], r['Distance'])&.inject({
        gpx_trace: jp(r, '.Fichierss[*].TraceGPX.Url')&.first,
        pdf: pdfs(r),
      }, :merge)&.compact_blank,
      'capacity:beds': jp(r, '.Capacites[*].Nombretotaldelits')&.first&.to_i,
      'capacity:rooms': jp(r, '.Capacites[*].Nombretotaldechambres')&.first&.to_i,
      # 'capacity:persons': r['CAPA']&.to_i,
      # 'capacity:caravans': r['NBRECARAVANES']&.to_i,
      # 'capacity:cabins': r['NBREMHOME']&.to_i,
      # 'capacity:pitches': r['NBREEMP']&.to_i,
      #   opening_hours: osm_openning_hours,
      stars: r['ObjectTypeName']&.include?('Hôtel') ? TourinsoftSirtaquiMixin::CLASS[r.dig('ClassementPrefectoral', 'ThesLibelle')] : nil,
      internet_access: jp(r, '.PrestationsConfortss[*][?(@.ThesLibelle=="Wifi")]').any? ? 'wlan' : nil,
    }.merge(
      #   r['ObjectTypeName'] == 'Fêtes et manifestations' && {
      #     start_date: date_on,
      #     end_date: date_off,
      #     event: multiple_split(r, ['CATFMA']).collect{ |t| TourinsoftSirtaquiMixin::EVENT_TYPE[t] },
      #   } || {},
      r['ObjectTypeName'] == 'Restauration' ? cuisines(jp(r, '.ClassificationTypeCuisines[*].ThesLibelle')&.compact_blank) : {},
      r['ObjectTypeName'] == 'Hôtel' ? { tourism: 'hotel' } : {},
    )
  end
end
