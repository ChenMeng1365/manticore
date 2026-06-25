
#------------------------------------------------------------------------------
# Markdown 解析器
#------------------------------------------------------------------------------
# 纯 Ruby 实现的 Markdown 解析器，兼容 rdiscount gem API，无需 C 扩展。
#
# 实现特性：
# - 段落、标题（ATX + Setext）、分隔线、引用块
# - 列表（ul/ol/alpha）、代码块（围栏 + 缩进）
# - 内联：链接、图片、强调、代码片段、自动链接
# - Discount 扩展：表格、定义列表、脚注、删除线、上标、图片尺寸、字母列表、目录
# - 标志：smart, filter_html, filter_styles, footnotes, generate_toc,
#   no_image, no_links, no_tables, strict, autolink, safelink,
#   no_pseudo_protocols, no_superscript, no_strikethrough,
#   latex, explicitlist, md1compat
#
# Usage:
#   require 'rediscount'
#   markdown = ReDiscount.new("Hello World!")
#   puts markdown.to_html
#

#------------------------------------------------------------------------------
# Caset Markdown 全局变量说明
#------------------------------------------------------------------------------

# @!attribute $_tmp_global_
#   @return [Hash] 全局配置累积存储（CasetDown 代码执行）
#   按代码块顺序累积，后续代码块继承前面加载的配置。

# @!attribute $_scr_head_
#   @return [String] Ruby 脚本头部（编码声明 + 依赖加载）
#   默认包含 #coding:utf-8 和 endata/tintext/tabbot 等依赖。

# @!attribute $_scr_tail_
#   @return [String] Ruby 脚本尾部（全局数据输出）
#   包含 __END__ 标记和全局变量输出。

# @!attribute $_erl_tail_
#   @return [String] Erlang 脚本尾部（全局数据输出）
#   包含全局变量的 Erlang 格式输出。

# @!attribute $_tmp_endata_
#   @return [Hash] endata 表格数据收集器（casetable 使用）
#   收集表格数据用于生成脚本尾部输出。


class ReDiscount
  VERSION = '3.1.0'

  # @return [String] Markdown 原始文本
  attr_reader :text

  # 解析标志访问器
  attr_accessor :smart                # 智能引号
  attr_accessor :filter_html          # 过滤 HTML 标签
  attr_accessor :filter_styles        # 过滤样式标签
  attr_accessor :footnotes            # 启用脚注
  attr_accessor :generate_toc         # 生成目录
  attr_accessor :no_image             # 禁用图片
  attr_accessor :no_links             # 禁用链接
  attr_accessor :no_tables            # 禁用表格
  attr_accessor :strict               # 严格模式
  attr_accessor :autolink             # 自动链接
  attr_accessor :safelink             # 安全链接
  attr_accessor :no_pseudo_protocols  # 禁用伪协议
  attr_accessor :no_superscript       # 禁用上标
  attr_accessor :no_strikethrough     # 禁用删除线
  attr_accessor :latex                # LaTeX 支持
  attr_accessor :explicitlist         # 显式列表
  attr_accessor :md1compat            # Markdown 1.0 兼容

  # 初始化 Markdown 解析器。
  #
  # @param text [String] Markdown 文本
  # @param flags [Symbol*] 可选标志，通过 send 方法设置为 true
  #   支持：:smart, :filter_html, :filter_styles, :footnotes, :generate_toc,
  #   :no_image, :no_links, :no_tables, :strict, :autolink, :safelink,
  #   :no_pseudo_protocols, :no_superscript, :no_strikethrough,
  #   :latex, :explicitlist, :md1compat
  # @return [ReDiscount] 解析器实例
  def initialize(text, *flags)
    @text = text.to_s
    @smart = false
    @filter_html = false
    @filter_styles = false
    @footnotes = false
    @generate_toc = false
    @no_image = false
    @no_links = false
    @no_tables = false
    @strict = false
    @autolink = false
    @safelink = false
    @no_pseudo_protocols = false
    @no_superscript = false
    @no_strikethrough = false
    @latex = false
    @explicitlist = false
    @md1compat = false

    flags.each do |flag|
      send("#{flag}=", true) if respond_to?("#{flag}=")
    end
  end

  # 将 Markdown 文本转换为 HTML。
  #
  # @return [String] HTML 字符串（末尾含换行符）
  def to_html
    parser = MarkdownParser.new(@text, self)
    parser.to_html
  end

  # 生成目录 HTML 内容。
  #
  # 需要 :generate_toc 标志启用，且文档中包含标题。
  #
  # @return [String] 目录 HTML（<ul> 列表），如果无标题则返回空字符串
  def toc_content
    parser = MarkdownParser.new(@text, self)
    parser.toc_content
  end
