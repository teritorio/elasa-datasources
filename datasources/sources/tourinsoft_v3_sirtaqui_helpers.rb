# frozen_string_literal: true
# typed: true

require 'json'
require 'http'
require 'active_support/all'

require 'sorbet-runtime'

module TourinsoftSirtaquiHelpers
  include TourinsoftSirtaquiMixin

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
end
