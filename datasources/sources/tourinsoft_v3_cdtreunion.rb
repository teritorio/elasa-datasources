# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'
require_relative 'tourinsoft_v3_helpers'


class TourinsoftV3CdtreunionSource < TourinsoftV3Source
  extend T::Sig
  include TourinsoftV3Helpers

  class Settings < TourinsoftV3Source::Settings
    const :gpx_trace_url, T.nilable(String)
  end

  extend T::Generic

  SettingsType = type_member{ { upper: Settings } } # Generic param

  def map_geometry(type_feat)
    _type, feat = type_feat
    {
      type: 'Point',
      coordinates: [
        feat['GmapLongitude'].to_f,
        feat['GmapLatitude'].to_f
      ]
    }
  end

  def map_feature_tags(feat)
    r = feat

    _date_on, _date_off, osm_openning_hours = openning(r['PeriodeOuvertures'])

    id = map_id([nil, r])
    {
      ref: {
        'FR:CRT974': id,
        'FR:SIRET': r['SIRET'],
      }.compact_blank,
      name: { 'fr-FR' => r['SyndicObjectName'] }.compact_blank,
      description: { 'fr-FR' => jp_first(r, '.Descriptifss[*].Descriptioncommerciale') }.compact_blank,
      website: jp(r, '.Moyencommunications[*][?(@.Moyendecommunication.ThesLibelle=="Site web (url)")]')&.pluck('Coordonnees')&.collect{ |url| valid_url(id, :website, url) }&.compact_blank,
      'website:details': { 'fr-FR' => valid_url(id, :'website:details', @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID'])) }.compact_blank,
      phone: jp(r, '.Moyencommunications[*][?(@.Moyendecommunication.ThesLibelle=="Tél. fixe" || @.Moyendecommunication.ThesLibelle=="Tél. mobile")]')&.pluck('Coordonnees')&.compact_blank,
      email: jp(r, '.Moyencommunications[*][?(@.Moyendecommunication.ThesLibelle=="Mail")]')&.pluck('Coordonnees')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.Reseauxsociauxs[*][?(@.Typedeplateforme.ThesLibelle=="Facebook")].URL')),
      twitter: valid_url(id, :twitter, jp_first(r, '.Reseauxsociauxs[*][?(@.Typedeplateforme.ThesLibelle=="Twitter")].URL')),
      instagram: valid_url(id, :instagram, jp_first(r, '.Reseauxsociauxs[*][?(@.Typedeplateforme.ThesLibelle=="Instagram")].URL')),

      image: jp(r, '.Photos[*].Photo.Url'),
      addr: addr(r),
      'capacity:beds': jp_first(r, '.Capacites[*].Nombredelits')&.to_i,
      'capacity:rooms': jp_first(r, '.Capacites[*].Nombretotaldechambres')&.to_i,
      'capacity:persons': jp_first(r, '.Capacites[*].Capacitetotalenombredepersonnes')&.to_i,
      opening_hours: osm_openning_hours,
      stars: ['Hébergements locatifs', 'Hôtellerie', 'Hôtellerie de plein air', 'Résidences'].include?(r['ObjectTypeName']) ? TourinsoftSirtaquiMixin::CLASS[r['ClassementPrefectoral']] : nil,
      # internet_access: jp(r, '.Servicess[*][?(@.ThesLibelle=="Wifi")]').any? ? 'wlan' : nil,
      # pets: { true => 'yes', false => 'no' }[r['Animaux']]
    }.merge(
        r['ObjectTypeName'] == 'Restauration' ? cuisines(jp(r, '.Typecuisines[*].ThesLibelle')) : {},
        r['ObjectTypeName'] == 'Hôtellerie' ? { tourism: 'hotel' } : {},
      )
  end
end
