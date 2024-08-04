# frozen_string_literal: true
# typed: ignore

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

    # Upgrade enum to array if needed
    if self['type'] == 'array' && self['items']['enum'] && !other_hash['enum'].nil?
      other_hash = {
        'type' => 'array',
        'items' => {
          'enum' => other_hash['enum']
        }
      }
    elsif other_hash['type'] == 'array' && other_hash['items']['enum'] && !self['enum'].nil?
      self['type'] = 'array'
      self['items'] = {
        'enum' => self['enum']
      }
      delete('enum')
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
