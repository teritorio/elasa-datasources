# frozen_string_literal: true
# typed: ignore

require 'logging'

include Logging.globally

Logging.logger.root.appenders = Logging.appenders.stdout(
  layout: Logging.layouts.pattern(
    pattern: '%m\n'
  ),
  level: :info,
)
Logging.logger.root.level = :debug
