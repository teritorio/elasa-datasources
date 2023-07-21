#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'yaml'
require 'sorbet-runtime'
require './datasources/sources/schema'
require './datasources/jobs/job'


@config = YAML.safe_load(File.read('config.yaml'))
@project = ARGV[0]
@datasource = ARGV[1]
@source_filter = ARGV[2]

@config['datasources'].to_a.select { |project, _jobs|
  !@project || project == @project
}.each { |project, jobs|
  puts project
  dir = "data/#{project}"
  FileUtils.makedirs(dir)

  jobs&.to_a&.select{ |id, _job|
    !@datasource || id == @datasource
  }&.each { |job_id, job|
    Job.new(job_id, job, @source_filter, dir)
  }

  puts '  - Conflate metadata'
  job = Kiba.parse do
    source(SchemaSource, nil, nil, {
      'schema' => Dir.glob("#{dir}/*.schema.json"),
      'i18n' => Dir.glob("#{dir}/*.i18n.json"),
    })
    destination(GeoJson, dir)
  end
  Kiba.run(job)
}
