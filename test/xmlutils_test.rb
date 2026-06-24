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

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require 'minitest/autorun'
require 'manticore'

class XmlUtilsTest < Minitest::Test
  #####################################################################################################
  # Basic XML parsing                                                                                 #
  #####################################################################################################

  def test_basic_xml_parsing
    xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <person id="1">
    <name>Alice</name>
    <age>30</age>
  </person>
  <person id="2">
    <name>Bob</name>
    <age>25</age>
  </person>
</root>
XML

    doc = XmlUtils.parse(xml)
    assert_equal 'root', doc.root.name
    assert_equal 2, doc.root.children.length
    assert_equal 2, doc.root.elements.length
  end

  #####################################################################################################
  # XPath queries                                                                                     #
  #####################################################################################################

  def test_xpath_queries
    xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <person id="1">
    <name>Alice</name>
    <age>30</age>
  </person>
  <person id="2">
    <name>Bob</name>
    <age>25</age>
  </person>
</root>
XML

    doc = XmlUtils.parse(xml)
    persons = XmlUtils::XPath.match(doc.root, 'person')
    assert_equal 2, persons.length
    assert_equal 'Alice', XmlUtils::XPath.first(doc.root, 'person[1]/name').text
    assert_equal '25', XmlUtils::XPath.first(doc.root, 'person[2]/age').text
  end

  #####################################################################################################
  # CDATA and Comments                                                                                #
  #####################################################################################################

  def test_cdata_and_comments
    xml = <<-XML
<data>
  <![CDATA[<html>test</html>]]>
  <!-- this is a comment -->
  <value>plain</value>
</data>
XML

    doc = XmlUtils.parse(xml)
    assert_equal 'data', doc.root.name
    assert_equal 1, doc.root.children.select { |c| c.is_a?(XmlUtils::Text) }.length
  end

  #####################################################################################################
  # Empty elements and attributes                                                                     #
  #####################################################################################################

  def test_empty_elements_and_attributes
    xml = '<config debug="true" version="2.0" />'
    doc = XmlUtils.parse(xml)
    assert_equal 'config', doc.root.name
    assert_equal %w[debug version], doc.root.attributes.keys.sort
    assert_equal 'true', doc.root['debug']
  end

  #####################################################################################################
  # Serialization / Round-trip                                                                          #
  #####################################################################################################

  def test_serialization_round_trip
    xml = <<-XML
<library>
  <book title="1984" author="Orwell">
    <price>12.99</price>
  </book>
</library>
XML

    doc = XmlUtils.parse(xml)
    out = XmlUtils.to_xml_string(doc)
    assert_includes out, '<book'
    assert_includes out, '</book>'
  end

  #####################################################################################################
  # Document construction                                                                             #
  #####################################################################################################

  def test_document_construction
    doc = XmlUtils.new_document
    root = XmlUtils::Element.new('catalog')
    doc.add(root)
    item = XmlUtils::Element.new('item')
    item.add_attribute('id', '99')
    item.add_text('Widget')
    root.add(item)

    assert_equal 'catalog', doc.root.name
    assert doc.root.children.any? { |c| c.is_a?(XmlUtils::Element) && c.name == 'item' }
  end

  #####################################################################################################
  # Doctype and XML declaration                                                                       #
  #####################################################################################################

  def test_doctype_and_xml_declaration
    xml = <<-XML
<?xml version="1.1"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html></html>
XML

    doc = XmlUtils.parse(xml)
    refute_nil doc.xml_decl
    refute_nil doc.doctype
    assert_equal 'html', doc.doctype.name
  end
end
