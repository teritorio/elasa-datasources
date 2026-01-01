# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'active_support/all'

class JsonSchema
  extend T::Sig

  sig { params(hash_: T::Hash[String, T.untyped]).void }
  def initialize(hash_ = {})
    @hash = hash_
  end

  delegate :key?, to: :@hash
  delegate :[], to: :@hash
  delegate :dig, to: :@hash
  delegate :each, to: :@hash
  delegate :delete, to: :@hash
  delegate :inspect, to: :@hash
  delegate :to_json, to: :@hash

  sig { returns(T.nilable(T::Hash[String, JsonSchema])) }
  def defs
    @hash['$defs']
  end

  sig { returns(T::Hash[String, JsonSchema]) }
  def except_defs
    @hash.except('$defs')
  end

  sig { params(this: T.nilable(T.any(T::Hash[String, JsonSchema], T::Boolean)), other: T.nilable(T.any(T::Hash[String, JsonSchema], T::Boolean))).returns(T.any(T::Hash[String, JsonSchema], T::Boolean)) }
  def self.merge_additional_properties(this, other)
    this_add = this.nil? || this
    other_add = other.nil? || other

    if this_add == other_add
      this_add
    elsif this_add.is_a?(Hash) && other_add.is_a?(Hash)
      merge_type(this_add, other_add)
    elsif this_add == true || other_add == true
      true
    else
      raise "Cannot merge additionalProperties #{this_add.to_json} and #{other_add.to_json}"
    end
  end

  sig { params(this: T.nilable(T::Hash[String, T.untyped]), other: T.nilable(T::Hash[String, T.untyped])).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.merge_properties(this, other)
    return if this.blank? && other.blank?
    return this if other.blank?
    return other if this.blank?

    this_keys = this.keys
    other_keys = other.keys
    commons_keys = this_keys & other_keys
    this.except(*other_keys).merge(
      other.except(*this_keys),
      commons_keys.to_h{ |key|
        begin
          [key, merge_type(this[key], other[key])]
        rescue StandardError => e
          raise "On key \"#{key}\": #{e.message}"
        end
      }
    )
  end

  sig { params(this: T::Hash[String, T.untyped], other: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def self.merge_type(this, other)
    return this if this.blank? && other.blank?
    return this if other.blank?
    return other if this.blank?

    if this == other
      this
    elsif this['type'] == 'object' && other['type'] == 'object'
      {
        'type' => 'object',
        'required' => (this['required'] || []).intersection(other['required'] || []).compact_blank,
        'additionalProperties' => merge_additional_properties(this['additionalProperties'], other['additionalProperties']),
        'properties' => merge_properties(this['properties'], other['properties']),
      }.compact
    elsif this['type'] == 'array' && other['type'] == 'array'
      this.except('items').merge(
        other.except('items'),
        'items' => merge_type(this['items'], other['items'])
      )
    elsif !this['enum'].nil? && !other['enum'].nil?
      this.except('enum').merge(
        other.except('enum'),
        { 'enum' => (this['enum'] + other['enum']).uniq },
      )
    elsif this['type'] == other['type']
      this.merge(other)
    elsif %w[string integer].include?(this['type']) && %w[string integer].include?(other['type'])
      { 'type' => 'integer' }
      #############################################################
    else
      raise "Cannot merge JSON Schema types\n#{this.to_json}\n#{other.to_json}"
    end
  end

  sig { params(other: JsonSchema).returns(JsonSchema) }
  def deep_merge_array(other)
    dup.deep_merge_array!(other)
  end

  sig { params(other: JsonSchema).returns(JsonSchema) }
  def deep_merge_array!(other)
    defs = self.class.merge_properties(self.defs, other.defs)
    @hash = self.class.merge_type(except_defs, other.except_defs)
    @hash['$defs'] = defs
    self
  end
end
