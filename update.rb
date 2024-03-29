#!/usr/bin/ruby
# frozen_string_literal: true
# typed: true

require 'logging'
require 'yaml'
require 'sorbet-runtime'
require './datasources/sources/metadata'
require './datasources/jobs/job'


include Logging.globally
Logging.logger.root.appenders = Logging.appenders.stdout(
  layout: Logging.layouts.pattern(
    pattern: '%m\n'
  ),
  level: :info,
)
Logging.logger.root.level = :debug


class Hash
  def deep_merge_array(other_hash)
    dup.deep_merge_array!(other_hash)
  end

  def deep_merge_array!(other_hash)
    if size == 1 && keys[0] == '$ref'
      # On JSON schema, when self hash is a ref, clear current value to only keep the other_hash
      clear
    end

    if other_hash.size == 1 && other_hash.keys[0] == '$ref'
      # On JSON schema, when other hash if a ref, clear current value to only keep the ref
      clear
    end

    merge!(other_hash) do |_key, this_val, other_val|
      if this_val.is_a?(Hash) && other_val.is_a?(Hash)
        this_val.deep_merge_array(other_val)
      elsif this_val.is_a?(Array) && other_val.is_a?(Array)
        (this_val + other_val).uniq
      else
        other_val
      end
    end
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
  rescue StandardError => e
    logger.error(e.message)
    logger.error(e.backtrace&.join("\n"))
  end

  if @datasource.nil? # Full run, drop and recreate
    dir_finnal = "data/#{project}"
    FileUtils.rm_rf(dir_finnal)
    FileUtils.mv(dir, dir_finnal)
  end

  Logging.logger.root.remove_appenders(logging_appender)
}
