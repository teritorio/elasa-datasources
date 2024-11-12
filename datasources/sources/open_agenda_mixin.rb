# frozen_string_literal: true
# typed: true

module OpenAgendaMixin
  I18N_IMPAIREMENT = HashExcep[{
    'visual_impairment' => {
      '@default': {
        'fr' => 'accéssible aux personnes malvoyantes'
      }
    },
    'hearing_impairment' => {
      '@default' => {
        'fr' => 'Accessibilité auditive'
      }
    },
    'cognitive_impairment' => {
      '@default' => {
        'fr' => 'Accessibilité cognitive'
      }
    },
    'psychic_impairment' => {
      '@default' => {
        'fr' => 'Accessibilité psychique'
      }
    },
  }]

  SCHEMA_IMPAIREMENT = HashExcep[{
    'visual_impairment' => {
      'values' => {
        'yes' => {
          '@default' => {
            'fr' => 'accéssible aux personnes malvoyantes'
          }
        },
        'no' => {
          '@default' => {
            'fr' => 'non accéssible aux personnes malvoyantes'
          }
        },
        'limited' => {
          '@default' => {
            'fr' => 'accéssible aux personnes malvoyantes avec limitations'
          }
        }
      }
    },
    'hearing_impairment' => {
      'values' => {
        'yes' => {
          '@default' => {
            'fr' => 'accéssible aux personnes malentendantes'
          }
        },
        'no' => {
          '@default' => {
            'fr' => 'non accéssible aux personnes malentendantes'
          }
        },
        'limited' => {
          '@default' => {
            'fr' => 'accéssible aux personnes malentendantes avec limitations'
          }
        }
      }
    },
    'cognitive_impairment' => {
      'values' => {
        'yes' => {
          '@default' => {
            'fr' => 'accéssible aux personnes en situation de handicap cognitif'
          },
        },
        'no' => {
          '@default' => {
            'fr' => 'non accéssible aux personnes en situation de handicap cognitif'
          },
        },
        'limited' => {
          '@default' => {
            'fr' => 'accéssible aux personnes en situation de handicap cognitif avec limitations'
          },
        },
      },
    },
    'psychic_impairment' => {
      'values' => {
        'yes' => {
          '@default' => {
            'fr' => 'accéssible aux personnes en situation de handicap psychique'
          },
        },
        'no' => {
          '@default' => {
            'fr' => 'non accéssible aux personnes en situation de handicap psychique'
          },
        },
        'limited' => {
          '@default' => {
            'fr' => 'accéssible aux personnes en situation de handicap psychique avec limitations'
          },
        },
      },
    },
  }]
end
