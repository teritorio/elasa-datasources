# frozen_string_literal: true

require 'test/unit'
require 'fileutils'
require 'mocha/test_unit'
require 'tmpdir'
require 'kiba'
require './datasources/sources/datatourisme'
require './datasources/connectors/datatourisme'
require './datasources/jobs/job'
require './datasources/logging'
require './datasources/hash'
require './datasources/sources/metadata'

class OpenAgendaMappingTest < Test::Unit::TestCase
  def setup
    @temp_dir = Dir.mktmpdir
    fixtures_dir = File.expand_path('./fixtures', __dir__)
    config_dir = File.expand_path('./config', __dir__)
    results_path = File.join(fixtures_dir, 'datatourisme_results.json')

    DatatourismeSource.stubs(:fetch).returns(
      JSON.parse(File.read(results_path))
    )

    @config = load_config_dir(File.join(config_dir, '*.yaml'))
  end

  def test_open_agenda_generating_files
    # Run the connector
    @config.each_value do |jobs|
      jobs.each do |job_id, job|
        Job.new(job_id, job, nil, @temp_dir)
      end
    end


    # Check that files are generated
    generated_files = Dir.glob(File.join(@temp_dir, '*'))
    assert_not_empty(generated_files, 'No files were generated')
    assert(generated_files.size > 1, 'Only one file was generated')
    assert(generated_files.any? { |file| file.end_with?('.json') }, 'No JSON files were generated')
    assert(generated_files.any? { |file| file.end_with?('.metadata.json') }, 'No metadata files were generated')
    assert(generated_files.any? { |file| file.end_with?('.schema.json') }, 'No schema files were generated')
    assert(generated_files.any? { |file| file.end_with?('.i18n.json') }, 'No i18n files were generated')
  end

  def test_datatourisme_files_have_correct_schema
    # Run the connector
    @config.each_value do |jobs|
      jobs.each do |job_id, job|
        Job.new(job_id, job, nil, @temp_dir)
      end
    end

    # Check that the files have the correct schema
    generated_files = Dir.glob(File.join(@temp_dir, '*'))
    generated_files.each do |file|
      next unless file.end_with?('project-WineCellar.json')

      schema_file = file.gsub('.json', '.schema.json')
      schema = JSON.parse(File.read(schema_file))
      data = JSON.parse(File.read(file))

      assert(data.is_a?(Array), 'Data is not an array')
      data.each do |item|
        assert(item.is_a?(Hash), 'Item is not a hash')
        assert(item.keys.all? { |key| schema['properties'].key?(key) }, 'Item has keys not in the schema')
      end
    end
  end

  def load_config_dir(glob)
    Dir[glob].to_h{ |path|
      project = T.must(path.split('/')[-1]).split('.', -2)[0]
      [project, YAML.safe_load_file(path)]
    }
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  at_exit do
    teardown
  end
end
