#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'yaml'
require 'sorbet-runtime'

require './datasources/jobs/apidae'
require './datasources/jobs/csv'
require './datasources/jobs/geotrek'
require './datasources/jobs/join'
require './datasources/jobs/overpass'
require './datasources/jobs/tourism_system'


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
  }&.each { |multi_source_id, settings|
    puts "#{project} : #{multi_source_id}, #{settings['type']}..."
    Object.const_get(settings['type']).new(
      multi_source_id,
      settings['attribution'],
      settings.except('attribution', 'type'),
      dir
    )
  }
}
