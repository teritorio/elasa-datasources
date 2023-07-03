# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'


class Job
  def initialize(multi_source_id, attribution, settings, source_filter, path)
    @multi_source_id = multi_source_id
    @attribution = attribution
    @settings = settings
    @source_filter = source_filter
    @path = path
  end
end
