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
    project = T.must(path.split('/')[-1]).split('.')[..-2]&.join('.')
    [project, YAML.safe_load_file(path, aliases: true)]
  }
end

@config = load_config_dir('config/config_public/*.yaml').deep_merge_array(load_config_dir('config/*.yaml'))
@project = ARGV[0]
@datasource = ARGV[1]
@source_filter = ARGV[2]

@config.select { |project, _jobs|
  (!@project && !/.manual$/.match?(project)) || project.split('.')[0] == @project
}.each { |project, jobs|
  project = project.split('.')[0]
  dir = "data/#{project}"
  if @datasource.nil? # Full run, drop and recreate
    dir += '_temp'
    FileUtils.rm_rf(dir)
  end

  old_dir = Dir.pwd
  FileUtils.makedirs(dir)
  Dir.chdir(dir)

  logging_appender = Logging.appenders.file(
    'log.txt',
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
      begin
        Job.new(job_id, job, @source_filter)
      rescue StandardError => e
        Sentry.set_tags(project: project, job: job_id)
        Sentry.capture_exception(e)
        Sentry.set_tags(project: nil, job: nil)
        raise
      end
    }

    logger.info('  - Conflate metadata')
    job = Kiba.parse do
      source(MetadataSource, nil, nil, nil, MetadataSource::Settings.from_hash({
        'meta' => Dir.glob('*.metadata.json'),
        'tags_schema_file' => Dir.glob('*.tags_schema.json'),
        'natives_schema_file' => Dir.glob('*.natives_schema.json'),
        'i18n' => Dir.glob('*.i18n.json'),
        'osm_tags' => Dir.glob('*.osm_tags.json'),
      }))
      destination(GeoJson, metadata_only: true)
    end
    Kiba.run(job)

    Dir.chdir(old_dir)
    old_dir = nil

    if @datasource.nil? # Full run, drop and recreate
      dir_finnal = "data/#{project}"
      FileUtils.rm_rf(dir_finnal)
      FileUtils.mv(dir, dir_finnal)
    end
  rescue StandardError => e
    logger.error(e.message)
    logger.error(e.backtrace&.join("\n"))
  end

  if !old_dir.nil?
    Dir.chdir(old_dir)
  end

  Logging.logger.root.remove_appenders(logging_appender)
}
