# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'
require_relative 'tourinsoft_v3'
require_relative 'tourinsoft_v3_sirtaqui_helpers'


class TourinsoftV3Cdt40Source < TourinsoftV3Source
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

  def extract_steps_from_feature(feature)
    feature['ETAPESs']&.collect{ |step|
      {
        'name' => step['NomEtape']&.presence,
        'description' => step['Descriptif']&.presence,
        'GmapLongitude' => step['Longitudedecimalegooglemap']&.presence,
        'GmapLatitude' => step['Latitudedecimalegooglemap']&.presence,
        'image' => step.dig('Photo', 'Url')&.presence,
      }
    }&.select{ |step| !step['GmapLongitude'].nil? && !step['GmapLatitude'].nil? }&.each_with_index&.collect{ |step, index|
      step['SyndicObjectID'] = "#{map_id([nil, feature])}.#{@destination_id}.#{index}"
      step['name'] = [step['id'], step['name']].compact.join(' - ') if !step['id'].nil? && !step['name'].nil?
      step['GmapLongitude'] = step['GmapLongitude']&.to_f
      step['GmapLatitude'] = step['GmapLatitude']&.to_f
      step['Updated'] = feature['Updated']
      step['waypoint:type'] = 'waypoint'
      step.compact
    } || []
  end

  def map_tags(type_feat)
    r = super
    return r if !r.nil?

    type, feat = type_feat
    type == :step ? map_step_tags(feat) : nil
  end

  def map_step_tags(feat)
    r = feat
    id = map_id([nil, r])
    {
      ref: {
        'FR:CRTA.step': id,
      },
      name: { 'fr-FR' => r['name'] }.compact_blank,
      description: { 'fr-FR' => r['description'] }.compact_blank,
      image: [r['image']].compact,
      # image_description
      # image_source
      route: {
        'waypoint:type': r['waypoint:type'],
      },
    }
  end

  def map_feature_tags(feat)
    r = feat

    date_on, date_off, osm_openning_hours = openning(r['OUVERTUREs'])

    id = map_id([nil, r])
    {
      ref: {
        'FR:CRTA': id,
      },
      name: { 'fr-FR' => jp_first(r, '.NOMOFFREs[*].Raisonsociale') }.compact_blank,
      description: { 'fr-FR' => jp_first_present(r, '.DESCRIPTIFSs[*].Descriptioncommerciale', '.DESCRIPTIFs[*].Description', '.DESCRIPTIFs[*].Descriptif', '.DESCRIPTIFs[*].Descriptifcommercial') }.compact_blank,
      website: jp(r['MOYENSCOMs'] || r['MOYENCOMs'], '[*][?(@.TypedaccesTelecom.ThesLibelle=="Site web (URL)")]')&.pluck('CoordonneesTelecom')&.collect{ |url| valid_url(id, :website, url) }&.compact_blank,
      'website:details': { 'fr-FR' => valid_url(id, :'website:details', @settings.website_details_url&.gsub('{{id}}', r['SyndicObjectID'])) }.compact_blank,
      phone: jp(r['MOYENSCOMs'] || r['MOYENCOMs'], '[*][?(@.TypedaccesTelecom.ThesLibelle=="Téléphone filaire" || @.TypedaccesTelecom.ThesLibelle=="Téléphone cellulaire")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      email: jp(r['MOYENSCOMs'] || r['MOYENCOMs'], '[*][?(@.TypedaccesTelecom.ThesLibelle=="Mél")]')&.pluck('CoordonneesTelecom')&.compact_blank,
      facebook: valid_url(id, :facebook, jp_first(r, '.RESEAUXSOCIAUXs[*].Facebook')),
      twitter: valid_url(id, :twitter, jp_first(r, '.RESEAUXSOCIAUXs[*].X')),
      instagram: valid_url(id, :instagram, jp_first(r, '.RESEAUXSOCIAUXs[*].Instagram')),
      linkedin: valid_url(id, :linkedin, jp_first(r, '.RESEAUXSOCIAUXs[*].Linkedin')),
      image: jp(r, '.PHOTOSs[*].Photo.Url'),
      addr: addr(jp_first(r, '.ADRESSEs[*]')),
      route: r['ObjectTypeName'] == 'Itinéraires touristiques' && route(r['ITITEMPSDIFs'], jp_first(r, '.DISTANCEs[*].Distanceenkm'))&.inject({
        gpx_trace: jp_first(r, '.PLAQUETTESTRACESs[*].TraceGPX.Url'),
        pdf: pdfs(jp_first(r, '.PLAQUETTESTRACESs[*]')),
      }, :merge)&.compact_blank,
      'capacity:beds': jp_first(r, '.CAPACITEs[*].Nombretotaldelits')&.to_i,
      'capacity:rooms': jp_first_present(r, '.CAPACITEs[*].Nombretotaldechambres', '.CAPACITEs[*].Nombredechambres')&.to_i,
      'capacity:persons': jp_first(r, '.CAPACITEs[*].Capacitedaccueiltotale')&.to_i,
      'capacity:caravans': jp_first(r, '.CAPACITEs[*].Nombredemplacementscaravanes')&.to_i,
      'capacity:cabins': jp_first(r, '.CAPACITEs[*].Nombredemplacementsmobilhomes')&.to_i,
      'capacity:pitches': jp_first_present(r, '.CAPACITEs[*].Nombredemplacements', '.CAPACITEs[*].Nombretotaldemplacements')&.to_i,
      opening_hours: osm_openning_hours,
      stars: ['Campings', 'Hébergements locatifs (meublés et chambres d\'hôtes)', 'Hôtels', 'Résidences', 'Villages Vacances'].include?(r['ObjectTypeName']) ? TourinsoftSirtaquiMixin::CLASS[jp_first(r, '.CLASs[*].Classement.ThesLibelle')] : nil,
      internet_access: jp(r, '.SERVICESs[0].Services[*][?(@.ThesLibelle=="Wifi")]').any? ? 'wlan' : nil,
    }.merge(
        r['ObjectTypeName'] == 'Fêtes et manifestations' && {
          start_date: date_on,
          end_date: date_off,
          # event: jp(r, '.ClassificationCategoriesFMAs[*].ThesLibelle').collect{ |t| TourinsoftSirtaquiMixin::EVENT_TYPE[t] }.uniq,
        } || {},
        r['ObjectTypeName'] == 'Restauration' ? cuisines(jp(r, '.SPECIALITESs[0].Specialitesculinaires[*].ThesLibelle')) : {},
        r['ObjectTypeName'] == 'Hôtels' ? { tourism: 'hotel' } : {},
      )
  end

  def map_refs(type_feat)
    type, feat = type_feat
    type == :feature ? feat['step_ids'] : nil
  end
end
