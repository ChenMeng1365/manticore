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

require 'stringio'

module XlsxKit
  ##
  # 轻量 SAX 风格 XML 解析器，专为 XLSX 内部 XML 流式处理设计。
  #
  # 与 XmlUtils::TreeParser（DOM 全量建树）不同，本解析器不在内存中构建节点树，
  # 而是逐标签触发回调（start_element / end_element / characters），内存占用恒定。
  #
  # 核心算法：增量缓冲 — 每次从 IO 读取一块数据追加到 @buf，
  # 尝试提取已完整的标签/文本段并回调，不完整的尾部保留到下次。
  # 这样即使数百 MB 的 sheet XML 也只占用几十 KB 内存。
  #
  # Handler 协议（鸭子类型，无需继承）：
  #   start_element(name, attrs)   — 遇到开始标签
  #   end_element(name)            — 遇到结束标签
  #   characters(text)             — 遇到文本内容（可能分多次回调）

  class SAXParser
    BUFFER_SIZE = 65536  # 64KB 读取块

    def self.parse(source, handler)
      new(source, handler).parse
    end

    def initialize(source, handler)
      @source  = source
      @handler = handler
      @buf     = ''.b
      @eof     = false
      @i       = 0  # 已消费位置
    end

    def parse
      until @eof && @i >= @buf.length
        fill_buffer if !@eof && (@buf.length - @i) < BUFFER_SIZE
        step || (@eof = true)
      end
      # 尾部残余文本
      if @i < @buf.length
        text = @buf[@i..]
        emit_text(text) unless text.strip.empty?
      end
    end

    private

    def fill_buffer
      chunk = @source.read(BUFFER_SIZE)
      if chunk && !chunk.empty?
        @buf << chunk
      else
        @eof = true
      end
    end

    ##
    # 尝试从 @buf 的 @i 位置提取一个完整元素（文本段或标签），
    # 成功返回 true（已消费），失败返回 nil（需要更多数据）。
    def step
      return nil if @i >= @buf.length

      lt = @buf.index('<', @i)

      # --- 情况一：当前位置是 '<'，解析标签 ---
      if @i == lt
        parse_tag
      # --- 情况二：有 '<' 在前方，先处理文本 ---
      elsif lt
        text = @buf[@i...lt]
        @i = lt
        emit_text(text) unless text.strip.empty?
        true  # 文本已消费，下次循环处理标签
      # --- 情况三：无 '<'，整个缓冲区都是文本（或已到 EOF）---
      else
        if @eof
          text = @buf[@i..]
          @i = @buf.length
          emit_text(text) unless text.strip.empty?
          true
        else
          # 留最后 1 字节（可能是 '<' 的一半... 虽然不会发生），等下次
          nil
        end
      end
    end

    #---------------------------------------------------------------------------
    # 标签解析
    #---------------------------------------------------------------------------

    def parse_tag
      # 确保 '>' 存在
      return nil unless ensure_char('>')

      ch = @buf[@i + 1]

      case ch
      when '!'
        parse_special
      when '?'
        parse_pi
      when '/'
        parse_end_tag
      else
        parse_start_tag
      end
    end

    def parse_start_tag
      # 注意：属性值中可能包含 '>'，因此需逐字符扫描，跳过引号区域
      gt_pos = find_tag_end(@i)
      return nil unless gt_pos

      raw = @buf[(@i + 1)...gt_pos]
      @i = gt_pos + 1

      self_closing = raw.end_with?('/')
      raw = raw[0..-2] if self_closing

      name, attrs = extract_name_and_attrs(raw)
      @handler.start_element(name, attrs) if @handler.respond_to?(:start_element)
      @handler.end_element(name) if self_closing && @handler.respond_to?(:end_element)

      true
    end

    def parse_end_tag
      gt_pos = @buf.index('>', @i)
      return nil unless gt_pos

      name = @buf[(@i + 2)...gt_pos].strip
      @i = gt_pos + 1
      @handler.end_element(name) if @handler.respond_to?(:end_element)
      true
    end

    def parse_special
      # <!-- comment --> 或 <![CDATA[ ... ]]>
      if @buf[(@i + 2), 2] == '--'
        end_idx = @buf.index('-->', @i)
        return nil unless end_idx
        @i = end_idx + 3
      elsif @buf[(@i + 2), 7] == '[CDATA['
        end_idx = @buf.index(']]>', @i)
        return nil unless end_idx

        data = @buf[(@i + 9)...end_idx]
        emit_text(data)
        @i = end_idx + 3
      else
        gt_pos = @buf.index('>', @i)
        return nil unless gt_pos
        @i = gt_pos + 1
      end
      true
    end

    def parse_pi
      close = @buf.index('?>', @i)
      if close
        @i = close + 2
      else
        gt_pos = @buf.index('>', @i)
        return nil unless gt_pos
        @i = gt_pos + 1
      end
      true
    end

    #---------------------------------------------------------------------------
    # 辅助：标签内扫描（跳过引号区域内的 '>'）
    #---------------------------------------------------------------------------

    def find_tag_end(start)
      i = start + 1
      in_quote = nil

      while i < @buf.length
        ch = @buf[i]

        if in_quote
          i += 1
          in_quote = nil if ch == in_quote
        elsif ch == '"' || ch == "'"
          in_quote = ch
          i += 1
        elsif ch == '>'
          return i
        else
          i += 1
        end
      end

      # 未找到 '>'
      nil
    end

    def ensure_char(target)
      @buf.index(target, @i) ? true : false
    end

    def extract_name_and_attrs(raw)
      # raw 形如: 'c r="A1" t="s"' 或 'c r="A1"/'
      i = 0
      i += 1 while raw[i] && raw[i] =~ /[A-Za-z0-9_:.\-]/
      name = raw[0...i]

      attrs = {}
      while i < raw.length
        i += 1 while raw[i] =~ /\s/
        break if i >= raw.length

        # 属性名
        nstart = i
        i += 1 while raw[i] && raw[i] !~ /[\s=\/]/
        aname = raw[nstart...i]

        # 跳过空格
        i += 1 while raw[i] =~ /\s/

        if raw[i] == '='
          i += 1
          i += 1 while raw[i] =~ /\s/
          quote = raw[i]
          if quote == '"' || quote == "'"
            i += 1
            vend = raw.index(quote, i)
            attrs[aname] = unescape(raw[i...vend])
            i = vend + 1
          else
            vstart = i
            i += 1 while raw[i] && raw[i] !~ /[\s\/]/
            attrs[aname] = raw[vstart...i]
          end
        else
          attrs[aname] = nil
        end
      end

      [name, attrs]
    end

    #---------------------------------------------------------------------------
    # 实体反转义
    #---------------------------------------------------------------------------

    ENTITY_MAP = {
      'amp'  => '&',
      'lt'   => '<',
      'gt'   => '>',
      'quot' => '"',
      'apos' => "'"
    }.freeze

    def emit_text(text)
      decoded = unescape(text)
      @handler.characters(decoded) if @handler.respond_to?(:characters)
    end

    def unescape(str)
      return '' if str.nil? || str.empty?
      str = str.dup.force_encoding('UTF-8')
      str.gsub!(/&(amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);/) do
        m = $1
        if m.start_with?('#x')
          [m[2..].to_i(16)].pack('U')
        elsif m.start_with?('#')
          [m[1..].to_i].pack('U')
        else
          ENTITY_MAP[m] || "&#{m};"
        end
      end
      str
    end
  end
end
