#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'logging'
require 'yaml'
require 'sorbet-runtime'
require './datasources/sources/schema'
require './datasources/jobs/job'


include Logging.globally
Logging.logger.root.appenders = Logging.appenders.stdout(
  layout: Logging.layouts.pattern(
    pattern: '%m\n'
  ),
  level: :info,
)
Logging.logger.root.level = :debug


@config = YAML.safe_load_file('config.yaml')
@project = ARGV[0]
@datasource = ARGV[1]
@source_filter = ARGV[2]

@config['datasources'].to_a.select { |project, _jobs|
  !@project || project == @project
}.each { |project, jobs|
  dir = "data/#{project}"
  FileUtils.makedirs(dir)

  logging_appender = Logging.appenders.file(
    "#{dir}/log.txt",
    truncate: true,
    layout: Logging.layouts.pattern(
      pattern: '%m\n'
    ),
    level: :debug,
  )
  Logging.logger.root.add_appenders(logging_appender)

  logger.info(project)

  jobs&.to_a&.select{ |id, _job|
    !@datasource || id == @datasource
  }&.each { |job_id, job|
    Job.new(job_id, job, @source_filter, dir)
  }

  logger.info('  - Conflate metadata')
  job = Kiba.parse do
    source(SchemaSource, nil, nil, {
      'schema' => Dir.glob("#{dir}/*.schema.json"),
      'i18n' => Dir.glob("#{dir}/*.i18n.json"),
    })
    destination(GeoJson, dir)
  end
  Kiba.run(job)

  Logging.logger.root.remove_appenders(logging_appender)
}
