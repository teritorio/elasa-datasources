# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'


class Job
  def initialize(multi_source_id, attribution, settings, path)
    @multi_source_id = multi_source_id
    @attribution = attribution
    @settings = settings
    @path = path
  end
end
