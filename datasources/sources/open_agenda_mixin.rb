# frozen_string_literal: true
# typed: true

module OpenAgendaMixin
  DEFS = {
    'multilingual' => {
      'type' => 'object',
      'additionalProperties' => {
        'type' => 'string'
      }
    },
  }.freeze

  I18N_IMPAIREMENT = {
    'cognitive_impairment' => {
      '@default': {
        'fr-FR' => 'accessibilité cognitive'
      },
      'values' => {
        'yes' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes en situation de handicap cognitif'
          }
        },
        'no' => {
          '@default:full' => {
            'fr-FR' => 'non accéssible aux personnes en situation de handicap cognitif'
          }
        },
        'limited' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes en situation de handicap cognitif avec limitations'
          }
        }
      }
    },
    'visual_impairment' => {
      '@default': {
        'fr-FR' => 'accéssible aux personnes malvoyantes'
      },
      'values' => {
        'yes' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes malvoyantes'
          }
        },
        'no' => {
          '@default:full' => {
            'fr-FR' => 'non accéssible aux personnes malvoyantes'
          }
        },
        'limited' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes malvoyantes avec limitations'
          }
        }
      }
    },
    'hearing_impairment' => {
      '@default' => {
        'fr-FR' => 'Accessibilité auditive'
      },
      'values' => {
        'yes' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes malentendantes'
          }
        },
        'no' => {
          '@default:full' => {
            'fr-FR' => 'non accéssible aux personnes malentendantes'
          }
        },
        'limited' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes malentendantes avec limitations'
          }
        }
      }
    },
    'psychic_impairment' => {
      '@default' => {
        'fr-FR' => 'Accessibilité psychique'
      },
      'values' => {
        'yes' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes en situation de handicap psychique'
          },
        },
        'no' => {
          '@default:full' => {
            'fr-FR' => 'non accéssible aux personnes en situation de handicap psychique'
          },
        },
        'limited' => {
          '@default:full' => {
            'fr-FR' => 'accéssible aux personnes en situation de handicap psychique avec limitations'
          },
        },
      },
    },
    'short_description' => {
      '@default' => {
        'fr-FR' => 'description courte'
      },
    },
  }.freeze

  NATIVES_SCHEMA = {
    'type' => 'object',
    'properties' => {
      'cognitive_impairment' => {
        'type' => 'string',
        'enum' => %w[yes no limited],
      },
      'visual_impairment' => {
        'type' => 'string',
        'enum' => %w[yes no limited],
      },
      'hearing_impairment' => {
        'type' => 'string',
        'enum' => %w[yes no limited],
      },
      'psychic_impairment' => {
        'type' => 'string',
        'enum' => %w[yes no limited],
      },
      'agenda' => {
        'type' => 'object',
        'additionalProperties' => false,
        'properties' => {
          'id' => { 'type' => 'integer' },
          'name' => { 'type' => 'string' },
        }
      },
      'keywords' => {
        'type' => 'array',
        'items' => {
          'type' => 'string',
        }
      },
      'short_description' => {
        '$ref' => '#/$defs/multilingual',
      },
    },
    '$defs' => OpenAgendaMixin::DEFS,
  }.freeze
end
