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
require 'zlib'
require 'stringio'
require 'tmpdir'

Dir.glob(File.join(Dir.tmpdir, 'manticore_test_*.xlsx')).each { |f| File.delete(f) rescue nil }

class XlsxKitTest < Minitest::Test
  #####################################################################################################
  # Test fixture: generate a minimal valid XLSX file in-memory                                         #
  #####################################################################################################

  def setup
    @xlsx_path = create_test_xlsx
  end

  def teardown
    File.delete(@xlsx_path) if @xlsx_path && File.exist?(@xlsx_path)
  end

  #####################################################################################################
  # Workbook basic API                                                                                #
  #####################################################################################################

  def test_sheet_names
    wb = XlsxKit::Workbook.open(@xlsx_path)
    assert_equal ['Sheet1'], wb.sheet_names
  end

  #####################################################################################################
  # Read rows as array                                                                                #
  #####################################################################################################

  def test_read_rows_basic
    wb = XlsxKit::Workbook.open(@xlsx_path)
    rows = wb.read_rows.to_a

    assert_equal 3, rows.length
    # Header row
    assert_equal ['Name', 'Age', 'Score'], rows[0]
    # Data rows
    assert_equal ['Alice', 30.0, 95.5], rows[1]
    assert_equal ['Bob', 25.0, 87.0], rows[2]
  end

  #####################################################################################################
  # Read rows with header option → Hash rows                                                          #
  #####################################################################################################

  def test_read_rows_with_headers
    wb = XlsxKit::Workbook.open(@xlsx_path)
    rows = wb.read_rows(headers: true).to_a

    assert_equal 2, rows.length
    assert_equal({ 'Name' => 'Alice', 'Age' => 30.0, 'Score' => 95.5 }, rows[0])
    assert_equal({ 'Name' => 'Bob', 'Age' => 25.0, 'Score' => 87.0 }, rows[1])
  end

  #####################################################################################################
  # to_a shortcut                                                                                     #
  #####################################################################################################

  def test_to_a
    wb = XlsxKit::Workbook.open(@xlsx_path)
    data = wb.to_a
    assert_equal 3, data.length
    assert_equal ['Name', 'Age', 'Score'], data[0]
  end

  #####################################################################################################
  # to_json output                                                                                    #
  #####################################################################################################

  def test_to_json
    wb = XlsxKit::Workbook.open(@xlsx_path)
    json = wb.to_json
    parsed = JSON.parse(json)
    assert_equal 3, parsed.length
    assert_equal 'Alice', parsed[1][0]
  end

  def test_to_json_with_headers
    wb = XlsxKit::Workbook.open(@xlsx_path)
    json = wb.to_json(headers: true)
    parsed = JSON.parse(json)
    assert_equal 2, parsed.length
    assert_equal 'Alice', parsed[0]['Name']
    assert_equal 95.5, parsed[0]['Score']
  end

  #####################################################################################################
  # to_csv output                                                                                     #
  #####################################################################################################

  def test_to_csv
    wb = XlsxKit::Workbook.open(@xlsx_path)
    csv = wb.to_csv
    lines = csv.strip.split("\n")
    assert_equal 3, lines.length
    assert_match /Alice/, lines[1]
  end

  #####################################################################################################
  # Streaming: block-based row-by-row                                                                 #
  #####################################################################################################

  def test_streaming_block
    wb = XlsxKit::Workbook.open(@xlsx_path)
    collected = []
    wb.read_rows do |row|
      collected << row
    end
    assert_equal 3, collected.length
  end

  #####################################################################################################
  # Sheet access by index and by name                                                                 #
  #####################################################################################################

  def test_sheet_by_index
    wb = XlsxKit::Workbook.open(@xlsx_path)
    rows = wb.read_rows(0).to_a
    assert_equal 3, rows.length
  end

  def test_sheet_by_name
    wb = XlsxKit::Workbook.open(@xlsx_path)
    rows = wb.read_rows('Sheet1').to_a
    assert_equal 3, rows.length
  end

  #####################################################################################################
  # Special characters / XML entities in cell values                                                  #
  #####################################################################################################

  def test_special_characters
    path = create_xlsx_with_special_chars
    begin
      wb = XlsxKit::Workbook.open(path)
      rows = wb.read_rows.to_a
      assert_equal ['A&B', '<tag>', '"quote"'], rows[0]
    ensure
      File.delete(path) if File.exist?(path)
    end
  end

  #####################################################################################################
  # Boolean and error cell types                                                                      #
  #####################################################################################################

  def test_boolean_and_error
    path = create_xlsx_with_bool_error
    begin
      wb = XlsxKit::Workbook.open(path)
      rows = wb.read_rows.to_a
      assert_equal true, rows[0][0]
      assert_equal false, rows[0][1]
      assert_equal '#DIV/0!', rows[0][2]
    ensure
      File.delete(path) if File.exist?(path)
    end
  end

  #####################################################################################################
  # to_json_file writes a valid JSON file                                                             #
  #####################################################################################################

  def test_to_json_file
    wb = XlsxKit::Workbook.open(@xlsx_path)
    out_path = File.join(File.dirname(@xlsx_path), 'test_output.json')
    begin
      wb.to_json_file(out_path, headers: true, pretty: true)
      assert File.exist?(out_path)
      parsed = JSON.parse(File.read(out_path))
      assert_equal 2, parsed.length
    ensure
      File.delete(out_path) if File.exist?(out_path)
    end
  end

  #####################################################################################################
  # to_csv_file writes a valid CSV file                                                               #
  #####################################################################################################

  def test_to_csv_file
    wb = XlsxKit::Workbook.open(@xlsx_path)
    out_path = File.join(File.dirname(@xlsx_path), 'test_output.csv')
    begin
      wb.to_csv_file(out_path)
      assert File.exist?(out_path)
      content = File.read(out_path)
      assert_match /Alice/, content
    ensure
      File.delete(out_path) if File.exist?(out_path)
    end
  end

  #####################################################################################################
  # Empty cells (sparse rows)                                                                         #
  #####################################################################################################

  def test_empty_cells
    path = create_xlsx_with_empty_cells
    begin
      wb = XlsxKit::Workbook.open(path)
      rows = wb.read_rows.to_a
      assert_equal ['A', nil, 'C'], rows[0]
    ensure
      File.delete(path) if File.exist?(path)
    end
  end

  #=====================================================================================================
  # XLSX fixture generation helpers
  #=====================================================================================================

  private

  ##
  # 创建一个最小化 XLSX 文件用于测试。
  # XLSX 本质是 ZIP 包，包含一组特定路径的 XML 文件。
  def create_test_xlsx
    shared_strings = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="5" uniqueCount="5">
  <si><t>Name</t></si>
  <si><t>Age</t></si>
  <si><t>Score</t></si>
  <si><t>Alice</t></si>
  <si><t>Bob</t></si>
