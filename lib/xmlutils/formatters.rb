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
  class Formatters
    class Default
      attr_accessor :compact

      def initialize(compact = false)
        @compact = compact
      end

      def write(node, output = $stdout)
        case node
        when Document
          node.children.each_with_index do |child, idx|
            write(child, output)
            output << "\n" unless idx == node.children.length - 1
          end
        when Element
          write_element(node, output, 0)
        when Text
          output << node.to_s
        when CData
          output << node.to_s
        when Comment
          output << node.to_s
        when ProcessingInstruction
          output << node.to_s
        when XMLDecl
          output << node.to_s
        when DocType
          output << node.to_s
        end
      end

      def write_element(node, output, indent = 0)
        output << '  ' * indent
        output << "<#{node.name}"
        node.attributes.each_value do |attr|
          output << " #{attr.to_string}"
        end

        if node.children.empty?
          output << " />"
        else
          output << ">"
          has_only_text = node.children.all? { |c| c.is_a?(Text) || c.is_a?(CData) }
          if has_only_text
            node.children.each { |c| write(c, output) }
          else
            output << "\n"
            node.children.each do |c|
              write(c, output) if c.is_a?(Text) && c.to_s.strip.empty?
              next if c.is_a?(Text) && c.to_s.strip.empty?
              if c.is_a?(Element)
                write_element(c, output, indent + 1)
              else
                output << '  ' * (indent + 1)
                write(c, output)
              end
              output << "\n"
            end
            output << '  ' * indent
          end
          output << "</#{node.name}>"
        end
      end
    end

    class Pretty < Default
      def initialize
        super(false)
      end
    end
  end
end
