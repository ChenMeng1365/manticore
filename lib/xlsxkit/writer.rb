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

require_relative 'zip_writer'

module XlsxKit
  ##
  # XLSX Workbook 写入 API（与 Workbook 读取器对应）。
  #
  # 将原生 Ruby 数据（二维数组 / Hash 数组 / 多 Sheet）按表格写入 .xlsx 文件。
  #
  # 用法：
  #   # 1. 一次性写入单个 Sheet
  #   XlsxKit::Writer.write('out.xlsx', [['Name', 'Age'], ['Alice', 30]])
  #
  #   # 2. 一次性写入多个 Sheet
  #   XlsxKit::Writer.write('out.xlsx', { 'Sheet1' => rows1, 'Sheet2' => rows2 })
  #
  #   # 3. 构建器模式
  #   XlsxKit::Writer.build('out.xlsx') do |wb|
  #     wb.add_sheet('People') do |s|
  #       s << ['Name', 'Age']
  #       s << ['Alice', 30]
  #     end
  #   end
  #

  class Writer
    # OOXML 命名空间
    NS_SPREADSHEET = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    NS_REL         = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    NS_CONTENT     = 'http://schemas.openxmlformats.org/package/2006/content-types'
    NS_PKG_REL     = 'http://schemas.openxmlformats.org/package/2006/relationships'

    attr_reader :sheets

    ##
    # 创建写入器。传 path 并给块时，块结束后自动 save。
    def initialize(path = nil, &block)
      @path   = path
      @sheets = []
      if block
        yield self
        save(path) if path
      end
    end

    ##
    # 构建器模式：块内 add_sheet，块结束后写入文件。
    def self.build(path = nil, &block)
      new(path, &block)
    end

    ##
    # 一次性写入：
    #   - data 为二维数组时，写入单个 Sheet（默认名 "Sheet1"）
    #   - data 为 { name => rows } 时，写入多个 Sheet
    #   - rows 可为「数组的数组」或「Hash 的数组」（首行 Hash 的 keys 作为表头）
    def self.write(path, data, sheet_name: 'Sheet1')
      writer = new
      if data.is_a?(Hash)
        data.each { |name, rows| writer.add_sheet(name, rows) }
      else
        writer.add_sheet(sheet_name, data)
      end
      writer.save(path)
      writer
    end

    ##
    # 添加一个 Sheet。可传入初始 rows，也可用块逐行 <<。
    def add_sheet(name = nil, rows = nil)
      sheet = Sheet.new(name || "Sheet#{@sheets.length + 1}")
      @sheets << sheet
      sheet.add_rows(rows) if rows
      yield sheet if block_given?
      sheet
    end

    ##
    # 写入文件。target 可为文件路径或可写 IO（如 StringIO）。
    def save(target = @path)
      raise ArgumentError, 'output path required' unless target

      if target.respond_to?(:write)
        zip = ZipWriter.new(target)
        write_zip(zip)
        zip.close
      else
        ZipWriter.open(target) { |zip| write_zip(zip) }
      end
      target
    end

    private

    #---------------------------------------------------------------------------
    # ZIP 包内容组装
    #---------------------------------------------------------------------------

    def write_zip(zip)
      zip.add_entry('[Content_Types].xml', content_types_xml)
      zip.add_entry('_rels/.rels', root_rels_xml)
      zip.add_entry('xl/workbook.xml', workbook_xml)
      zip.add_entry('xl/_rels/workbook.xml.rels', workbook_rels_xml)
      @sheets.each_with_index do |sheet, i|
        zip.add_entry("xl/worksheets/sheet#{i + 1}.xml", sheet_xml(sheet))
      end
    end

    def content_types_xml
      overrides = @sheets.each_with_index.map do |_, i|
        %(<Override PartName="/xl/worksheets/sheet#{i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>)
      end.join

      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
        %(<Types xmlns="#{NS_CONTENT}">) +
        %(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) +
        %(<Default Extension="xml" ContentType="application/xml"/>) +
        %(<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>) +
        overrides +
        %(</Types>)
    end

    def root_rels_xml
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
        %(<Relationships xmlns="#{NS_PKG_REL}">) +
        %(<Relationship Id="rId1" Type="#{NS_REL}/officeDocument" Target="xl/workbook.xml"/>) +
        %(</Relationships>)
    end

    def workbook_xml
      sheets = @sheets.each_with_index.map do |sheet, i|
        %(<sheet name="#{escape_xml(sheet.name)}" sheetId="#{i + 1}" r:id="rId#{i + 1}"/>)
      end.join

      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
        %(<workbook xmlns="#{NS_SPREADSHEET}" xmlns:r="#{NS_REL}"><sheets>) +
        sheets +
        %(</sheets></workbook>)
    end

    def workbook_rels_xml
      rels = @sheets.each_with_index.map do |_, i|
        %(<Relationship Id="rId#{i + 1}" Type="#{NS_REL}/worksheet" Target="worksheets/sheet#{i + 1}.xml"/>)
      end.join

      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
        %(<Relationships xmlns="#{NS_PKG_REL}">) +
        rels +
        %(</Relationships>)
    end

    def sheet_xml(sheet)
      rows = +''
      sheet.each_row do |values, row_num|
        rows << build_row(values, row_num)
      end

      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
        %(<worksheet xmlns="#{NS_SPREADSHEET}"><sheetData>) +
        rows +
        %(</sheetData></worksheet>)
    end

    #---------------------------------------------------------------------------
    # 行 / 单元格生成
    #---------------------------------------------------------------------------

    def build_row(values, row_num)
      cells = +''
      values.each_with_index do |value, col_idx|
        next if value.nil?
        ref = "#{column_name(col_idx)}#{row_num}"
        cells << build_cell(ref, value)
      end
      %(<row r="#{row_num}">#{cells}</row>)
    end

    def build_cell(ref, value)
      case value
      when true, false
        %(<c r="#{ref}" t="b"><v>#{value ? 1 : 0}</v></c>)
      when Numeric
        %(<c r="#{ref}"><v>#{value}</v></c>)
      else
        %(<c r="#{ref}" t="inlineStr"><is><t>#{escape_xml(value.to_s)}</t></is></c>)
      end
    end

    # 列序号 → 列名（0 → "A"，25 → "Z"，26 → "AA"）
    def column_name(idx)
      name = +''
      n = idx
      loop do
        name.prepend((65 + n % 26).chr)
        n = n / 26 - 1
        break if n < 0
      end
      name
    end

    def escape_xml(str)
      str.to_s
         .gsub('&', '&amp;')
         .gsub('<', '&lt;')
         .gsub('>', '&gt;')
         .gsub('"', '&quot;')
         .gsub("'", '&apos;')
    end

    #---------------------------------------------------------------------------
    # Sheet 数据结构
    #---------------------------------------------------------------------------

    class Sheet
      attr_reader :name

      def initialize(name)
        @name = name
        @rows = []
      end

      def <<(row)
        add_row(row)
      end

      def add_row(row)
        @rows << row
        self
      end

      def add_rows(rows)
        rows.each { |r| add_row(r) }
        self
      end

      ##
      # 逐行产出 [values, row_num]，统一将 Hash 行按表头对齐为数组。
      # 若首行为 Hash，则以 keys 生成表头行，其余 Hash 行按表头对齐（缺失 key 补 nil）。
      def each_row
        return if @rows.empty?

        if @rows.first.is_a?(Hash)
          headers = @rows.first.keys
          yield headers, 1
          @rows.each_with_index do |row, idx|
            values = row.is_a?(Hash) ? headers.map { |k| row[k] } : Array(row)
            yield values, idx + 2
          end
        else
          @rows.each_with_index do |row, idx|
            yield Array(row), idx + 1
          end
        end
      end
    end
  end

  ##
  # 便捷入口：XlsxKit.write(path, data, sheet_name: 'Sheet1')
  def self.write(path, data, **opts)
    Writer.write(path, data, **opts)
  end
end
