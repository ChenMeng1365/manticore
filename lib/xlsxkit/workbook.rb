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

require 'json'
require 'stringio'
require_relative 'zip_reader'
require_relative 'sax_parser'

module XlsxKit
  ##
  # XLSX Workbook 高层 API
  #
  # 用法：
  #   wb = XlsxKit::Workbook.open('data.xlsx')
  #   wb.sheet_names       # => ["Sheet1", "Sheet2"]
  #   wb.read_rows('Sheet1') do |row|
  #     puts row.inspect   # ["A1值", "B1值", ...]
  #   end
  #   wb.to_json('Sheet1') # => JSON 字符串
  #   wb.to_a('Sheet1')    # => [[...], [...], ...] 原生 Ruby 数组
  #

  class Workbook
    attr_reader :path

    def initialize(path)
      @path = path
      @shared_strings = nil
    end

    def self.open(path)
      wb = new(path)
      yield wb if block_given?
      wb
    end

    ##
    # 返回所有 sheet 名称。
    def sheet_names
      @sheet_names ||= parse_workbook
    end

    ##
    # 流式读取指定 sheet，逐行 yield。
    #
    # @param name [String, Integer] sheet 名称或序号（0-based）
    # @param headers [Boolean] 第一行作为表头（返回 Hash 行）
    # @yield [Array<value> 或 Hash] 数据行
    def read_rows(name = 0, headers: false)
      target = resolve_sheet(name)
      return enum_for(:read_rows, name, headers: headers) unless block_given?

      header_row = nil
      row_handler = SheetRowHandler.new(load_shared_strings)

      # 第一次扫描：解析 xml，逐行回调
      ZipReader.open(@path) do |zip|
        xml = zip.read_entry_utf8(target[:path])
        return unless xml

        io = StringIO.new(xml)
        SAXParser.parse(io, row_handler)
      end

      rows = row_handler.rows
      if headers && !rows.empty?
        header_row = rows.first
        rows[1..].each do |row|
          yield hashify(header_row, row)
        end
      else
        rows.each { |row| yield row }
      end
    end

    ##
    # 读取全部数据到原生 Ruby 二维数组。
    def to_a(name = 0, headers: false)
      rows = read_rows(name).to_a
      return rows unless headers && rows.size > 1

      header_row = rows.first
      rows[1..].map { |row| hashify(header_row, row) }
    end

    ##
    # 读取并转为 JSON 字符串。
    def to_json(name = 0, headers: false, pretty: false)
      data = to_a(name, headers: headers)
      pretty ? JSON.pretty_generate(data) : JSON.generate(data)
    end

    ##
    # 读取并写入 JSON 文件。
    def to_json_file(path, name = 0, headers: false, pretty: false)
      json = to_json(name, headers: headers, pretty: pretty)
      File.write(path, json)
    end

    #---------------------------------------------------------------------------
    # CSV 输出
    #---------------------------------------------------------------------------

    ##
    # 读取并转为 CSV 字符串。
    def to_csv(name = 0, headers: false)
      out = +''
      first = true
      read_rows(name) do |row|
        if headers && first
          first = false
          next
        end
        out << row.map { |c| csv_escape(c) }.join(',') << "\n"
      end
      out
    end

    ##
    # 逐行生成 CSV（流式，适合大数据量直接写文件）。
    def to_csv_file(path, name = 0, headers: false)
      File.open(path, 'w:UTF-8') do |f|
        first = true
        read_rows(name) do |row|
          if headers && first
            first = false
            next
          end
          f.puts(row.map { |c| csv_escape(c) }.join(','))
        end
      end
    end

    private

    #---------------------------------------------------------------------------
    # Workbook XML 解析：提取 sheet 名称与文件路径
    #---------------------------------------------------------------------------

    def parse_workbook
      names = []
      ZipReader.open(@path) do |zip|
        wb_xml = zip.read_entry_utf8('xl/workbook.xml')
        return names unless wb_xml

        handler = WorkbookHandler.new
        SAXParser.parse(StringIO.new(wb_xml), handler)
        names = handler.sheets

        # 解析 rels 映射 rId → target
        rels_xml = zip.read_entry_utf8('xl/_rels/workbook.xml.rels')
        if rels_xml
          rels_handler = RelsHandler.new
          SAXParser.parse(StringIO.new(rels_xml), rels_handler)
          @rels = rels_handler.rels
        end
      end

      # 将 rId 映射为实际路径
      @sheet_info = names.map do |name, rid|
        target = @rels[rid]
        path = target ? "xl/#{target}" : "xl/worksheets/sheet#{names.index([name, rid]) + 1}.xml"
        { name: name, path: path }
      end

      @sheet_info.map { |s| s[:name] }
    end

    def resolve_sheet(name)
      sheet_names if @sheet_info.nil?
      case name
      when Integer
        @sheet_info[name]
      when String
        @sheet_info.find { |s| s[:name] == name }
      else
        raise ArgumentError, "sheet name must be String or Integer"
      end
    end

    #---------------------------------------------------------------------------
    # Shared Strings 解析
    #---------------------------------------------------------------------------

    def load_shared_strings
      return @shared_strings if @shared_strings

      @shared_strings = []
      ZipReader.open(@path) do |zip|
        xml = zip.read_entry_utf8('xl/sharedStrings.xml')
        return @shared_strings unless xml

        handler = SharedStringsHandler.new
        SAXParser.parse(StringIO.new(xml), handler)
        @shared_strings = handler.strings
      end
      @shared_strings
    end

    #---------------------------------------------------------------------------
    # 辅助方法
    #---------------------------------------------------------------------------

    def hashify(header_row, row)
      hash = {}
      header_row.each_with_index do |key, i|
        hash[key] = row[i]
      end
      hash
    end

    def csv_escape(val)
      return '' if val.nil?
      s = val.to_s
      if s.include?(',') || s.include?('"') || s.include?("\n")
        '"' + s.gsub('"', '""') + '"'
      else
        s
      end
    end

    #---------------------------------------------------------------------------
    # Workbook XML SAX Handler
    #---------------------------------------------------------------------------

    class WorkbookHandler
      attr_reader :sheets

      def initialize
        @sheets = []
        @in_sheet = false
      end

      def start_element(name, attrs)
        if name == 'sheet'
          @sheets << [attrs['name'], attrs['r:id'] || attrs['id']]
        end
      end

      def end_element(name); end
      def characters(text); end
    end

    #---------------------------------------------------------------------------
    # Rels XML SAX Handler
    #---------------------------------------------------------------------------

    class RelsHandler
      attr_reader :rels

      def initialize
        @rels = {}
      end

      def start_element(name, attrs)
        if name == 'Relationship'
          @rels[attrs['Id']] = attrs['Target']
        end
      end

      def end_element(name); end
      def characters(text); end
    end

    #---------------------------------------------------------------------------
    # Shared Strings SAX Handler
    #---------------------------------------------------------------------------

    class SharedStringsHandler
      attr_reader :strings

      def initialize
        @strings = []
        @in_si = false
        @in_t  = false
        @chars = nil
      end

      def start_element(name, attrs)
        case name
        when 'si' then @in_si = true; @chars = +''
        when 't'  then @in_t = true
        end
      end

      def characters(text)
        @chars << text if @in_si && @in_t
      end

      def end_element(name)
        case name
        when 'si'
          @strings << (@chars || '')
          @in_si = false
          @chars = nil
        when 't'
          @in_t = false
        end
      end
    end

    #---------------------------------------------------------------------------
    # Sheet Row SAX Handler
    #
    # 解析 <sheetData> 下的 <row> → <c> → <v>/<is><t> 结构，
    # 将每行的单元格值提取为数组，逐行收集。
    #---------------------------------------------------------------------------

    class SheetRowHandler
      attr_reader :rows

      def initialize(shared_strings)
        @sst = shared_strings
        @rows = []
        @in_row = false
        @in_cell = false
        @in_v = false
        @in_is = false
        @in_is_t = false
        @cell_type = nil
        @cell_ref = nil
        @chars = nil
        @current_row = nil
      end

      def start_element(name, attrs)
        case name
        when 'row'
          @in_row = true
          @current_row = []
        when 'c'
          @in_cell = true
          @cell_type = attrs['t']
          @cell_ref = attrs['r']
          @chars = +''
        when 'v'
          @in_v = true
        when 'is'
          @in_is = true
        when 't'
          @in_is_t = true if @in_is
        end
      end

      def characters(text)
        @chars << text if @in_cell && (@in_v || (@in_is && @in_is_t))
      end

      def end_element(name)
        case name
        when 'row'
          @rows << @current_row
          @in_row = false
          @current_row = nil
        when 'c'
          val = resolve_cell_value
          if @cell_ref
            col = col_ref_to_index(@cell_ref)
            @current_row.fill(nil, @current_row.length...col) if col > @current_row.length
            @current_row[col] = val
          else
            @current_row << val
          end
          @in_cell = false
          @cell_type = nil
          @cell_ref = nil
          @chars = nil
        when 'v'
          @in_v = false
        when 'is'
          @in_is = false
        when 't'
          @in_is_t = false if @in_is
        end
      end

      private

      def resolve_cell_value
        raw = @chars ? @chars.strip : ''
        return nil if raw.empty?

        case @cell_type
        when 's'        # shared string
          idx = raw.to_i
          @sst[idx] || nil
        when 'str'       # formula string
          raw
        when 'inlineStr' # inline string
          raw
        when 'b'         # boolean
          raw == '1'
        when 'e'         # error
          raw
        else             # numeric
          num?(raw) ? raw.to_f : raw
        end
      end

      # "A1" → 0, "B3" → 1, "AA1" → 26
      def col_ref_to_index(ref)
        letters = ref[/^[A-Z]+/]
        col = 0
        letters.each_byte { |b| col = col * 26 + (b - 64) }
        col - 1
      end

      def num?(s)
        s =~ /^-?\d+(\.\d+)?(e[+-]?\d+)?$/i
      end
    end
  end
end
