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

require_relative 'xmlutils/node'
require_relative 'xmlutils/tokenizer'
require_relative 'xmlutils/tree_parser'
require_relative 'xmlutils/xpath'
require_relative 'xmlutils/formatters'
require_relative 'xmlutils/xml_doc'

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
