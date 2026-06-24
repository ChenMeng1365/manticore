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
  class ParseException < RuntimeError
    attr_reader :line, :position

    def initialize(message, line = nil, position = nil)
      @line = line
      @position = position
      super(message)
    end

    def to_s
      base = super
      @line ? "#{base} (line #{@line}, pos #{@position})" : base
    end
  end

  class IllegalArgumentError < ArgumentError; end
  class UndefinedNamespaceException < ParseException; end

  class Node
    include Enumerable

    attr_accessor :parent

    def initialize
      @parent = nil
    end

    def each(&block)
      return to_enum unless block_given?
    end

    def to_s
      output = ""
      write(output)
      output
    end

    def node_type
      self.class.name.split('::').last.downcase.to_sym
    end

    def root
      node = self
      node = node.parent while node.parent
      node
    end

    def document
      r = root
      r.is_a?(Document) ? r : nil
    end

    def next_sibling
      return nil unless @parent
      siblings = @parent.children
      idx = siblings.index(self)
      idx ? siblings[idx + 1] : nil
    end

    def previous_sibling
      return nil unless @parent
      siblings = @parent.children
      idx = siblings.index(self)
      idx && idx > 0 ? siblings[idx - 1] : nil
    end

    def remove
      @parent.delete(self) if @parent
      self
    end

    def deep_clone
      Marshal.load(Marshal.dump(self))
    end
  end

  class ChildNode < Node
    def write(output, indent = 0)
      output << '  ' * indent
      write_content(output, indent)
    end

    def write_content(output, indent)
      raise NotImplementedError
    end
  end

  class Text < ChildNode
    attr_accessor :value, :raw, :unnormalized

    def initialize(value, respect_whitespace = false, parent = nil)
      super()
      @parent = parent
      @raw = false
      @unnormalized = nil
      @value = respect_whitespace ? value : normalize(value)
    end

    def node_type
      :text
    end

    def clone
      Text.new(@value, true)
    end

    def empty?
      @value.nil? || @value.empty?
    end

    def <=>(other)
      other <=> @value
    end

    def to_s
      @value.to_s
    end

    def value
      @unnormalized || unnormalize(@value)
    end

    def value=(val)
      @value = normalize(val)
      @unnormalized = nil
    end

    def write_content(output, indent = 0)
      if @raw
        output << @value
      else
        output << escape(@value)
      end
    end

    private

    def normalize(input)
      return '' if input.nil?
      input.gsub(/\r\n?/, "\n")
    end

    def unnormalize(input)
      input.gsub(/&(amp|lt|gt|quot|apos);/) do |match|
        case $1
        when 'amp'  then '&'
        when 'lt'   then '<'
        when 'gt'   then '>'
        when 'quot' then '"'
        when 'apos' then "'"
        else match
        end
      end
    end

    def escape(input)
      input.gsub('&', '&amp;')
           .gsub('<', '&lt;')
           .gsub('>', '&gt;')
           .gsub('"', '&quot;')
    end
  end

  class CData < Text
    def initialize(value, respect_whitespace = false, parent = nil)
      super(value, respect_whitespace, parent)
      @raw = true
    end

    def node_type
      :cdata
    end

    def clone
      CData.new(@value, true)
    end

    def write_content(output, indent = 0)
      output << "<![CDATA[#{@value}]]>"
    end
  end

  class Comment < ChildNode
    attr_accessor :string

    def initialize(string, parent = nil)
      super()
      @parent = parent
      @string = string.to_s
    end

    def node_type
      :comment
    end

    def clone
      Comment.new(@string)
    end

    def write_content(output, indent = 0)
      output << "<!--#{@string}-->"
    end
  end

  class ProcessingInstruction < ChildNode
    attr_accessor :target, :content

    def initialize(target, content = nil, parent = nil)
      super()
      @parent = parent
      @target = target
      @content = content
    end

    def node_type
      :processing_instruction
    end

    def clone
      ProcessingInstruction.new(@target, @content)
    end

    def write_content(output, indent = 0)
      if @content && !@content.empty?
        output << "<?#{@target} #{@content}?>"
      else
        output << "<?#{@target}?>"
      end
    end
  end

  class DocType < ChildNode
    attr_accessor :name, :external_id, :system_id, :public_id

    def initialize(name, external_id = nil, system_id = nil, public_id = nil, parent = nil)
      super()
      @parent = parent
      @name = name
      @external_id = external_id
      @system_id = system_id
      @public_id = public_id
    end

    def node_type
      :doctype
    end

    def write_content(output, indent = 0)
      if @external_id
        if @public_id
          output << "<!DOCTYPE #{@name} PUBLIC \"#{@public_id}\" \"#{@system_id}\">"
        else
          output << "<!DOCTYPE #{@name} SYSTEM \"#{@system_id}\">"
        end
      else
        output << "<!DOCTYPE #{@name}>"
      end
    end
  end

  class XMLDecl < ProcessingInstruction
    attr_accessor :version, :encoding, :standalone

    def initialize(version = "1.0", encoding = nil, standalone = nil, parent = nil)
      super('xml', nil, parent)
      @version = version
      @encoding = encoding
      @standalone = standalone
    end

    def node_type
      :xmldecl
    end

    def write_content(output, indent = 0)
      attrs = ["version=\"#{@version}\""]
      attrs << "encoding=\"#{@encoding}\"" if @encoding
      attrs << "standalone=\"#{@standalone}\"" if @standalone
      output << "<?xml #{attrs.join(' ')}?>"
    end
  end

  class Attribute
    attr_accessor :name, :value, :normalized, :element

    def initialize(name, value, normalized = true)
      @name = name.to_s
      @value = normalized ? value.to_s : normalize(value.to_s)
      @normalized = normalized
      @element = nil
    end

    def node_type
      :attribute
    end

    def clone
      Attribute.new(@name, @value, true)
    end

    def to_s
      @value
    end

    def to_string
      "#{@name}=\"#{escape(@value)}\""
    end

    def namespace
      prefix = @name.include?(':') ? @name.split(':').first : ''
      prefix == 'xmlns' ? '' : prefix
    end

    def prefix
      @name.include?(':') ? @name.split(':').first : ''
    end

    private

    def normalize(input)
      input.gsub(/\r\n?/, "\n").gsub(/\n/, '&#10;')
    end

    def escape(input)
      input.gsub('&', '&amp;')
           .gsub('<', '&lt;')
           .gsub('>', '&gt;')
           .gsub('"', '&quot;')
           .gsub("'", '&apos;')
    end
  end

  class Element < ChildNode
    attr_accessor :name, :attributes, :children, :prefixes

    def initialize(name, parent = nil)
      super()
      @parent = parent
      @name = name.to_s
      @attributes = {}
      @children = []
      @prefixes = {}
      @parent.add(self) if @parent && @parent.respond_to?(:add)
    end

    def node_type
      :element
    end

    def clone
      cloned = Element.new(@name)
      @attributes.each { |k, v| cloned.add_attribute(k, v.clone) }
      @children.each { |c| cloned.add(c.clone) }
      cloned
    end

    def add(element)
      element.parent = self
      @children << element
      element
    end
    alias << add

    def delete(element)
      @children.delete(element)
      element.parent = nil if element.respond_to?(:parent=)
    end

    def delete_at(index)
      @children.delete_at(index)
    end

    def [](name_or_index)
      if name_or_index.is_a?(Integer)
        @children[name_or_index]
      else
        attr = attribute(name_or_index.to_s)
        attr ? attr.value : nil
      end
    end

    def []=(name_or_index, value)
      if name_or_index.is_a?(Integer)
        @children[name_or_index] = value
      else
        add_attribute(name_or_index.to_s, value.to_s)
      end
    end

    def add_attribute(name, value)
      attr = value.is_a?(Attribute) ? value : Attribute.new(name, value)
      attr.element = self
      @attributes[name.to_s] = attr
      attr
    end
    alias set_attribute add_attribute

    def delete_attribute(name)
      @attributes.delete(name.to_s)
    end

    def attribute(name)
      @attributes[name.to_s]
    end

    def has_attribute?(name)
      @attributes.key?(name.to_s)
    end

    def each_element(&block)
      return to_enum(:each_element) unless block_given?
      @children.select { |c| c.is_a?(Element) }.each(&block)
    end

    def elements
      @children.select { |c| c.is_a?(Element) }
    end

    def text(path = nil)
      return XPath.match(self, path).first.text if path
      txt = @children.select { |c| c.is_a?(Text) || c.is_a?(CData) }
      txt.map(&:to_s).join('')
    end

    def get_text(path = nil)
      return XPath.match(self, path).first if path
      @children.find { |c| c.is_a?(Text) || c.is_a?(CData) }
    end

    def add_text(text)
      t = text.is_a?(Text) ? text : Text.new(text)
      add(t)
      t
    end

    def get_elements(name)
      @children.select { |c| c.is_a?(Element) && c.name == name }
    end

    def each_recursive(&block)
      return to_enum(:each_recursive) unless block_given?
      @children.each do |child|
        block.call(child)
        child.each_recursive(&block) if child.is_a?(Element)
      end
    end

    def namespaces
      ns = @prefixes.dup
      @attributes.each do |k, v|
        if k == 'xmlns'
          ns[''] = v.value
        elsif k.start_with?('xmlns:')
          ns[k.sub('xmlns:', '')] = v.value
        end
      end
      ns
    end

    def namespace(prefix = nil)
      prefix ||= self.prefix
      ns = namespaces
      return ns[prefix] if ns.key?(prefix)
      @parent.respond_to?(:namespace) ? @parent.namespace(prefix) : nil
    end

    def prefix
      @name.include?(':') ? @name.split(':').first : ''
    end

    def expand(name)
      return name unless name.include?(':')
      p, local = name.split(':')
      ns = namespace(p)
      ns ? "{#{ns}}#{local}" : name
    end

    def write_content(output, indent = 0)
      output << "<#{@name}"
      @attributes.each_value { |attr| output << " #{attr.to_string}" }
      if @children.empty?
        output << " />"
      else
        output << ">"
        has_only_text = @children.all? { |c| c.is_a?(Text) || c.is_a?(CData) }
        if has_only_text
          @children.each { |c| c.write(output, 0) }
        else
          output << "\n"
          @children.each { |c| c.write(output, indent + 1); output << "\n" }
          output << '  ' * indent
        end
        output << "</#{@name}>"
      end
    end

    def inspect
      attrs = @attributes.map { |k, v| "#{k}=#{v.to_s.inspect}" }.join(' ')
      attrs = " #{attrs}" unless attrs.empty?
      "<#{@name}#{attrs}>"
    end
  end

  class Document < Node
    attr_accessor :children

    def initialize(standalone = nil)
      super()
      @children = []
      @standalone = standalone
    end

    def node_type
      :document
    end

    def add(element)
      element.parent = self
      @children << element
      element
    end
    alias << add

    def delete(element)
      @children.delete(element)
      element.parent = nil if element.respond_to?(:parent=)
    end

    def root
      @children.find { |c| c.is_a?(Element) }
    end

    def write(output = $stdout, indent = 0)
      @children.each_with_index do |child, idx|
        child.write(output, indent)
        output << "\n" unless idx == @children.length - 1
      end
    end

    def to_s
      output = ""
      write(output)
      output
    end

    def xml_decl
      @children.find { |c| c.is_a?(XMLDecl) || (c.is_a?(ProcessingInstruction) && c.respond_to?(:target) && c.target == 'xml') }
    end

    def doctype
      @children.find { |c| c.is_a?(DocType) }
    end

    def each_element(&block)
      return to_enum(:each_element) unless block_given?
      @children.select { |c| c.is_a?(Element) }.each(&block)
    end

    def elements
      @children.select { |c| c.is_a?(Element) }
    end

    def context
      {}
    end
  end
end
