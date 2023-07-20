#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'yaml'
require 'sorbet-runtime'
require './datasources/sources/i18n'
require './datasources/jobs/job'


@config = YAML.safe_load(File.read('config.yaml'))
@project = ARGV[0]
@datasource = ARGV[1]
@source_filter = ARGV[2]

@config['datasources'].to_a.select { |project, _jobs|
  !@project || project == @project
}.each { |project, jobs|
  # datasources|
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
    Dir.glob("#{dir}/*.i18n.json").each{ |i18n|
      source(I18nSource, 'i18n', 'i18n', { 'url' => i18n })
    }
    destination(GeoJson, dir)
  end
  Kiba.run(job)
}