</sst>)

    sheet_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row r="1">
  <c r="A1" t="s"><v>0</v></c>
  <c r="B1" t="s"><v>1</v></c>
  <c r="C1" t="s"><v>2</v></c>
</row>
<row r="2">
  <c r="A2" t="s"><v>3</v></c>
  <c r="B2"><v>30</v></c>
  <c r="C2"><v>95.5</v></c>
</row>
<row r="3">
  <c r="A3" t="s"><v>4</v></c>
  <c r="B3"><v>25</v></c>
  <c r="C3"><v>87</v></c>
</row>
</sheetData>
</worksheet>)

    workbook_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
  <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
</sheets>
</workbook>)

    rels_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>)

    content_types = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>)

    files = {
      '[Content_Types].xml'           => content_types,
      'xl/workbook.xml'               => workbook_xml,
      'xl/_rels/workbook.xml.rels'    => rels_xml,
      'xl/worksheets/sheet1.xml'      => sheet_xml,
      'xl/sharedStrings.xml'          => shared_strings,
    }

    write_xlsx(files)
  end

  def create_xlsx_with_special_chars
    shared_strings = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">
  <si><t>A&amp;B</t></si>
  <si><t>&lt;tag&gt;</t></si>
  <si><t>&quot;quote&quot;</t></si>
