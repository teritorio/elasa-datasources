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
  ]

  def group_addr(tags)
    g = tags.to_a.group_by{ |k, _v|
      /^addr:.*/.match?(k)
    }.transform_values(&:to_h)
    [g[true] || {}, g[false] || {}]
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

    # Group addr
    addr, tags = group_addr(tags)
    if !addr.empty?
      tags[:addr] = addr.transform_keys{ |key| /^addr:(.*)/.match(key)[1].to_s }
    end
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
