#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require_relative 'datasources/logging'
require_relative 'datasources/hash'
require 'yaml'
require 'sorbet-runtime'
require './datasources/sources/metadata'
require './datasources/jobs/job'
require 'sentry-ruby'


if ENV['SENTRY_DSN']
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.sample_rate = 1.0
    config.traces_sample_rate = 1.0
    config.breadcrumbs_logger = [:http_logger]
    config.include_local_variables = true
    config.release = File.read('.build')
  end
end


def load_config_dir(glob)
  Dir[glob].to_h{ |path|
    project = T.must(path.split('/')[-1]).split('.', -2)[0]
    [project, YAML.safe_load_file(path)]
  }
end

@config = load_config_dir('config/config_public/*.yaml').deep_merge_array(load_config_dir('config/*.yaml'))
@project = ARGV[0]
@datasource = ARGV[1]
@source_filter = ARGV[2]

@config.select { |project, _jobs|
  !@project || project == @project
}.each { |project, jobs|
  dir = "data/#{project}"
  if @datasource.nil? # Full run, drop and recreate
    dir += '_temp'
    FileUtils.rm_rf(dir)
    FileUtils.makedirs(dir)
  end

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

  begin
    jobs&.to_a&.select{ |id, _job|
      !@datasource || id == @datasource
    }&.each { |job_id, job|
      Job.new(job_id, job, @source_filter, dir)
    }

    logger.info('  - Conflate metadata')
    job = Kiba.parse do
      source(MetadataSource, nil, nil, nil, MetadataSource::Settings.from_hash({
        'meta' => Dir.glob("#{dir}/*.metadata.json"),
        'schema' => Dir.glob("#{dir}/*.schema.json"),
        'i18n' => Dir.glob("#{dir}/*.i18n.json"),
        'osm_tags' => Dir.glob("#{dir}/*.osm_tags.json"),
      }))
      destination(GeoJson, dir, metadata_only: true)
    end
    Kiba.run(job)

    if @datasource.nil? # Full run, drop and recreate
      dir_finnal = "data/#{project}"
      FileUtils.rm_rf(dir_finnal)
      FileUtils.mv(dir, dir_finnal)
    end
  rescue StandardError => e
    Sentry.capture_exception(e)
    logger.error(e.message)
    logger.error(e.backtrace&.join("\n"))
  end

  Logging.logger.root.remove_appenders(logging_appender)
}
