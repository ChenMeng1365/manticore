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

['json','yaml'].each{|mod|require mod}

module XmlUtils
  VERSION = "3.0.1"

  def self.parse(source)
    parser = TreeParser.new(source)
    parser.parse
  end

  def self.new_document
    Document.new
  end

  def self.create_element(name, attributes = {})
    element = Element.new(name)
    attributes.each { |k, v| element.add_attribute(k, v) }
    element
  end

  def self.to_xml_string(node)
    formatter = Formatters::Default.new
    output = ""
    formatter.write(node, output)
    output
  end
end

class XmlNode
  attr_accessor :name, :attributes, :elements, :parent, :next, :prev

  def initialize(option = {})
    args = {parent: nil, attributes: {}, elements: [], prev: [], next: []}.merge(option)
    @name = args[:name] || "OID:#{self.object_id}"
    @attributes = args[:attributes]
    @parent, @elements, @prev, @next = args[:parent], args[:elements], args[:prev], args[:next]
    
    if @parent
      @prev << @parent unless @prev.include?(@parent)
      @parent.elements << self unless @parent.elements.include?(self)
      @parent.next << self unless @parent.next.include?(self)
    end
  end

  #####################################################################################################
  # format                                                                                            #
  #####################################################################################################

  # 三元组 ([name, attributes, [name, attributes, ...]])
  def to_triad
    attrs,elems = {},[]
    @attributes.each do|k,v|
      unless k == :text
        attrs[k] = v
      else
        elems += [v].flatten
      end
    end
    elems += @elements.map{|c|c.to_triad}
    [@name, attrs, elems]
  end
  alias :to_a :to_triad

  # 文档化 ({name: [attributes, {name: [...]}]})
  def to_doc
    doc = {}
    doc[@name] = []
    doc[@name] << @attributes
    @elements.each{|e|doc[@name] << e.to_doc}
    return doc
  end

  # 对象化 (like js: {obj: {'-attr': val, '#text': text, obj: {...}}})
  def to_obj
    doc = {}
    @attributes.each do|k,v|
      h = k==:text ? '#' : '-'
      doc["#{h}#{k}"] = v
    end
    @elements.each do|elem|
      doc.merge! elem.to_obj
    end
    return {@name => doc}
  end

  # XML（手动序列化，需确保属性/文本已转义）
  def to_xml
    attrs, content = '', ''
    @attributes.each do |k,v|
      if k == :text
        content += XmlNode.escape_xml([v].flatten.join("\n"))
      elsif k == :namespace && !v
        next
      else
        attrs += " #{k}=\"#{XmlNode.escape_xml_attr(v.to_s)}\""
      end
    end
    return "<#{@name}#{attrs}/>" if @elements.size==0 && !@attributes[:text]
    @elements.each do|e|
      content += if e.is_a?(XmlNode)
        e.to_xml
      elsif e.instance_of?(String)
        XmlNode.escape_xml(e)
      end
    end
    return "<#{@name}#{attrs}>#{content}</#{@name}>"
  end

  def pretty format, method, indent=2
    case method
    when :xml
      pretty_xml = ""
      XmlUtils::Formatters::Default.new.write(XmlUtils.parse(self.send(format)), pretty_xml)
      return pretty_xml
    when :json
      return JSON.pretty_generate(self.send(format))
    else
      raise ArgumentError, "Unknown pretty method: #{method.inspect}"
    end
  end

  def self.escape_xml(text)
    text.gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
  end

  def self.escape_xml_attr(text)
    text.gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
        .gsub('"', '&quot;')
        .gsub("'", '&apos;')
  end
  
  def self.make_str_from xml
    text = xml.dup
    [['&lt;','<'], ['&gt;','>'], ['&amp;','&'], ['&apos;',"'"], ['&quot;','"']].each do |xstr, str|
      text.gsub!(xstr, str)
    end
    text
  end
  
  def self.make_xml_from string
    string.gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub("'", '&apos;')
          .gsub('"', '&quot;')
  end

  #####################################################################################################
  # attributes operation                                                                              #
  #####################################################################################################

  def add_attributes hash
    (@attributes[:text] ||= []) << hash[:text] if hash[:text]
    hash.delete(:text)
    @attributes.merge!(hash)
  end

  def modify_attributes hash
    add_attributes hash
  end

  def delete_attribute key
    @attributes.delete(key) unless key==:text
  end

  #####################################################################################################
  # content operation                                                                                 #
  #####################################################################################################

  def add_content content
    @elements << content
  end

  def modify_content content
    @attributes[:text] = []
    @elements.delete_if{|e|e.is_a?(XmlNode)}
    @elements << content
  end

  def delete_content
    @elements = @elements.find_all{|c|!c.instance_of?(XmlNode)}
  end

  def add_element elem
    if elem.is_a?(XmlNode)
      @elements << elem unless @elements.include?(elem)
      @next << elem unless @next.include?(elem)
      elem.parent = self
      elem.prev << self unless elem.prev.include?(self)
    end
  end

  def search_elements &block
    return ( block ? @elements.find_all(&block) : [] )
  end

  def delete_elements &block
    return [] unless block
    elems = search_elements(&block)
    elems.each{|elem|@elements.delete(elem)}
    return elems
  end

  def self.copy node
    duplicate = XmlNode.new(name: node.name, parent: nil, attributes: node.attributes.dup)
    node.elements.map{|subnode|self.copy(subnode)}.each do|subnode|
      duplicate.add_element subnode
    end
    return duplicate
  end
end


module XmlParser
  def self.load(filepath)
    return File.exist?(filepath) ? XmlParser.parse(File.read(filepath)) : nil
  end

  def self.parse(s)
    doc = XmlUtils.parse(s)
    root_elem = doc.root
    return nil unless root_elem
    
    build_xmlnode(root_elem)
  end

  private

  def self.build_xmlnode(element, parent = nil)
    attrs = {}
    element.attributes.each do |k, attr|
      attrs[k.to_sym] = attr.value
    end

    ns = element.namespace(element.prefix)
    attrs[:namespace] = ns if ns && !ns.empty?

    text_content = element.children
      .select { |c| c.is_a?(XmlUtils::Text) || c.is_a?(XmlUtils::CData) }
      .map(&:to_s)
      .join
    attrs[:text] = text_content unless text_content.strip.empty?

    node = XmlNode.new(name: element.name, parent: parent, attributes: attrs)

    element.children.select { |c| c.is_a?(XmlUtils::Element) }.each do |child|
      build_xmlnode(child, node)
    end

    node
  end
end
