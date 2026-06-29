# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'
require_relative 'tourinsoft_v3_sirtaqui_helpers'


class TourinsoftV3Cdt87Source < TourinsoftV3Source
  extend T::Sig
  include TourinsoftSirtaquiHelpers
  include TourinsoftSirtaquiMixin

  class Settings < TourinsoftV3Source::Settings
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { returns(SchemaRow) }
  def schema
    super.deep_merge_array(SchemaRow.from_hash({
      'i18n' => {
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
    }))
  end

  def map_feature_tags(feat)
    r = feat

    date_on, date_off, osm_openning_hours = openning(r['PeriodeOuvertures'])

    id = map_id([nil, r])
    {
      ref: {
        'FR:CRTA': id,
      },
      name: { 'fr-FR' => r['SyndicObjectName'] }.compact_blank,
      description: { 'fr-FR' => jp_first(r, '.DescriptionsCommercialess[*].Descriptioncommerciale') }.compact_blank,
      website: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Site web (URL)")]')&.pluck('CoordonneesTelecom')&.collect{ |url| valid_url(id, :website, url) }&.compact_blank,
      'website:details': { 'fr-FR' => valid_url(id, :'website:details', @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID'])) }.compact_blank,
      phone: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Téléphone filaire" || @.TypedaccesTelecom.ThesLibelle=="Téléphone cellulaire")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      email: jp(r, '.MoyensDeComs[*][?(@.TypedaccesTelecom.ThesLibelle=="Mél")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.ReseauxSociauxs[*].Facebook')),
      twitter: valid_url(id, :twitter, jp_first(r, '.ReseauxSociauxs[*].X')),
      instagram: valid_url(id, :instagram, jp_first(r, '.ReseauxSociauxs[*].Instagram')),
      linkedin: jp_first(r, '.ReseauxSociauxs[*].Linkedin'),
      pinterest: jp_first(r, '.ReseauxSociauxs[*].Pinterest'),
      # jp_first(r, '.ReseauxSociauxs[0].GoogleMyBusiness'),
      image: jp(r, '.Photoss[*].Photo.Url'),
      addr: addr(jp_first(r, '.AdresseCompletes[*]')),
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r['LocomotionTempDifficultes'], r['Distance'])&.inject({
        gpx_trace: jp_first(r, '.Fichierss[*].TraceGPX.Url'),
        pdf: pdfs(jp_first(r, '.Fichierss[*]')),
      }, :merge)&.compact_blank,
      'capacity:beds': jp_first(r, '.Capacites[*].Nombretotaldelits')&.to_i,
      'capacity:rooms': (jp_first(r, '.Capacites[*].Nombretotaldechambres') || jp_first(r, '.Capacites[*].Nombredechambres'))&.to_i,
      'capacity:persons': jp_first(r, '.Capacites[*].Capacitemaximum')&.to_i,
      # 'capacity:caravans': r['NBRECARAVANES']&.to_i,
      # 'capacity:cabins': r['NBREMHOME']&.to_i,
      'capacity:pitches': jp_first(r, '.Capacites[*].Nombretotaldemplacements')&.to_i,
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