</sst>)

    sheet_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row r="1">
  <c r="A1" t="s"><v>0</v></c>
  <c r="B1" t="s"><v>1</v></c>
  <c r="C1" t="s"><v>2</v></c>
</row>
</sheetData>
</worksheet>)

    build_xlsx(shared_strings, sheet_xml)
  end

  def create_xlsx_with_bool_error
    sheet_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row r="1">
  <c r="A1" t="b"><v>1</v></c>
  <c r="B1" t="b"><v>0</v></c>
  <c r="C1" t="e"><v>#DIV/0!</v></c>
</row>
</sheetData>
</worksheet>)

    shared_strings = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0"></sst>)

    build_xlsx(shared_strings, sheet_xml)
  end

  def create_xlsx_with_empty_cells
    shared_strings = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
  <si><t>A</t></si>
  <si><t>C</t></si>
</sst>)

    sheet_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row r="1">
  <c r="A1" t="s"><v>0</v></c>
  <c r="C1" t="s"><v>1</v></c>
</row>
</sheetData>
</worksheet>)

    build_xlsx(shared_strings, sheet_xml)
  end

  def build_xlsx(shared_strings, sheet_xml)
    workbook_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
</workbook>)

    rels_xml = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>)

    content_types = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>)

    files = {
      '[Content_Types].xml'           => content_types,
      'xl/workbook.xml'               => workbook_xml,
      'xl/_rels/workbook.xml.rels'    => rels_xml,
      'xl/worksheets/sheet1.xml'      => sheet_xml,
      'xl/sharedStrings.xml'          => shared_strings,
    }

    write_xlsx(files)
  end

  ##
  # 将文件列表打包为 ZIP（XLSX）格式，使用 DEFLATE 压缩。
  # 纯 Ruby 实现，不依赖 rubyzip。
  def write_xlsx(files)
    path = File.join(Dir.tmpdir, "manticore_test_#{Time.now.to_f}_#{rand(10000)}.xlsx")
    File.open(path, 'wb') do |f|
      central_dir = []
      offset = 0

      files.each do |name, content|
        data = content.dup.force_encoding('UTF-8').encode('UTF-8').b
        compressed = Zlib::Deflate.new(nil, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)

        crc = Zlib.crc32(data)
        name_bytes = name.b

        # Local File Header (26 bytes + name)
        local = LOCAL_SIG.dup
        local << [20, 0, 8, 0, 0, crc,
                  compressed.length, data.length,
                  name_bytes.length, 0].pack('vvvvvVVVvv')
        local << name_bytes
        local << compressed

        f.write(local)

        # Central Directory Record (46 bytes + name)
        cd = CDENTRY_SIG.dup
        cd << [20, 20, 0, 8, 0, 0, crc,
               compressed.length, data.length,
               name_bytes.length, 0, 0, 0, 0, 0, offset].pack('vvvvvvVVVvvvvvVV')
        cd << name_bytes

        central_dir << cd
        offset += local.length
      end

      cd_offset = offset
      cd_data = central_dir.join
      f.write(cd_data)

      # End of Central Directory
      cd_size = cd_data.length
      total = files.length
      eocd = EOCD_SIG.dup
      eocd << [0, 0, total, total, cd_size, cd_offset, 0].pack('vvvvVVv')
      f.write(eocd)
    end

    path
  end

  # ZIP signatures
  LOCAL_SIG   = "PK\x03\x04".b.freeze
  CDENTRY_SIG = "PK\x01\x02".b.freeze
  EOCD_SIG    = "PK\x05\x06".b.freeze
end
