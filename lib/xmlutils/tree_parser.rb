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
  class TreeParser
    def initialize(source, document = nil)
      @tokens = Tokenizer.new(source).tokenize
      @pos = 0
      @document = document || Document.new
    end

    def parse
      while current_token && current_token.type != :eof
        parse_node(@document)
      end
      @document
    end

    private

    def current_token
      @tokens[@pos]
    end

    def advance
      token = @tokens[@pos]
      @pos += 1
      token
    end

    def parse_node(parent)
      token = current_token
      return unless token

      case token.type
      when :xml_decl
        advance
        decl = parse_xml_decl(token.value)
        parent.add(decl)
      when :doctype
        advance
        parent.add(parse_doctype(token.value))
      when :processing_instruction
        advance
        if token.value[:target] == 'xml'
          parent.add(parse_xml_decl(token.value[:content]))
        else
          parent.add(ProcessingInstruction.new(token.value[:target], token.value[:content]))
        end
      when :comment
        advance
        parent.add(Comment.new(token.value))
      when :cdata
        advance
        parent.add(CData.new(token.value, true))
      when :start_tag, :empty_tag
        parse_element(parent)
      when :text
        advance
        text = token.value
        parent.add(Text.new(text)) unless text.strip.empty?
      when :close_tag
        advance
      else
        advance
      end
    end

    def parse_element(parent)
      token = advance
      tag_data = token.value

      element = Element.new(tag_data[:name])
      tag_data[:attributes].each do |name, value|
        element.add_attribute(name, value)
      end

      if token.type == :empty_tag
        parent.add(element)
        return
      end

      parent.add(element)

      loop do
        break if @pos >= @tokens.length
        next_token = current_token
        if next_token.type == :close_tag
          if next_token.value == tag_data[:name]
            advance
            break
          else
            raise ParseException.new(
              "Unexpected close tag </#{next_token.value}>, expected </#{tag_data[:name]}>",
              next_token.line,
              next_token.position
            )
          end
        elsif next_token.type == :start_tag
          parse_element(element)
        elsif next_token.type == :empty_tag
          parse_element(element)
        elsif next_token.type == :text
          advance
          element.add(Text.new(next_token.value))
        elsif next_token.type == :cdata
          advance
          element.add(CData.new(next_token.value, true))
        elsif next_token.type == :comment
          advance
          element.add(Comment.new(next_token.value))
        elsif next_token.type == :processing_instruction
          advance
          element.add(ProcessingInstruction.new(next_token.value[:target], next_token.value[:content]))
        else
          advance
        end
      end
    end

    def parse_xml_decl(content)
      decl = XMLDecl.new
      if content =~ /version\s*=\s*["']([^"']+)["']/
        decl.version = $1
      end
      if content =~ /encoding\s*=\s*["']([^"']+)["']/
        decl.encoding = $1
      end
      if content =~ /standalone\s*=\s*["']([^"']+)["']/
        decl.standalone = $1
      end
      decl
    end

    def parse_doctype(content)
      if content =~ /^(\S+)(?:\s+PUBLIC\s+["']([^"']*)["']\s+["']([^"']*)["'])?(?:\s+SYSTEM\s+["']([^"']*)["'])?/
        name = $1
        public_id = $2
        system_id = $3 || $4
        external_id = public_id ? 'PUBLIC' : (system_id ? 'SYSTEM' : nil)
        DocType.new(name, external_id, system_id, public_id)
      else
        DocType.new(content.strip)
      end
    end
  end
end
