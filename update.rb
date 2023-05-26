#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'yaml'
require 'sorbet-runtime'
require './datasources/geotrek'
require './datasources/tourism_system'
require './datasources/apidae'
require './datasources/csv'
require './datasources/overpass'

@config = YAML.safe_load(File.read('config.yaml'))
@project = ARGV[0]
@datasource = ARGV[1]

@config['datasources'].to_a.select { |project, _datasources|
  !@project || project == @project
}.each { |project, datasources|
  puts project
  dir = "data/#{project}"
  FileUtils.makedirs(dir)

  datasources&.to_a&.select{ |id, _datasource|
    !@datasource || id == @datasource
  }&.each { |id, datasource|
    puts "#{project} : #{id}, #{datasource['type']}..."

    processor = Object.const_get(datasource['type']).new
    objects = processor.process(id, datasource, dir)
    objects.each{ |k, os|
      os = {
        type: 'FeatureCollection',
        features: os,
      }
      puts "#{project} : #{id}, #{datasource['type']} -> #{k}"
      File.write("#{dir}/#{k.to_s.gsub('/', '_')}.geojson", JSON.pretty_generate(os))
    }
  }
}
