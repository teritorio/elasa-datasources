# typed: true
# frozen_string_literal: true

require 'test/unit'
require './datasources/sources/apidae'

class JoinTransformerTags < Test::Unit::TestCase
  def setup
    @join = JoinTransformer.new('ref')
  end

  def join(current, update)
    @join.process_tags(current, update)
  end

  def test_day_hour
    assert_equal 'Jun 12-Jul 02 Tu,We', ApidaeSource.openning({ 'periodesOuvertures' => [{
      'dateDebut' => '2023-06-12',
      'dateFin' => '2023-07-02',
      'type' => 'OUVERTURE_SEMAINE',
      'ouverturesJournalieres' => [{
          'jour' => 'MARDI'
        }, {
          'jour' => 'MERCREDI'
        }]
    }] })
  end

  def test_day_hour_except
    assert_equal 'Jun 12-Jul 02 Mo,Th,Fr,Sa,Su', ApidaeSource.openning({ 'periodesOuvertures' => [{
      'dateDebut' => '2023-06-12',
      'dateFin' => '2023-07-02',
      'type' => 'OUVERTURE_SAUF',
      'ouverturesJournalieres' => [{
          'jour' => 'MARDI'
        }, {
          'jour' => 'MERCREDI'
        }]
    }] })
  end

  def test_exceptional_days
    assert_equal 'Apr 03-Jun 30;Jun 10 off;Jan 1 off;Nov 1 off;Nov 11 off;Dec 25 off', ApidaeSource.openning({
      'periodesOuvertures' => [{
        'dateDebut' => '2023-04-03',
        'dateFin' => '2023-06-30',
        'type' => 'OUVERTURE_TOUS_LES_JOURS',
      }],
      'fermeturesExceptionnelles' => [{
          'dateFermeture' => '2023-06-10',
        }, {
          'dateSpeciale' => 'PREMIER_JANVIER'
        }, {
          'dateSpeciale' => 'PREMIER_NOVEMBRE'
        }, {
          'dateSpeciale' => 'ONZE_NOVEMBRE'
        }, {
          'dateSpeciale' => 'VINGT_CINQ_DECEMBRE'
        }]
    })
  end

  def test_a_lot
    assert_equal 'Apr 15-May 01;May 02-Jul 07 Sa,Su 13:30-18:00;May 08 13:30-18:00;May 18 13:30-18:00;May 19 13:30-18:00;May 29 13:30-18:00;Jul 08-Aug 31 09:30+;Sep 01-Oct 06 We,Sa,Su;Oct 07-Apr 19 We,Sa,Su', ApidaeSource.openning({
      'periodesOuvertures' => [{
          'dateDebut' => '2023-04-15',
          'dateFin' => '2023-05-01',
          'type' => 'OUVERTURE_TOUS_LES_JOURS',
        }, {
          'dateDebut' => '2023-05-02',
          'dateFin' => '2023-07-07',
          'horaireOuverture' => '13:30:00',
          'horaireFermeture' => '18:00:00',
          'type' => 'OUVERTURE_SEMAINE',
          'ouverturesExceptionnelles' => [{
              'dateOuverture' => '2023-05-08'
            }, {
              'dateOuverture' => '2023-05-18'
            }, {
              'dateOuverture' => '2023-05-19'
            }, {
              'dateOuverture' => '2023-05-29'
            }],
          'ouverturesJournalieres' => [{
              'jour' => 'SAMEDI'
            }, {
              'jour' => 'DIMANCHE'
            }],
        }, {
          'dateDebut' => '2023-07-08',
          'dateFin' => '2023-08-31',
          'horaireFermeture' => '09:30:00',
          'type' => 'OUVERTURE_TOUS_LES_JOURS',
        }, {
          'dateDebut' => '2023-09-01',
          'dateFin' => '2023-10-06',
          'type' => 'OUVERTURE_SEMAINE',
          'ouverturesJournalieres' => [{
              'jour' => 'MERCREDI'
            }, {
              'jour' => 'SAMEDI'
            }, {
              'jour' => 'DIMANCHE'
            }],
        }, {
          'dateDebut' => '2023-10-07',
          'dateFin' => '2024-04-19',
          'type' => 'OUVERTURE_SEMAINE',
          'ouverturesJournalieres' => [{
              'jour' => 'MERCREDI'
            }, {
              'jour' => 'SAMEDI'
            }, {
              'jour' => 'DIMANCHE'
            }],
        }]
    })
  end

  def test_month_day
    assert_equal 'Sep 08-Sep 10 Fr[2],Sa[2],Su[2]', ApidaeSource.openning({
      'periodesOuvertures' => [{
        'dateDebut' => '2023-09-08',
        'dateFin' => '2023-09-10',
        'type' => 'OUVERTURE_MOIS',
        'ouverturesJourDuMois' => [
          {
            'jourDuMois' => 'D_2EME',
            'jour' => 'VENDREDI'
          },
          {
            'jourDuMois' => 'D_2EME',
            'jour' => 'SAMEDI'
          },
          {
            'jourDuMois' => 'D_2EME',
            'jour' => 'DIMANCHE'
          }
        ],
      }]
    })
  end

  def test_all_the_year
    assert_equal 'Jan 01-Dec 31', ApidaeSource.openning({
      'periodesOuvertures' => [{
        'dateDebut' => '2018-01-01',
        'dateFin' => '2018-12-31',
        'type' => 'OUVERTURE_TOUS_LES_JOURS',
      }]
    })
  end
end
