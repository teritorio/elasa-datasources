#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'yaml'
require 'sorbet-runtime'
require './datasources/geotrek'
require './datasources/tourism_system'
require './datasources/apidae'

@config = YAML.safe_load(File.read('config.yaml'))
@project = ARGV[0]
@datasource = ARGV[1]

@config['datasources'].to_a.select { |project, _datasources|
  !@project || project == @project
}.each { |project, datasources|
  puts project
  dir = "data/#{project}"
  FileUtils.rm_rf(dir)
  FileUtils.makedirs(dir)

  datasources&.to_a&.select{ |id, _datasource|
    !@datasource || id == @datasource
  }&.each { |id, datasource|
    puts "#{project} : #{id}, #{datasource['type']}..."

    objects = (
      case datasource['type']
      when 'geotrek'
        Geotrek.new.process(datasource['url'], datasource['url_web'], datasource['attribution'])
      when 'tourism_system'
        TourismSystem.new.process(datasource['url'], datasource['attribution'])
      when 'apidae'
        Apidae.new.process(datasource['territoireIds'], datasource['projetId'], datasource['apiKey'], datasource['attribution'])
      end
    )
    objects.each{ |k, os|
      os = {
        type: 'FeatureCollection',
        features: os,
      }
      puts "#{project} : #{id}, #{datasource['type']} -> #{k}"
      File.write("#{"data/#{project}"}/#{k.to_s.gsub('/', '_')}.geojson", JSON.pretty_generate(os))
    }
  }
}
