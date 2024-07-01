# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/transforms/reverse_geocode'
require './datasources/hash'

class TestReverseGeocode < Test::Unit::TestCase
  def setup; end

  def test_split_by_addr
    with_addr, without_addr = ReverseGeocode.split_by_addr([
      {
        properties: {
          with_addr: false,
          tags: {}
        }
      },
      {
        properties: {
          with_addr: false,
          tags: {
            addr: {
              'city' => 'Paris',
              'postcode' => '75001',
            }
          }
        }
      },
      {
        properties: {
          with_addr: false,
          tags: {
            addr: {
              'street' => 'plop',
              'city' => 'Paris',
            }
          }
        }
      },
      {
        properties: {
          with_addr: false,
          tags: {
            addr: {
              'street' => 'plop',
            }
          }
        }
      },
      {
        properties: {
          with_addr: false,
          tags: {
            addr: {}
          }
        }
      },
      {
        properties: {
          with_addr: true,
          tags: {
            addr: {
              'street' => 'plop',
              'city' => 'Paris',
              'postcode' => '75001',
            }
          }
        }
      },
    ])

    with_addr.each{ |f|
      assert_true f[:properties][:with_addr], f
    }
    without_addr.each{ |f|
      assert_false f[:properties][:with_addr], f
    }
  end

  def test_reverse
    geometry = {
      type: 'Point',
      coordinates: [1.31152, 45.84875]
    }
    ReverseGeocode.reverse([
      {
        geometry: geometry,
        result: { 'city' => 'Panazol', 'postcode' => '87350', 'street' => '16 Route de la Longe' },
        properties: {
          tags: {}
        }
      },
      {
        geometry: geometry,
        result: { 'city' => 'Panazol', 'postcode' => '87350', 'street' => '16 Route de la Longe' },
        properties: {
          tags: {
            addr: {
              'city' => 'Paris',
              'postcode' => '75001',
            }
          }
        }
      },
      {
        geometry: geometry,
        result: { 'city' => 'Panazol', 'postcode' => '87350', 'street' => 'plop' },
        properties: {
          tags: {
            addr: {
              'street' => 'plop',
              'city' => 'Paris',
            }
          }
        }
      },
      {
        geometry: geometry,
        result: { 'city' => 'Panazol', 'postcode' => '87350', 'street' => 'plop' },
        properties: {
          tags: {
            addr: {
              'street' => 'plop',
            }
          }
        }
      },
      {
        geometry: geometry,
        result: { 'city' => 'Panazol', 'postcode' => '87350', 'street' => '16 Route de la Longe' },
        properties: {
          tags: {
            addr: {}
          }
        }
      },
    ]) { |f|
      assert_equal f[:result], f[:properties][:tags][:addr]
    }
  end
end