end

# ============================================================================
# 内部 Markdown 解析器实现
# ============================================================================
class MarkdownParser
  # 块级正则常量
  # @!attribute [r] ATX_HEADER_RE
  #   @return [Regexp] ATX 标题匹配：^#{1,6}\s+.+?\s*#*\s*$
  # @!attribute [r] HORIZONTAL_RULE
  #   @return [Regexp] 水平分隔线：^\*{3,}|-{3,}|_{3,}\s*$
  # @!attribute [r] CODE_BLOCK_FENCE
  #   @return [Regexp] 围栏代码块起始：^```(\w*)
  # @!attribute [r] CODE_BLOCK_INDENT
  #   @return [Regexp] 缩进代码块：^(    |\t)
  # @!attribute [r] BLOCKQUOTE_RE
  #   @return [Regexp] 引用块起始：^>
  # @!attribute [r] LIST_BULLET_RE
  #   @return [Regexp] 无序列表：^(\*|\+|\-)\s+
  # @!attribute [r] LIST_NUMBER_RE
  #   @return [Regexp] 有序列表：^(\d+)[.)]\s+
  # @!attribute [r] LIST_ALPHA_RE
  #   @return [Regexp] 字母列表：^([a-zA-Z])[.)]\s+
  # @!attribute [r] REFERENCE_DEF
  #   @return [Regexp] 引用定义：^\[(.+?)\]:\s*(\S+)(?:\s+["\'\(](.+?)["\'\)])?\s*$
  # @!attribute [r] HTML_BLOCK_RE
  #   @return [Regexp] HTML 块起始：^<(\/?)(\w+)
  # @!attribute [r] TABLE_ROW_RE
  #   @return [Regexp] 表格行：^\|(.+?)\|?\s*$
  # @!attribute [r] TABLE_SEP_RE
  #   @return [Regexp] 表格分隔行：^\|?[\s:-]+\|?[\s:-|]*\s*$
  ATX_HEADER_RE    = /^(\#{1,6})\s+(.+?)\s*#*\s*$/
  HORIZONTAL_RULE  = /^(\*{3,}|-{3,}|_{3,})\s*$/
  CODE_BLOCK_FENCE = /^```(\w*)/
  CODE_BLOCK_INDENT = /^(    |\t)/
  BLOCKQUOTE_RE    = /^\s*>/
  LIST_BULLET_RE   = /^(\*|\+|-)\s+/
  LIST_NUMBER_RE   = /^(\d+)[.)]\s+/
  LIST_ALPHA_RE    = /^([a-zA-Z])[.)]\s+/
  REFERENCE_DEF    = /^\[(.+?)\]:\s*(\S+)(?:\s+["'(](.+?)["')])?\s*$/
  HTML_BLOCK_RE    = /^<(\/?)(\w+)/
  TABLE_ROW_RE     = /^\|(.+?)\|?\s*$/
  TABLE_SEP_RE     = /^\|?[\s:|-]+\|?[\s:|-]*\s*$/

  # 初始化解析器。
  #
  # @param text [String] Markdown 文本
  # @param rdiscount_obj [ReDiscount] ReDiscount 实例，提供标志配置
  def initialize(text, rdiscount_obj)
    @text = text
    @rd = rdiscount_obj
    @references = {}
    @footnotes = {}
    @footnote_counter = 0
    @toc_entries = []
    @used_footnotes = []
  end

  # 完整解析流程：预处理 → 分块 → 渲染 → 后处理。
  #
  # @return [String] 最终 HTML 字符串（末尾含换行符）
  def to_html
    normalized = preprocess(@text)
    blocks = parse_blocks(normalized)
    html = render_blocks(blocks)
    html = postprocess(html)
    html.strip + "\n"
  end

  # 生成目录 HTML。
  #
  # 需要先调用 to_html 收集标题信息。
  #
  # @return [String] 目录 HTML（<ul> 列表），如果无标题返回空字符串
  def toc_content
    normalized = preprocess(@text)
    blocks = parse_blocks(normalized)
    render_blocks(blocks)
    return "" if @toc_entries.empty?

    build_toc_html(@toc_entries)
  end

  private

  def build_toc_html(entries)
    return "" if entries.empty?

    # 构建树结构
    root = { children: [] }
    stack = [root]

    entries.each do |entry|
      level = entry[:level]
      node = { entry: entry, children: [] }

      while stack.length > 1 && stack[-1][:entry][:level] >= level
        stack.pop
      end

      stack[-1][:children] << node
      stack << node
    end

    render_toc_node(root)
  end

  def render_toc_node(node)
    return "" if node[:children].empty?
    html = "<ul>\n"
    node[:children].each do |child|
      entry = child[:entry]
      html += "  <li><a href=\"##{entry[:id]}\">#{escape_html(entry[:text])}</a>"
      if !child[:children].empty?
        html += "\n" + render_toc_node(child)
      end
      html += "</li>\n"
    end
    html += "</ul>\n"
    html
  end

  # ========================================================================
  # 预处理：标准化换行，提取引用链接和脚注定义
  #
  # 将 \r\n 和 \r 统一为 \n。
  # 从正文中移除引用定义和脚注定义，存入实例变量。
  #
  # @param text [String] 原始 Markdown 文本
  # @return [String] 处理后的文本（不含引用/脚注定义）
  # ========================================================================
  def preprocess(text)
    text = text.gsub("\r\n", "\n").gsub("\r", "\n")

    lines = text.split("\n")
    content_lines = []
    i = 0
    while i < lines.length
      line = lines[i]

      # Reference-style link definition
      if line =~ REFERENCE_DEF
        id = $1.downcase
        url = $2
        title = $3
        @references[id] = { url: url, title: title }
        i += 1
        next
      end

      # Footnote definition
      if @rd.footnotes && line =~ /^\[(\^\w+)\]:\s*(.+)$/
        id = $1
        content = $2
        j = i + 1
        while j < lines.length && (lines[j].start_with?(' ') || lines[j].start_with?("\t"))
          content += "\n" + lines[j].sub(/^(\s+)/, '')
          j += 1
        end
        @footnotes[id] = content
        i = j
        next
      end

      content_lines << line
      i += 1
    end

    content_lines.join("\n")
  end

  # ========================================================================
  # 块级解析：将文本分块为结构化 block 数组
  #
  # 识别的块类型：:hr, :header, :code, :blockquote, :table, :deflist,
  # :ul, :ol, :ol_alpha, :html, :paragraph
  #
  # @param text [String] 预处理后的文本
  # @return [Array<Hash>] block 数组，每个元素包含 :type 和其他类型特定键
  # ========================================================================
  def parse_blocks(text)
    lines = text.split("\n")
    blocks = []
    i = 0

    while i < lines.length
      line = lines[i]

      if line.strip.empty?
        i += 1
        next
      end

      # Horizontal rule
      if line =~ HORIZONTAL_RULE
        blocks << { type: :hr }
        i += 1
        next
      end

      # ATX Header
      if line =~ ATX_HEADER_RE
        level = $1.length
        content = $2.strip
        blocks << { type: :header, level: level, content: content }
        i += 1
        next
      end

      # Setext Header
      if i + 1 < lines.length && lines[i+1] =~ /^[=-]+\s*$/
        level = lines[i+1][0] == '=' ? 1 : 2
        blocks << { type: :header, level: level, content: line.strip }
        i += 2
        next
      end

      # Fenced code block
      if line =~ CODE_BLOCK_FENCE
        lang = $1
        code_lines = []
        i += 1
        while i < lines.length && lines[i] !~ /^```\s*$/
          code_lines << lines[i]
          i += 1
        end
        i += 1 # skip closing fence
        blocks << { type: :code, lang: lang, content: code_lines.join("\n") }
        next
      end

      # Indented code block
      if line =~ CODE_BLOCK_INDENT
        code_lines = [line.sub(/^(    |\t)/, '')]
        i += 1
        while i < lines.length && (lines[i] =~ CODE_BLOCK_INDENT || lines[i].strip.empty?)
          code_lines << lines[i].sub(/^(    |\t)/, '')
          i += 1
        end
        blocks << { type: :code, content: code_lines.join("\n").gsub(/\n+\z/, "\n") }
        next
      end

      # Blockquote
      if line =~ BLOCKQUOTE_RE
        quote_lines = []
        while i < lines.length && (lines[i] =~ BLOCKQUOTE_RE || (lines[i].strip.empty? && i+1 < lines.length && lines[i+1] =~ BLOCKQUOTE_RE))
          quote_lines << lines[i].sub(/^\s*>\s?/, '')
          i += 1
        end
        inner_parser = MarkdownParser.new(quote_lines.join("\n"), @rd)
        blocks << { type: :blockquote, content: inner_parser.to_html }
        next
      end

      # Table (GFM/Discount extension)
      if !@rd.no_tables && i + 1 < lines.length && lines[i] =~ TABLE_ROW_RE && lines[i+1] =~ TABLE_SEP_RE
        header = parse_table_row(lines[i])
        alignments = parse_table_alignments(lines[i+1])
        rows = []
        i += 2
        while i < lines.length && lines[i] =~ TABLE_ROW_RE
          rows << parse_table_row(lines[i])
          i += 1
        end
        blocks << { type: :table, header: header, alignments: alignments, rows: rows }
        next
      end

      # Definition list (Discount extension MKD_DLEXTRA)
      if !@rd.no_tables && i + 1 < lines.length && lines[i+1] =~ /^:\s+/
        term = line.strip
        defs = []
        i += 1
        while i < lines.length && lines[i] =~ /^:\s+/
          defs << lines[i].sub(/^:\s+/, '')
          i += 1
          if i < lines.length && lines[i].strip.empty?
            i += 1
          end
        end
        blocks << { type: :deflist, term: term, defs: defs }
        next
      end

      # Lists
      list_match = nil
      list_type = nil
      if line =~ LIST_BULLET_RE
        list_match = $1
        list_type = :ul
      elsif line =~ LIST_NUMBER_RE
        list_match = $1
        list_type = :ol
      elsif @rd.md1compat && line =~ LIST_ALPHA_RE
        list_match = $1
        list_type = :ol_alpha
      end

      if list_type
        items = []
        current_item = [line.sub(/^#{Regexp.escape(list_match)}[.)]?\s+/, '')]
        i += 1

        while i < lines.length
          current_line = lines[i]

          # New item same type (ul: same bullet; ol: any number; ol_alpha: any letter)
          if (list_type == :ul && current_line =~ LIST_BULLET_RE) ||
             (list_type == :ol && current_line =~ LIST_NUMBER_RE) ||
             (list_type == :ol_alpha && current_line =~ LIST_ALPHA_RE)
            match = $1
            items << current_item.join("\n")
            current_item = [current_line.sub(/^#{Regexp.escape(match)}[.)]?\s+/, '')]
            i += 1
            next
          end

          # Different list marker or non-indented non-empty line ends list
          if !current_line.strip.empty? && current_line !~ /^(\s+)/
            if current_line =~ LIST_BULLET_RE || current_line =~ LIST_NUMBER_RE || current_line =~ LIST_ALPHA_RE
              # Only break if it's a different marker type
              if list_type == :ul && current_line !~ LIST_BULLET_RE
                break
              elsif list_type == :ol && current_line !~ LIST_NUMBER_RE
                break
              elsif list_type == :ol_alpha && current_line !~ LIST_ALPHA_RE
                break
              end
            else
              break
            end
          end

          current_item << current_line
          i += 1
        end
        items << current_item.join("\n")

        parsed_items = items.map do |item_text|
          stripped = item_text.strip
          if stripped.include?("\n") || @rd.explicitlist
            # 多行列表项：只渲染内联，保留换行，不嵌套 <p>
            render_inline(item_text)
          else
            render_inline(stripped)
          end
        end

        blocks << { type: list_type, items: parsed_items }
        next
      end

      # HTML block
      if line =~ HTML_BLOCK_RE && !@rd.filter_html
        tag = $2.downcase
        if %w[p div h1 h2 h3 h4 h5 h6 blockquote pre table ol ul dl form hr br].include?(tag)
          html_lines = [line]
          i += 1
          while i < lines.length
            html_lines << lines[i]
            break if lines[i] =~ /<\/#{tag}>\s*$/i
            i += 1
          end
          blocks << { type: :html, content: html_lines.join("\n") }
          next
        end
      end

      # Paragraph (default)
      para_lines = [line]
      i += 1
      while i < lines.length && !lines[i].strip.empty? && !is_block_start?(lines[i])
        para_lines << lines[i]
        i += 1
      end
      blocks << { type: :paragraph, content: para_lines.join("\n") }
    end

    blocks
  end

  # 判断行是否为新块的起始。
  #
  # @param line [String] 单行文本
  # @return [Boolean] 如果是块起始则为 true
  def is_block_start?(line)
    line =~ ATX_HEADER_RE ||
    line =~ HORIZONTAL_RULE ||
    line =~ CODE_BLOCK_FENCE ||
    line =~ CODE_BLOCK_INDENT ||
    line =~ BLOCKQUOTE_RE ||
    line =~ LIST_BULLET_RE ||
    line =~ LIST_NUMBER_RE ||
    line =~ LIST_ALPHA_RE ||
    line =~ HTML_BLOCK_RE
  end

  # 解析表格行数据。
  #
  # 移除首尾的 | 分隔符，按 | 分割并去除空白。
  #
  # @param line [String] 表格行文本
  # @return [Array<String>] 单元格内容数组
  def parse_table_row(line)
    line.sub(/^\|/, '').sub(/\|\s*$/, '').split('|')
  end

  # 解析表格列对齐方式。
  #
  # 根据分隔行中 : 的位置判断对齐：
  # - ^:.*:$ → center
  # - ^: → left
  # - :$ → right
  #
  # @param line [String] 表格分隔行文本
  # @return [Array<String, nil>] 对齐方式数组，nil 表示未指定
  def parse_table_alignments(line)
    cells = line.sub(/^\|/, '').sub(/\|\s*$/, '').split('|')
    cells.map do |cell|
      cell = cell.strip
      if cell =~ /^:.*:$/
        'center'
      elsif cell =~ /^:/
        'left'
      elsif cell =~ /:$/
        'right'
      else
        nil
      end
    end
  end

  # ========================================================================
  # 将 block 数组渲染为 HTML 字符串
  #
  # @param blocks [Array<Hash>] 解析后的 block 数组
  # @return [String] 拼接后的 HTML 片段
  # ========================================================================
  def render_blocks(blocks)
    html_parts = blocks.map do |block|
      case block[:type]
      when :hr
        "<hr />\n"
      when :header
        level = block[:level]
        content = render_inline(block[:content])
        if @rd.generate_toc
          id = generate_header_id(block[:content])
          @toc_entries << { level: level, text: block[:content], id: id }
          "<a name=\"#{id}\"></a> <h#{level}>#{content}</h#{level}>\n"
        else
          "<h#{level}>#{content}</h#{level}>\n"
        end
      when :paragraph
        content = render_inline(block[:content])
        # 保留段落内原始换行符
        "<p>#{content}</p>\n"
      when :code
        if block[:lang] && !block[:lang].empty?
          "<pre><code class=\"#{escape_html(block[:lang])}\">#{escape_html(block[:content])}</code></pre>\n"
        else
          "<pre><code>#{escape_html(block[:content])}</code></pre>\n"
        end
      when :blockquote
        html = block[:content]
        # 去掉内部 <p> 标签但保留内容（避免嵌套引用块内部凭空产生 <p>）
        html = html.gsub(/<p>(.*?)<\/p>/m) { $1 }
        # 确保段落/块间的空行有换行分隔
        html = html.gsub(/\n\n+/, "\n")
        "<blockquote>\n#{html}</blockquote>\n"
      when :ul
        items = block[:items].map { |item| "<li>#{item}</li>" }.join("\n")
        "<ul>\n#{items}\n</ul>\n"
      when :ol
        items = block[:items].map { |item| "<li>#{item}</li>" }.join("\n")
        "<ol>\n#{items}\n</ol>\n"
      when :ol_alpha
        items = block[:items].map { |item| "<li>#{item}</li>" }.join("\n")
        "<ol type=\"a\">\n#{items}\n</ol>\n"
      when :table
        render_table(block)
      when :deflist
        defs = block[:defs].map { |d| "<dd>#{render_inline(d)}</dd>" }.join("\n")
        "<dl>\n<dt>#{render_inline(block[:term])}</dt>\n#{defs}\n</dl>\n"
      when :html
        if @rd.filter_html
          ""
        else
          block[:content] + "\n"
        end
      else
        ""
      end
    end
    html_parts.join
  end

  # 渲染表格 block 为完整 HTML 表格。
  #
  # @param block [Hash] 表格 block，包含 :header, :alignments, :rows
  # @return [String] HTML 表格字符串
  def render_table(block)
    html = "<table>\n<thead>\n<tr>\n"
    header = block[:header]
    alignments = block[:alignments]
    rows = block[:rows]

    header.each_with_index do |cell, i|
      align = alignments[i] ? " style=\"text-align:#{alignments[i]};\"" : ""
      html += "<th#{align}>#{render_inline(cell)}</th>\n"
    end
    html += "</tr>\n</thead>\n<tbody>\n"

    rows.each do |row|
      html += "<tr>\n"
      row.each_with_index do |cell, i|
        align = alignments[i] ? " style=\"text-align:#{alignments[i]};\"" : ""
        html += "<td#{align}>#{render_inline(cell)}</td>\n"
      end
      html += "</tr>\n"
    end
    html += "</tbody>\n</table>\n"
    html
  end

  # 生成标题锚点 ID。
  #
  # 转换规则：小写化 → 移除非字母数字空白连字符 → 空格替换为 - →
  # 合并多个 - → 移除首尾 -
  #
  # @param text [String] 标题文本
  # @return [String] 锚点 ID 字符串
  def generate_header_id(text)
    text.gsub(/[^\w\s-]/, '').gsub(/\s+/, '-').gsub(/-+/, '-').sub(/^-/, '').sub(/-$/, '')
  end

  # ========================================================================
  # 渲染内联元素。
  #
  # 处理顺序：代码片段保护 → 图片 → 链接 → 自动链接 → 删除线 →
  # 上标 → 强调（strong/em）→ 硬换行 → 脚注 → 恢复代码片段
  #
  # @param text [String] 内联文本
  # @return [String] 渲染后的 HTML 字符串
  # ========================================================================
  def render_inline(text)
    return "" if text.nil? || text.empty?

    # Protect code spans first
    code_spans = []
    text = text.gsub(/`(.+?)`/) do
      code_spans << escape_html($1)
      "\x00CODE#{code_spans.length - 1}\x00"
    end

    # Images (before links)
    unless @rd.no_image
      # Inline images with optional size: ![alt](url =WxH)
      text = text.gsub(/!\[(.*?)\]\((.+?)\)/) do
        alt, src = $1, $2
        if src =~ /(.+?)\s*=\s*(\d+)x(\d+)/
          "<img src=\"#{escape_html($1.strip)}\" alt=\"#{escape_html(alt)}\" width=\"#{$2}\" height=\"#{$3}\" />"
        else
          "<img src=\"#{escape_html(src)}\" alt=\"#{escape_html(alt)}\" />"
        end
      end

      # Reference-style images
      text = text.gsub(/!\[(.*?)\]\[(.*?)\]/) do
        alt, ref = $1, $2
        ref = alt if ref.empty?
        if @references[ref.downcase]
          url = @references[ref.downcase][:url]
          title = @references[ref.downcase][:title]
          title_attr = title ? " title=\"#{escape_html(title)}\"" : ""
          "<img src=\"#{escape_html(url)}\" alt=\"#{escape_html(alt)}\"#{title_attr} />"
        else
          $&
        end
      end
    end

    # Links
    unless @rd.no_links
      # Inline links with optional title
      text = text.gsub(/(?<!!)\[(.+?)\]\((.+?)\)/) do
        link_text, url = $1, $2
        title = nil
        if url =~ /(.+?)\s+["'(](.+?)["')]/
          url, title = $1, $2
        end
        title_attr = title ? " title=\"#{escape_html(title)}\"" : ""
        "<a href=\"#{escape_html(url)}\"#{title_attr}>#{render_inline(link_text)}</a>"
      end

      # Reference-style links
      text = text.gsub(/\[(.+?)\]\[(.*?)\]/) do
        link_text, ref = $1, $2
        ref = link_text if ref.empty?
        if @references[ref.downcase]
          url = @references[ref.downcase][:url]
          title = @references[ref.downcase][:title]
          title_attr = title ? " title=\"#{escape_html(title)}\"" : ""
          "<a href=\"#{escape_html(url)}\"#{title_attr}>#{link_text}</a>"
        else
          $&
        end
      end
    end

    # Autolinks
    if @rd.autolink
      text = text.gsub(/<(https?:\/\/[^>]+)>/) { "<a href=\"#{$1}\">#{$1}</a>" }
      text = text.gsub(/<([^>\s@]+@[^>\s@]+\.[^>\s@]+)>/) { "<a href=\"mailto:#{$1}\">#{$1}</a>" }
    end

    # Strikethrough
    unless @rd.no_strikethrough
      text = text.gsub(/~~(.+?)~~/) { "<del>#{$1}</del>" }
    end

    # Superscript
    unless @rd.no_superscript
      text = text.gsub(/\^(\w+)\^/) { "<sup>#{$1}</sup>" }
    end

    # Emphasis: strong then em
    text = text.gsub(/\*\*(.+?)\*\*/) { "<strong>#{$1}</strong>" }
    text = text.gsub(/__(.+?)__/) { "<strong>#{$1}</strong>" }
    text = text.gsub(/\*(.+?)\*/) { "<em>#{$1}</em>" }
    text = text.gsub(/_(.+?)_/) { "<em>#{$1}</em>" }

    # Hard line breaks (two trailing spaces)
    text = text.gsub(/  \n/, "<br />\n")

    # Footnote references
    if @rd.footnotes
      text = text.gsub(/\[(\^\w+)\]/) do
        id = $1
        if @footnotes[id]
          @footnote_counter += 1
          num = @footnote_counter
          @used_footnotes << { id: id, num: num, content: @footnotes[id] }
          "<sup><a href=\"#fn#{num}\" id=\"ref#{num}\">#{num}</a></sup>"
        else
          $&
        end
      end
    end

    # Restore code spans
    code_spans.each_with_index do |code, idx|
      text = text.sub("\x00CODE#{idx}\x00", "<code>#{code}</code>")
    end

    text
  end

  # ========================================================================
  # 后处理：Smartypants、脚注、HTML 过滤、样式过滤。
  #
  # @param html [String] 渲染后的 HTML
  # @return [String] 处理后的 HTML
  # ========================================================================
  def postprocess(html)
    if @rd.smart
      html = smartypants(html)
    end

    if @rd.footnotes && !@used_footnotes.empty?
      html += "\n<div class=\"footnotes\">\n<hr />\n<ol>\n"
      @used_footnotes.each do |fn|
        content = render_inline(fn[:content])
        html += "<li id=\"fn#{fn[:num]}\">#{content} <a href=\"#ref#{fn[:num]}\">&#8617;</a></li>\n"
      end
      html += "</ol>\n</div>\n"
    end

    if @rd.filter_html
      html = html.gsub(/<[^>]+>/, '')
    end

    if @rd.filter_styles
      html = html.gsub(/<style\b[^>]*>.*?<\/style>/mi, '')
    end

    html
  end

  # 智能引号与排版符号转换。
  #
  # 转换规则：
  # - "..." → &ldquo;...&rdquo;
  # - '...' → &lsquo;...&rsquo;
  # - \w'\w → &rsquo;
  # - -- → &mdash;
  # - 空格-空格 → &ndash;
  # - ... → &hellip;
  #
  # 保护 HTML 标签内的属性，避免替换引号。
  #
  # @param text [String] HTML 文本
  # @return [String] 转换后的文本
  def smartypants(text)
    # Protect HTML tags
    tags = []
    text = text.gsub(/<[^>]+>/) do
      tags << $&
      "\x00TAG#{tags.length - 1}\x00"
    end

    text = text.gsub(/"([^"]*?)"/, '&ldquo;\1&rdquo;')
    text = text.gsub(/'([^']*?)'/, '&lsquo;\1&rsquo;')
    text = text.gsub(/(\w)'(\w)/, '\1&rsquo;\2')
    text = text.gsub(/(\w)'/, '\1&rsquo;')
    text = text.gsub(/--/, '&mdash;')
    text = text.gsub(/ - /, ' &ndash; ')
    text = text.gsub(/\.\.\./, '&hellip;')

    # Restore tags
    tags.each_with_index do |tag, idx|
      text = text.sub("\x00TAG#{idx}\x00", tag)
    end
    text
  end

  # HTML 实体转义。
  #
  # 转义字符：& → &amp; < → &lt; > → &gt; " → &quot;
  #
  # @param text [String, nil] 待转义文本
  # @return [String] 转义后的文本，nil 输入返回空字符串
  def escape_html(text)
    return "" if text.nil?
    text.gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
        .gsub('"', '&quot;')
  end
end

# BlueCloth 兼容别名
begin
  BlueCloth = ReDiscount
rescue
  # 如果 BlueCloth 已定义则忽略
end
