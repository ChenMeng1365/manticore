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
  class Token
    attr_accessor :type, :value, :line, :position

    TYPES = %i[
      start_tag end_tag empty_tag
      text cdata comment processing_instruction
      doctype xml_decl attribute_name attribute_value
      close_tag eq quote whitespace newline eof
    ].freeze

    def initialize(type, value = nil, line = nil, position = nil)
      @type = type
      @value = value
      @line = line
      @position = position
    end

    def to_s
      "<Token #{@type}: #{@value.inspect}>"
    end
  end

  class Tokenizer
    XML_NAME_PATTERN = /[A-Za-z_][A-Za-z0-9_.:-]*/.freeze

    def initialize(source)
      @source = source.respond_to?(:read) ? source.read : source.to_s
      @pos = 0
      @line = 1
      @col = 1
      @tokens = []
    end

    def tokenize
      until @pos >= @source.length
        @tokens << next_token
      end
      @tokens << Token.new(:eof)
      @tokens
    end

    private

    def next_token
      skip_spaces

      if @pos >= @source.length
        return Token.new(:eof, nil, @line, @col)
      end

      ch = peek

      case ch
      when '<'
        advance
        case peek
        when '/'
          advance
          name = read_name
          skip_until('>')
          advance if peek == '>'
          Token.new(:close_tag, name, @line, @col)
        when '!'
          advance
          if peek(2) == '--'
            advance(2)
            read_comment
          elsif peek(7).upcase == '[CDATA['
            advance(7)
            read_cdata
          elsif peek(7).upcase == 'DOCTYPE'
            advance(7)
            read_doctype
          else
            raise ParseException.new("Invalid markup after <!", @line, @col)
          end
        when '?'
          advance
          read_processing_instruction
        else
          read_tag
        end
      when '&'
        read_entity_ref
      else
        read_text
      end
    end

    def read_tag
      name = read_name
      skip_spaces

      attrs = {}
      until peek == '>' || peek == '/' || @pos >= @source.length
        attr_name = read_name
        skip_spaces
        if peek == '='
          advance
          skip_spaces
          attr_value = read_quoted_string
        else
          attr_value = attr_name
        end
        attrs[attr_name] = attr_value
        skip_spaces
      end

      if peek == '/'
        advance
        token_type = :empty_tag
      else
        token_type = :start_tag
      end

      skip_until('>')
      advance if peek == '>'

      Token.new(token_type, { name: name, attributes: attrs }, @line, @col)
    end

    def read_comment
      start_line = @line
      start_col = @col
      content = ""
      until @pos + 2 >= @source.length
        if peek(3) == '-->'
          advance(3)
          break
        end
        content << advance
      end
      Token.new(:comment, content, start_line, start_col)
    end

    def read_cdata
      start_line = @line
      start_col = @col
      content = ""
      until @pos + 2 >= @source.length
        if peek(3) == ']]>'
          advance(3)
          break
        end
        content << advance
      end
      Token.new(:cdata, content, start_line, start_col)
    end

    def read_doctype
      start_line = @line
      start_col = @col
      content = ""
      depth = 1
      while @pos < @source.length && depth > 0
        ch = advance
        if ch == '<'
          depth += 1
        elsif ch == '>'
          depth -= 1
        end
        content << ch unless depth == 0
      end
      Token.new(:doctype, content.strip, start_line, start_col)
    end

    def read_processing_instruction
      start_line = @line
      start_col = @col
      target = read_name
      skip_spaces
      content = ""
      until @pos + 1 >= @source.length
        if peek(2) == '?>'
          advance(2)
          break
        end
        content << advance
      end
      Token.new(:processing_instruction, { target: target, content: content.strip }, start_line, start_col)
    end

    def read_text
      start_line = @line
      start_col = @col
      text = ""
      while @pos < @source.length && peek != '<' && peek != '&'
        text << advance
      end
      Token.new(:text, text, start_line, start_col)
    end

    def read_entity_ref
      start_line = @line
      start_col = @col
      advance # &
      ref = ""
      while @pos < @source.length && peek != ';'
        ref << advance
      end
      advance if peek == ';' # ;
      entity = case ref
               when 'amp' then '&'
               when 'lt' then '<'
               when 'gt' then '>'
               when 'quot' then '"'
               when 'apos' then "'"
               else "&#{ref};"
               end
      Token.new(:text, entity, start_line, start_col)
    end

    def read_name
      name = ""
      while @pos < @source.length && peek =~ /[A-Za-z0-9_.:-]/
        name << advance
      end
      raise ParseException.new("Expected name", @line, @col) if name.empty?
      name
    end

    def read_quoted_string
      quote = advance
      raise ParseException.new("Expected quote", @line, @col) unless quote == '"' || quote == "'"
      value = ""
      while @pos < @source.length && peek != quote
        value << advance
      end
      advance if peek == quote
      value
    end

    def peek(n = 1)
      @source[@pos, n] || ''
    end

    def advance(n = 1)
      ch = @source[@pos, n]
      n.times do |i|
        c = @source[@pos + i]
        if c == "\n"
          @line += 1
          @col = 1
        else
          @col += 1
        end
      end
      @pos += n
      ch
    end

    def skip_spaces
      while @pos < @source.length && peek =~ /\s/
        advance
      end
    end

    def skip_until(char)
      while @pos < @source.length && peek != char
        advance
      end
    end
  end
end
