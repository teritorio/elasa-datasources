# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class OsmTags < Transformer
  extend T::Sig

  class Settings < Transformer::TransformerSettings
    const :extra_multiple, T::Array[String], default: []
  end

  extend T::Generic
  SettingsType = type_member{ { upper: Settings } } # Generic param

  sig { params(settings: SettingsType).void }
  def initialize(settings)
    super
    @multiple = @@multiple_base + settings.extra_multiple
  end

  @@multiple_base = %i[
    image
    email
    phone
    website
    contact:phone
    mobile
    contact:mobile
    contact:email
    contact:website
    cuisine
    route_ref
    produce
    product
    crop
    sport
    shoes
    vending
    seasonal
    clothes
    healthcare:speciality
  ]

  @@capacities = ['capacity', 'capacity:beds', 'capacity:rooms', 'capacity:persons', 'capacity:caravans', 'capacity:cabins', 'capacity:pitches']

  def group(prefix, tags)
    match, not_match = tags.to_a.partition{ |k, _v|
      k.start_with?("#{prefix}:")
    }.collect(&:to_h)

    not_match[prefix] = match.transform_keys{ |key| key[(prefix.size + 1)..] }
    not_match.compact_blank
  end

  def remove_contact_prefix(tags, key, has_flat_addr)
    return key if !key.start_with?('contact:')

    kk = key[('contact:'.size)..].to_sym
    # Do no overwrite existing tags
    # Do no remove contact: for adresse if an adress already exists
    return if tags.include?(kk)

    is_addr_key = @@contact_addr.include?(kk)
    if is_addr_key && has_flat_addr
      nil
    elsif is_addr_key
      "addr:#{kk}"
    else
      kk
    end
  end

  def tags_to_url(tags)
    @@url_format.each{ |key, formatter|
      if tags.include?(key) && !tags[key].start_with?('http')
        tags[key] = formatter.gsub('$1', tags[key])
      end
    }
    tags
  end

  def process_tags_name_description(tags)
    (@@names + %i[addr ref description source]).each{ |key|
      value = tags.delete(key)
      tags = group(key, tags)
      tags = tags.transform_keys(&:to_sym)

      # else
      # tags[key] = (tags[key] || {}).merge({ '' => value })
      if !value.nil? && (@@names + %i[description]).include?(key) && !tags.dig(key, 'fr-FR')
        tags[key] = (tags[key] || {}).merge({ 'fr-FR' => value })
      end
      # else
      # tags[key] = (tags[key] || {}).merge({ '' => value })
    }

    # Fill default name
    @@names.collect{ |name| tags[name]&.keys }.compact.flatten.uniq.each{ |lang|
      name_lang = @@names.find{ |name| tags.dig(name, lang) }
      if name_lang
        if tags[:name]
          tags[:name][lang] = tags[name_lang][lang]
        else
          tags[:name] = { lang => tags[name_lang][lang] }
        end
      end
    }

    # Deals with locale variants
    (@@names + %i[description]).each{ |key|
      # FIXME: should be the opposite

      if tags.dig(key, 'fr-FR').nil? && !tags.dig(key, 'fr').nil?
        tags[key]['fr-FR'] = tags[key].delete('fr')

      end

      if tags.dig(key, 'fr-FR') == tags.dig(key, 'fr')
        tags[key]&.delete('fr')
      end
    }

    tags
  end

  def process_tags_phone(tags)
    # Move mobile to phone
    phone = (tags[:phone] || []) + (tags.delete(:mobile) || [])
    tags[:phone] = phone if phone.present?

    tags
  end

  def process_tags_street(tags)
    # Move housenumber, housename, place, unit... to street
    if tags[:addr]
      tags[:addr].delete('full') # Remove full
      street = %w[housenumber housename place unit street].collect{ |key| tags[:addr].delete(key) }.compact.join(', ')
      tags[:addr]['street'] = street if street.present?
    end

    tags
  end

  def process_tags_capacities(tags)
    @@capacities.each { |key|
      capacity = tags.delete(key.to_sym)
      if capacity
        begin
          tags[key] = Integer(capacity)
        rescue StandardError => _e
          logger.info("Fails conver to integer #{key}=#{capacity}")
        end
      end
    }

    tags
  end

  def process_tags_units(tags)
    # Remove unit from length
    tags[:length] = tags[:length].strip if !tags[:length].nil? && tags[:length][-1] == 'm'

    tags
  end

  def process_tags(tags)
    # There is an adresse defined by addr:* ?
    has_flat_addr = tags.keys.find{ |k| k.start_with?('addr:') }

    tags = tags.collect{ |k, v|
      k = k.to_sym
      k = remove_contact_prefix(tags, k, has_flat_addr)

      # Split multi-values fields
      [k, @multiple.include?(k) ? v.split(';').collect(&:strip) : v]
    }.select{ |k, _v| !k.nil? }.to_h

    tags = tags_to_url(tags)
    tags = process_tags_name_description(tags)
    tags = process_tags_phone(tags)
    tags = process_tags_street(tags)
    tags = process_tags_capacities(tags)
    tags = process_tags_units(tags)

    tags.delete(:type) if tags[:type] == 'multipolygon'
    tags.delete(:colour) if tags[:type] != 'route'

    tags
  end

  def process_data(row)
    row[:properties][:tags] = process_tags(row[:properties][:tags])
    row
  end

  @@names = %i[
    name
    alt_name
    loc_name
    official_name
  ]

  # Part off addr:*, that could also be used in contact:*
  @@contact_addr = %i[
    housenumber
    street
    city
    postcode
    country
    state
    place
    suburb
    district
    province
    conscriptionnumber
    hamlet
    municipality
    subdistrict
    interpolation
    unit
    full
    neighbourhood
    floor
    neighborhood
    housename
    streetnumber
    region
    flats
    inclusion
    county
    provisionalnumber
    ward
    subward
    village
    block
    quarter
    block_number
  ]

  @@url_format = {
    facebook: 'https://www.facebook.com/$1',
    twitter: 'https://twitter.com/$1',
    instagram: 'https://www.instagram.com/$1',
  }
end
