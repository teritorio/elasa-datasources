# frozen_string_literal: true
# typed: true

require_relative 'transformer'


class OsmTags < Transformer
  def initialize(settings)
    super(settings)
    @multiple = @@multiple_base + (settings['extra_multiple'] || [])
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
  ]

  def group(prefix, tags)
    match, not_match = tags.to_a.partition{ |k, _v|
      k.start_with?("#{prefix}:")
    }.collect(&:to_h)

    not_match[prefix] = match.transform_keys{ |key| key[(prefix.size + 1)..] }
    not_match.compact_blank
  end

  def process_tags(tags)
    # There is an adresse defined by addr:* ?
    has_flat_addr = tags.keys.find{ |k| k.start_with?('addr:') }

    tags = tags.collect{ |k, v|
      k = k.to_sym
      # Remove contact prefixes
      if k.start_with?('contact:')
        kk = k[('contact:'.size)..].to_sym
        # Do no overwrite existing tags
        # Do no remove contact: for adresse if an adress already exists
        if tags.include?(kk)
          k = nil
        else
          is_addr_key = @@contact_addr.include?(kk)
          if is_addr_key && has_flat_addr
            k = nil
          else
            kk = "addr:#{kk}" if is_addr_key
            k = kk
          end
        end
      end

      # Split multi-values fields
      [k, @multiple.include?(k) ? v.split(';').collect(&:strip) : v]
    }.select{ |k, _v| !k.nil? }.to_h

    %i[addr ref name source].each{ |key|
      value = tags.delete(key)
      tags = group(key, tags)
      tags = tags.transform_keys(&:to_sym)

      if key == :name
        if !tags.dig(:name, 'fr') && value
          tags[:name] = (tags[:name] || {}).merge({ 'fr' => value })
        end
      else
        tags[:key] = (tags[:key] || {}).merge({ '' => value })
      end
    }

    tags
  end

  def process_data(row)
    row[:properties][:tags] = process_tags(row[:properties][:tags])
    row
  end

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
end
