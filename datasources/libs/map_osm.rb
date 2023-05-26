# frozen_string_literal: true
# typed: true

module MapOSM
  @@multiple = %w[
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

  def self.map(tags, extra_multiple = [])
    m = @@multiple + extra_multiple
    tags.to_h{ |k, v|
      [k, m.include?(k) ? v.split(';').collect(&:strip) : v]
    }
  end
end
