# frozen_string_literal: true
# typed: true

class OsmTags
  def initialize(extra_multiple = [])
    @multiple = @@multiple_base + extra_multiple
  end

  @@multiple_base = %w[
    image
    email
    phone
    website
    contact:phone
    mobile
    contact:mobile
    contact:email
    contact:website
  ]

  def process(row)
    tags = row[:properties][:tags]

    # There is an adresse defined by addr:* ?
    has_flat_addr = tags.keys.find{ |k| k.start_with?('addr:') }

    row[:properties][:tags] = tags.collect{ |k, v|
      # Remove contact prefixes
      if k.start_with?('contact:')
        kk = k[('contact:'.size)..]
        # Do no overwrite existing tags
        # Do no remove contact: for adresse if an adress already exists
        if tags.include?(kk)
          k = nil
        else
          is_addr_key = @@contact_addr.include?(kk)
          if is_addr_key && has_flat_addr
            k = nil
          else
            if is_addr_key
              kk = "addr:#{kk}"
            end
            k = kk
          end
        end
      end

      # Split multi-values fields
      [k, @multiple.include?(k) ? v.split(';').collect(&:strip) : v]
    }.select{ |k, _v| !k.nil? }.to_h

    row
  end

  # Part off addr:*, that could also be used in contact:*
  @@contact_addr = %(
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
  )
end
