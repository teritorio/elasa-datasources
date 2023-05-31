# frozen_string_literal: true
# typed: true

require_relative './mixins/addr_tags'

class JoinTransformer
  include HasArrdTags

  def initialize(key)
    @key = key

    @rows = {}
  end

  def process_tags(current_tags, update_tags)
    current_addr, current_other = group_addr(current_tags)
    update_addr, update_other = group_addr(update_tags)

    puts [current_addr, current_other].inspect
    puts [update_addr, update_other].inspect

    # Set non already existing tags
    current_other = update_other.update(current_other)
    if current_addr.empty?
      current_addr = update_addr
    end
    current_other.merge(current_addr)
  end

  def process(row)
    key = row[:properties][:tags][@key]
    if @rows.key?(key)
      @rows[key][:properties][:tags] = process_tags(
        @rows[key][:properties][:tags],
        row[:properties][:tags],
      )
    else
      @rows[key] = row
    end

    nil
  end

  def close(&block)
    puts "#{self.class.name}: #{@rows.size}"

    @rows.values.each(&block)
  end
end
