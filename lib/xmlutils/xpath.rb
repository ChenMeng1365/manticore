# frozen_string_literal: false

# Copyright (C) 2024 Manticore Authors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

module XmlUtils
  class XPath
    def self.match(element, path)
      return [element] if path.nil? || path.strip.empty? || path == '.'
      return [element] if path == '/'

      nodes = [element]
      parts = path.split('/').reject(&:empty?)

      parts.each do |part|
        new_nodes = []
        nodes.each do |node|
          new_nodes.concat(match_step(node, part))
        end
        nodes = new_nodes
      end

      nodes
    end

    def self.first(element, path)
      match(element, path).first
    end

    def self.each(element, path, &block)
      match(element, path).each(&block)
    end

    def self.match_step(node, step)
      return [] unless node.is_a?(Element) || node.is_a?(Document)

      if step == '*'
        return node.children.select { |c| c.is_a?(Element) }
      end

      if step == '..'
        return node.parent ? [node.parent] : []
      end

      if step.start_with?('@')
        attr_name = step[1..]
        if node.is_a?(Element)
          attr = node.attribute(attr_name)
          return attr ? [attr] : []
        end
        return []
      end

      if step.include?('[')
        name = step[/^[^\[]+/]
        predicate = step[/\[(.*?)\]/, 1]
      else
        name = step
        predicate = nil
      end

      if node.is_a?(Document)
        candidates = node.children.select { |c| c.is_a?(Element) && c.name == name }
      else
        candidates = node.children.select { |c| c.is_a?(Element) && c.name == name }
      end

      return candidates unless predicate

      apply_predicate(candidates, predicate)
    end

    def self.apply_predicate(candidates, predicate)
      if predicate =~ /^\d+$/
        idx = predicate.to_i - 1
        idx >= 0 && candidates[idx] ? [candidates[idx]] : []
      elsif predicate =~ /^@(\S+)$/
        attr_name = $1
        candidates.select { |c| c.has_attribute?(attr_name) }
      elsif predicate =~ /^@(\S+)\s*=\s*['"]([^'"]*)['"]$/
        attr_name = $1
        attr_value = $2
        candidates.select { |c| c[attr_name] == attr_value }
      elsif predicate =~ /^contains\(\s*(\S+)\s*,\s*['"]([^'"]*)['"]\s*\)$/
        candidates # Simplified: not fully implemented
      else
        candidates
      end
    end
  end
end
