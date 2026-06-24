# frozen_string_literal: true

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

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'manticore'
require 'tempfile'

class XmlDocTest < Minitest::Test
  #####################################################################################################
  # XmlNode initialization                                                                            #
  #####################################################################################################

  def test_initialize_default
    node = XmlNode.new
    assert_match(/OID:\d+/, node.name)
    assert_equal({}, node.attributes)
    assert_equal([], node.elements)
    assert_nil(node.parent)
  end

  def test_initialize_with_options
    node = XmlNode.new(name: 'root', attributes: { id: '1' })
    assert_equal 'root', node.name
    assert_equal({ id: '1' }, node.attributes)
  end

  def test_initialize_with_parent
    parent = XmlNode.new(name: 'parent')
    child = XmlNode.new(name: 'child', parent: parent)
    assert_equal parent, child.parent
    assert_includes parent.elements, child
    assert_includes parent.next, child
    assert_includes child.prev, parent
  end

  #####################################################################################################
  # serialization / format                                                                          #
  #####################################################################################################

  def test_to_triad_basic
    node = XmlNode.new(name: 'item', attributes: { id: '42' })
    assert_equal ['item', { id: '42' }, []], node.to_triad
  end

  def test_to_triad_with_text
    node = XmlNode.new(name: 'title', attributes: { text: 'Hello' })
    triad = node.to_triad
    assert_equal 'title', triad[0]
    assert_equal({}, triad[1])
    assert_equal ['Hello'], triad[2]
  end

  def test_to_triad_with_children
    parent = XmlNode.new(name: 'root')
    child = XmlNode.new(name: 'child', attributes: { val: 'x' })
    parent.add_element(child)
    assert_equal ['root', {}, [['child', { val: 'x' }, []]]], parent.to_triad
  end

  def test_to_triad_alias_to_a
    node = XmlNode.new(name: 'a')
    assert_equal node.to_triad, node.to_a
  end

  def test_to_doc
    parent = XmlNode.new(name: 'root')
    child = XmlNode.new(name: 'child', attributes: { val: 'x' })
    parent.add_element(child)
    assert_equal({ 'root' => [{}, { 'child' => [{ val: 'x' }] }] }, parent.to_doc)
  end

  def test_to_obj
    node = XmlNode.new(name: 'item', attributes: { id: '1', text: 'text' })
    obj = node.to_obj
    assert_equal({ 'item' => { '-id' => '1', '#text' => 'text' } }, obj)
  end

  def test_to_xml_basic
    node = XmlNode.new(name: 'item')
    assert_equal '<item/>', node.to_xml
  end

  def test_to_xml_with_attributes
    node = XmlNode.new(name: 'item', attributes: { id: '1', class: 'a' })
    xml = node.to_xml
    assert_includes xml, '<item'
    assert_includes xml, 'id="1"'
    assert_includes xml, 'class="a"'
  end

  def test_to_xml_with_text
    node = XmlNode.new(name: 'title', attributes: { text: 'Hello' })
    assert_equal '<title>Hello</title>', node.to_xml
  end

  def test_to_xml_with_children
    parent = XmlNode.new(name: 'root')
    parent.add_element(XmlNode.new(name: 'child'))
    assert_equal '<root><child/></root>', parent.to_xml
  end

  def test_to_xml_escaping
    node = XmlNode.new(name: 'code', attributes: { text: 'if (a < b && c > d) "quote"' })
    xml = node.to_xml
    assert_includes xml, '&lt;'
    assert_includes xml, '&gt;'
    assert_includes xml, '&amp;'
    # escape_xml does not escape quotes in text content; only escape_xml_attr does
    assert_includes xml, '"quote"'
  end

  def test_to_xml_empty_with_text_and_children
    parent = XmlNode.new(name: 'p', attributes: { text: 'hello' })
    parent.add_element(XmlNode.new(name: 'br'))
    xml = parent.to_xml
    assert_includes xml, '<p>'
    assert_includes xml, 'hello'
    assert_includes xml, '<br/>'
    assert_includes xml, '</p>'
  end

  def test_to_xml_namespace_skipped_when_nil
    node = XmlNode.new(name: 'tag', attributes: { namespace: nil, id: '1' })
    xml = node.to_xml
    refute_includes xml, 'namespace'
    assert_includes xml, 'id="1"'
  end

  def test_to_xml_with_string_element
    node = XmlNode.new(name: 'div')
    node.add_content('plain text')
    xml = node.to_xml
    assert_equal '<div>plain text</div>', xml
  end

  def test_pretty_xml
    parent = XmlNode.new(name: 'root')
    parent.add_element(XmlNode.new(name: 'child'))
    pretty = parent.pretty(:to_xml, :xml)
    assert_includes pretty, '<root>'
    assert_includes pretty, '<child />'
    assert_includes pretty, '</root>'
  end

  def test_pretty_json
    node = XmlNode.new(name: 'item', attributes: { id: '1' })
    pretty = node.pretty(:to_triad, :json)
    assert_includes pretty, '"item"'
    assert_includes pretty, '"id"'
  end

  def test_pretty_unknown_method_raises
    node = XmlNode.new(name: 'x')
    assert_raises(ArgumentError) { node.pretty(:to_xml, :yaml) }
  end

  #####################################################################################################
  # escape helpers                                                                                  #
  #####################################################################################################

  def test_escape_xml
    assert_equal '&lt;b&gt; &amp; "', XmlNode.escape_xml('<b> & "')
  end

  def test_escape_xml_attr
    assert_equal '&lt;b&gt; &amp; &quot;&apos;', XmlNode.escape_xml_attr('<b> & "\'')
  end

  def test_make_str_from
    xml = '&lt;div&gt;&amp;&quot;&apos;'
    assert_equal '<div>&"\'', XmlNode.make_str_from(xml)
  end

  def test_make_xml_from
    str = '<b> & "\''
    assert_equal '&lt;b&gt; &amp; &quot;&apos;', XmlNode.make_xml_from(str)
  end

  #####################################################################################################
  # attribute operations                                                                            #
  #####################################################################################################

  def test_add_attributes
    node = XmlNode.new(name: 'tag')
    node.add_attributes(id: '1', class: 'foo')
    assert_equal '1', node.attributes[:id]
    assert_equal 'foo', node.attributes[:class]
  end

  def test_add_attributes_with_text
    node = XmlNode.new(name: 'tag')
    node.add_attributes(text: 'hello')
    assert_equal ['hello'], node.attributes[:text]
  end

  def test_modify_attributes
    node = XmlNode.new(name: 'tag', attributes: { id: '1' })
    node.modify_attributes(id: '2')
    assert_equal '2', node.attributes[:id]
  end

  def test_delete_attribute
    node = XmlNode.new(name: 'tag', attributes: { id: '1', class: 'foo' })
    node.delete_attribute(:id)
    assert_nil node.attributes[:id]
    assert_equal 'foo', node.attributes[:class]
  end

  def test_delete_attribute_cannot_remove_text
    node = XmlNode.new(name: 'tag', attributes: { text: 'hello', id: '1' })
    node.delete_attribute(:text)
    assert_equal 'hello', node.attributes[:text]
  end

  #####################################################################################################
  # content operations                                                                              #
  #####################################################################################################

  def test_add_content
    node = XmlNode.new(name: 'tag')
    node.add_content('hello')
    assert_includes node.elements, 'hello'
  end

  def test_modify_content
    node = XmlNode.new(name: 'tag')
    node.add_element(XmlNode.new(name: 'child'))
    node.add_content('text')
    node.modify_content('new')
    assert_includes node.elements, 'new'
    refute node.elements.any? { |e| e.is_a?(XmlNode) }
    assert_equal [], node.attributes[:text]
  end

  def test_delete_content
    node = XmlNode.new(name: 'tag')
    node.add_content('text')
    node.add_element(XmlNode.new(name: 'child'))
    node.delete_content
    assert_equal ['text'], node.elements.find_all { |c| c.instance_of?(String) }
    assert_equal 0, node.elements.count { |c| c.is_a?(XmlNode) }
  end

  #####################################################################################################
  # element operations                                                                              #
  #####################################################################################################

  def test_add_element
    parent = XmlNode.new(name: 'parent')
    child = XmlNode.new(name: 'child')
    parent.add_element(child)
    assert_equal parent, child.parent
    assert_includes parent.elements, child
    assert_includes parent.next, child
    assert_includes child.prev, parent
  end

  def test_add_element_ignores_non_xmlnode
    parent = XmlNode.new(name: 'parent')
    parent.add_element('not a node')
    assert_equal [], parent.elements
  end

  def test_search_elements
    parent = XmlNode.new(name: 'parent')
    parent.add_element(XmlNode.new(name: 'a', attributes: { val: '1' }))
    parent.add_element(XmlNode.new(name: 'a', attributes: { val: '2' }))
    parent.add_element(XmlNode.new(name: 'b'))
    found = parent.search_elements { |e| e.name == 'a' }
    assert_equal 2, found.size
  end

  def test_search_elements_without_block
    parent = XmlNode.new(name: 'parent')
    parent.add_element(XmlNode.new(name: 'a'))
    assert_equal [], parent.search_elements
  end

  def test_delete_elements
    parent = XmlNode.new(name: 'parent')
    parent.add_element(XmlNode.new(name: 'a', attributes: { val: '1' }))
    parent.add_element(XmlNode.new(name: 'a', attributes: { val: '2' }))
    parent.add_element(XmlNode.new(name: 'b'))
    deleted = parent.delete_elements { |e| e.name == 'a' }
    assert_equal 2, deleted.size
    assert_equal 1, parent.elements.size
  end

  def test_delete_elements_without_block
    parent = XmlNode.new(name: 'parent')
    parent.add_element(XmlNode.new(name: 'a'))
    assert_equal [], parent.delete_elements
  end

  #####################################################################################################
  # copy                                                                                            #
  #####################################################################################################

  def test_copy_is_independent
    original = XmlNode.new(name: 'root', attributes: { id: '1' })
    original.add_element(XmlNode.new(name: 'child'))
    dup = XmlNode.copy(original)
    assert_equal original.name, dup.name
    assert_equal original.attributes, dup.attributes
    refute_equal original.object_id, dup.object_id
    assert_equal 1, dup.elements.size
    dup.attributes[:id] = '2'
    assert_equal '1', original.attributes[:id]
  end

  def test_copy_deep_structure
    root = XmlNode.new(name: 'root')
    child = XmlNode.new(name: 'child', attributes: { val: 'x' })
    grandchild = XmlNode.new(name: 'grandchild')
    child.add_element(grandchild)
    root.add_element(child)
    dup = XmlNode.copy(root)
    assert_equal 'root', dup.name
    assert_equal 'child', dup.elements[0].name
    assert_equal 'grandchild', dup.elements[0].elements[0].name
    assert_nil dup.parent
    assert_equal dup, dup.elements[0].parent
  end

  #####################################################################################################
  # XmlParser.parse                                                                                 #
  #####################################################################################################

  def test_parse_basic
    xml = '<root><child/></root>'
    node = XmlParser.parse(xml)
    assert_equal 'root', node.name
    assert_equal 1, node.elements.size
    assert_equal 'child', node.elements[0].name
  end

  def test_parse_with_attributes
    xml = '<root id="1" class="a"><child val="x"/></root>'
    node = XmlParser.parse(xml)
    assert_equal '1', node.attributes[:id]
    assert_equal 'a', node.attributes[:class]
    assert_equal 'x', node.elements[0].attributes[:val]
  end

  def test_parse_with_text
    xml = '<root>hello</root>'
    node = XmlParser.parse(xml)
    assert_equal 'hello', node.attributes[:text]
  end

  def test_parse_with_cdata
    xml = '<root><![CDATA[<html>]]></root>'
    node = XmlParser.parse(xml)
    assert_equal '<html>', node.attributes[:text]
  end

  def test_parse_with_namespace
    xml = '<root xmlns:ns="http://example.com"><ns:child/></root>'
    node = XmlParser.parse(xml)
    assert_equal 'root', node.name
    child = node.elements[0]
    assert_equal 'ns:child', child.name
    assert_equal 'http://example.com', child.attributes[:namespace]
  end

  def test_parse_empty_element
    xml = '<item/>'
    node = XmlParser.parse(xml)
    assert_equal 'item', node.name
    assert_equal [], node.elements
  end

  def test_parse_returns_nil_for_empty_doc
    xml = '<?xml version="1.0"?>'
    assert_nil XmlParser.parse(xml)
  end

  def test_parse_roundtrip
    xml = '<root id="1"><child>text</child></root>'
    node = XmlParser.parse(xml)
    assert_equal xml, node.to_xml
  end

  def test_parse_with_mixed_content
    xml = '<root>before<child/>after</root>'
    node = XmlParser.parse(xml)
    assert_equal 'beforeafter', node.attributes[:text]
    assert_equal 1, node.elements.size
  end

  #####################################################################################################
  # XmlParser.load                                                                                  #
  #####################################################################################################

  def test_load_existing_file
    Tempfile.create(['test', '.xml']) do |f|
      f.write('<config><setting/></config>')
      f.flush
      node = XmlParser.load(f.path)
      assert_equal 'config', node.name
      assert_equal 'setting', node.elements[0].name
    end
  end

  def test_load_missing_file
    assert_nil XmlParser.load('/nonexistent/path.xml')
  end

  #####################################################################################################
  # edge cases                                                                                      #
  #####################################################################################################

  def test_xmlnode_with_multiple_text_attributes
    node = XmlNode.new(name: 'tag')
    node.add_attributes(text: 'a')
    node.add_attributes(text: 'b')
    assert_equal %w[a b], node.attributes[:text]
  end

  def test_to_xml_self_closing_no_text_no_children
    node = XmlNode.new(name: 'br')
    assert_equal '<br/>', node.to_xml
  end

  def test_to_xml_not_self_closing_when_text_present
    node = XmlNode.new(name: 'p', attributes: { text: 'hello' })
    assert_equal '<p>hello</p>', node.to_xml
  end

  def test_to_xml_not_self_closing_when_children_present
    node = XmlNode.new(name: 'ul')
    node.add_element(XmlNode.new(name: 'li'))
    assert_equal '<ul><li/></ul>', node.to_xml
  end
end
