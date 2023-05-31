# frozen_string_literal: true
# typed: true

module HasArrdTags
  def addr_tags?(tags)
    # There is an adresse defined by addr:* ?
    tags.keys.find{ |k| k.start_with?('addr:') }
  end

  def group_addr(tags)
    g = tags.to_a.group_by{ |k, _v|
      /^addr:.*/.match?(k)
    }.transform_values(&:to_h)
    [g[true] || {}, g[false] || {}]
  end
end
