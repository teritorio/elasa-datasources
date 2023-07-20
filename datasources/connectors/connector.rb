# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'


class Connector
  def initialize(job_id, settings, source_filter, path)
    @job_id = job_id
    @settings = settings
    @source_filter = source_filter
    @path = path
  end

  def setup(kiba)
    kiba.source(
      self.class.source_class,
      @job_id,
      @job_id,
      @settings,
    )
  end
end
