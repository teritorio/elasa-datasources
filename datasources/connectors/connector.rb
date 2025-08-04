# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'


class Connector
  extend T::Sig
  extend T::Helpers

  abstract!

  def initialize(job_id, settings, source_filter)
    @job_id = job_id
    @settings = settings
    @source_filter = source_filter
  end

  def self.source_class; end

  def slug
    s = self.class.source_class.name
    if s.end_with?('Source')
      s = s[0..-7]
    end
    { 'en-US' => s.parameterize }
  end

  def setup(kiba)
    kiba.source(
      self.class.source_class,
      @job_id,
      @job_id,
      @settings['name'],
      self.class.source_class.const_get(:Settings).from_hash(@settings),
    )
  end
end
