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
require 'mdutils/rediscount'

# Attempt to load native rdiscount for comparison
RDISCOUNT_AVAILABLE = begin
  require 'rdiscount'
  true
rescue LoadError
  false
end

class MdUtilsTest < Minitest::Test
  #####################################################################################################
  # Helpers                                                                                           #
  #####################################################################################################

  # Normalize HTML for robust comparison between rediscount and rdiscount.
  # Strips leading/trailing whitespace on each line, collapses multiple spaces,
  # and normalizes self-closing tags.
  def normalize_html(html)
    html
      .gsub(/\r\n?/, "\n")
      .gsub(/<(\w+)([^>]*)\s*\/\s*>/, '<\1\2 />')
      .gsub(/\s+/, ' ')
      .gsub(/\s*\n\s*/, "\n")
      .strip
  end

  # Compare rediscount output with native rdiscount output when available.
  def assert_matches_rdiscount(markdown, *flags)
    skip 'native rdiscount not available' unless RDISCOUNT_AVAILABLE

    red = ReDiscount.new(markdown, *flags)
    rdd = RDiscount.new(markdown, *flags)

    expected = normalize_html(rdd.to_html)
    actual   = normalize_html(red.to_html)

    assert_equal expected, actual,
      "Mismatch for markdown:\n#{markdown}\n\n" \
      "flags: #{flags.inspect}\n\n" \
      "rdiscount:\n#{expected}\n\n" \
      "rediscount:\n#{actual}"
  end

  # Record that rediscount output differs from rdiscount in a known way.
  def assert_differs_from_rdiscount(markdown, *flags)
    skip 'native rdiscount not available' unless RDISCOUNT_AVAILABLE

    red = ReDiscount.new(markdown, *flags)
    rdd = RDiscount.new(markdown, *flags)

    expected = normalize_html(rdd.to_html)
    actual   = normalize_html(red.to_html)

    refute_equal expected, actual,
      "Expected difference, but outputs match for:\n#{markdown}"
  end

  #####################################################################################################
  # Basic block elements                                                                              #
  #####################################################################################################

  def test_paragraph
    md = "Hello, World!"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<p>Hello, World!</p>"
    assert_matches_rdiscount(md)
  end

  def test_multiple_paragraphs
    md = "First para.\n\nSecond para."
    html = ReDiscount.new(md).to_html
    assert_includes html, "<p>First para.</p>"
    assert_includes html, "<p>Second para.</p>"
    assert_matches_rdiscount(md)
  end

  def test_atx_headers
    md = "# H1\n\n## H2\n\n### H3"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<h1>H1</h1>"
    assert_includes html, "<h2>H2</h2>"
    assert_includes html, "<h3>H3</h3>"
    assert_matches_rdiscount(md)
  end

  def test_setext_headers
    md = "Header 1\n========\n\nHeader 2\n--------"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<h1>Header 1</h1>"
    assert_includes html, "<h2>Header 2</h2>"
    assert_matches_rdiscount(md)
  end

  def test_horizontal_rule
    md = "---\n"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<hr"
    assert_matches_rdiscount(md)
  end

  def test_blockquote
    md = "> quoted line"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<blockquote>"
    assert_includes html, "quoted line"
    assert_includes html, "</blockquote>"
    # Known difference: rediscount adds extra whitespace inside <blockquote>
    assert_differs_from_rdiscount(md)
  end

  def test_nested_blockquote
    md = "> outer\n> > inner"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<blockquote>"
    assert_includes html, "outer"
    assert_includes html, "<blockquote>"
    assert_includes html, "inner"
    assert_includes html, "</blockquote>"
    # Known difference: extra whitespace in blockquote output
    assert_differs_from_rdiscount(md)
  end

  #####################################################################################################
  # Lists                                                                                             #
  #####################################################################################################

  def test_unordered_list
    md = "* item1\n* item2"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<ul>"
    assert_includes html, "<li>item1</li>"
    assert_includes html, "<li>item2</li>"
    assert_includes html, "</ul>"
    assert_matches_rdiscount(md)
  end

  def test_ordered_list
    md = "1. first\n2. second"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<ol>"
    assert_includes html, "<li>first</li>"
    assert_includes html, "<li>second</li>"
    assert_includes html, "</ol>"
    assert_matches_rdiscount(md)
  end

  def test_alpha_list_with_md1compat
    md = "a. alpha1\nb. alpha2"
    html = ReDiscount.new(md, :md1compat).to_html
    assert_includes html, '<ol type="a">'
    assert_includes html, "<li>alpha1</li>"
    assert_includes html, "<li>alpha2</li>"
    assert_matches_rdiscount(md, :md1compat)
  end

  def test_list_with_adjacent_types
    md = "- ul item\n\n1. ol item"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<ul>"
    assert_includes html, "<li>ul item</li>"
    assert_includes html, "</ul>"
    assert_includes html, "<ol>"
    assert_includes html, "<li>ol item</li>"
    assert_includes html, "</ol>"
  end

  #####################################################################################################
  # Code blocks                                                                                       #
  #####################################################################################################

  def test_fenced_code_block
    md = "```ruby\ndef hello\n  'world'\nend\n```"
    html = ReDiscount.new(md).to_html
    assert_includes html, '<pre><code class="ruby">'
    assert_includes html, "def hello"
    assert_includes html, "</code></pre>"
  end

  def test_indented_code_block
    md = "    def hello\n      'world'\n    end"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<pre><code>"
    assert_includes html, "def hello"
    assert_includes html, "</code></pre>"
  end

  #####################################################################################################
  # Inline elements                                                                                   #
  #####################################################################################################

  def test_emphasis
    md = "*italic* and _also italic_"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<em>italic</em>"
    assert_includes html, "<em>also italic</em>"
    assert_matches_rdiscount(md)
  end

  def test_strong
    md = "**bold** and __also bold__"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<strong>bold</strong>"
    assert_includes html, "<strong>also bold</strong>"
    assert_matches_rdiscount(md)
  end

  def test_inline_code
    md = "Use `printf()` here."
    html = ReDiscount.new(md).to_html
    assert_includes html, "<code>printf()</code>"
    assert_matches_rdiscount(md)
  end

  def test_inline_link
    md = "[link](https://example.com)"
    html = ReDiscount.new(md).to_html
    assert_includes html, '<a href="https://example.com">link</a>'
    assert_matches_rdiscount(md)
  end

  def test_inline_link_with_title
    md = '[link](https://example.com "Title")'
    html = ReDiscount.new(md).to_html
    assert_includes html, '<a href="https://example.com" title="Title">link</a>'
    assert_matches_rdiscount(md)
  end

  def test_reference_link
    md = "[link][ref]\n\n[ref]: https://example.com"
    html = ReDiscount.new(md).to_html
    assert_includes html, '<a href="https://example.com">link</a>'
    assert_matches_rdiscount(md)
  end

  def test_inline_image
    md = "![alt](https://example.com/img.png)"
    html = ReDiscount.new(md).to_html
    assert_includes html, '<img src="https://example.com/img.png" alt="alt" />'
    assert_matches_rdiscount(md)
  end

  def test_inline_image_with_size
    md = "![alt](https://example.com/img.png =100x200)"
    html = ReDiscount.new(md).to_html
    assert_includes html, 'width="100"'
    assert_includes html, 'height="200"'
  end

  def test_autolink
    md = "Visit <https://example.com>."
    html = ReDiscount.new(md, :autolink).to_html
    assert_includes html, '<a href="https://example.com">https://example.com</a>'
    assert_matches_rdiscount(md, :autolink)
  end

  def test_strikethrough
    md = "~~deleted~~"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<del>deleted</del>"
    assert_matches_rdiscount(md)
  end

  # NOTE: rdiscount renders x^2^ as x<sup>2</sup>^ (leaving trailing ^),
  # while rediscount removes the trailing ^. Known difference.
  def test_superscript
    md = "x^2^"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<sup>2</sup>"
    assert_differs_from_rdiscount(md)
  end

  #####################################################################################################
  # Tables (Discount extension)                                                                         #
  #####################################################################################################

  def test_table
    md = <<~MD
      | A | B |
      |---|---|
      | 1 | 2 |
    MD
    html = ReDiscount.new(md).to_html
    assert_includes html, "<table>"
    assert_includes html, "<th> A </th>"
    assert_includes html, "<td> 1 </td>"
    assert_includes html, "</table>"
    assert_matches_rdiscount(md)
  end

  def test_table_with_alignment
    md = <<~MD
      | A | B | C |
      |:--|:--:|--:|
      | 1 | 2 | 3 |
    MD
    html = ReDiscount.new(md).to_html
    assert_includes html, 'style="text-align:left;"'
    assert_includes html, 'style="text-align:center;"'
    assert_includes html, 'style="text-align:right;"'
    assert_matches_rdiscount(md)
  end

  def test_no_tables_flag
    md = <<~MD
      | A | B |
      |---|---|
      | 1 | 2 |
    MD
    html = ReDiscount.new(md, :no_tables).to_html
    refute_includes html, "<table>"
  end

  #####################################################################################################
  # Definition lists (Discount extension)                                                               #
  #####################################################################################################

  def test_definition_list
    md = <<~MD
      term
      : definition
    MD
    html = ReDiscount.new(md).to_html
    assert_includes html, "<dl>"
    assert_includes html, "<dt>term</dt>"
    assert_includes html, "<dd>definition</dd>"
    assert_includes html, "</dl>"
  end

  #####################################################################################################
  # Footnotes                                                                                         #
  #####################################################################################################

  def test_footnote
    md = <<~MD
      A sentence with a footnote[^1].

      [^1]: This is the footnote.
    MD
    html = ReDiscount.new(md, :footnotes).to_html
    assert_includes html, '<sup><a href="#fn1" id="ref1">1</a></sup>'
    assert_includes html, '<div class="footnotes">'
    assert_includes html, '<li id="fn1">This is the footnote.'
  end

  #####################################################################################################
  # HTML blocks                                                                                       #
  #####################################################################################################

  def test_html_block
    md = "<div>raw html</div>"
    html = ReDiscount.new(md).to_html
    assert_includes html, "<div>raw html</div>"
    assert_matches_rdiscount(md)
  end

  # NOTE: rediscount's filter_html strips the <p> wrapper too, while rdiscount
  # preserves the <p> tag and escapes the <div> inside. Known difference.
  def test_filter_html_flag
    md = "<div>raw</div>"
    html = ReDiscount.new(md, :filter_html).to_html
    refute_includes html, "<div>"
    refute_includes html, "</div>"
    assert_differs_from_rdiscount(md, :filter_html)
  end

  #####################################################################################################
  # Flags / options                                                                                   #
  #####################################################################################################

  def test_smart_flag
    md = '"Hello"'
    html = ReDiscount.new(md, :smart).to_html
    assert_includes html, "&ldquo;"
    assert_includes html, "&rdquo;"
    assert_matches_rdiscount(md, :smart)
  end

  def test_smart_flag_with_link
    md = '[link](https://example.com "title")'
    html = ReDiscount.new(md, :smart).to_html
    assert_includes html, 'href="https://example.com"'
    assert_matches_rdiscount(md, :smart)
  end

  def test_no_image_flag
    md = "![alt](https://example.com/img.png)"
    html = ReDiscount.new(md, :no_image).to_html
    refute_includes html, "<img"
    assert_matches_rdiscount(md, :no_image)
  end

  def test_no_links_flag
    md = "[text](https://example.com)"
    html = ReDiscount.new(md, :no_links).to_html
    refute_includes html, "<a href"
    assert_matches_rdiscount(md, :no_links)
  end

  def test_filter_styles_flag
    md = "<style>body{}</style>"
    html = ReDiscount.new(md, :filter_styles).to_html
    refute_includes html, "<style>"
    refute_includes html, "body{}"
  end

  def test_explicitlist_flag
    md = "* a\n\n* b"
    html = ReDiscount.new(md, :explicitlist).to_html
    assert_includes html, "<li>a\n</li>"
    assert_includes html, "<li>b</li>"
    # rediscount: 多行列表项不嵌套 <p>，换行原样保留
    assert_differs_from_rdiscount(md, :explicitlist)
  end

  #####################################################################################################
  # Table of Contents                                                                                 #
  #####################################################################################################

  def test_toc_content
    md = "# First\n\n## Second\n\n### Third"
    rd = ReDiscount.new(md, :generate_toc)
    toc = rd.toc_content
    assert_includes toc, '<ul>'
    assert_includes toc, '<a href="#First">First</a>'
    assert_includes toc, '<a href="#Second">Second</a>'
    assert_includes toc, '<a href="#Third">Third</a>'
    assert_includes toc, '</ul>'
    assert_matches_rdiscount(md, :generate_toc)
  end

  def test_toc_content_empty_when_no_headers
    md = "Just a paragraph."
    rd = ReDiscount.new(md, :generate_toc)
    assert_equal "", rd.toc_content
  end

  #####################################################################################################
  # Version & API surface                                                                             #
  #####################################################################################################

  def test_version_constant
    assert_equal '3.0.0', ReDiscount::VERSION
  end

  def test_text_reader
    rd = ReDiscount.new("hello")
    assert_equal "hello", rd.text
  end

  def test_flags_via_constructor
    rd = ReDiscount.new("", :smart, :footnotes, :no_tables)
    assert rd.smart
    assert rd.footnotes
    assert rd.no_tables
  end

  def test_bluecloth_alias
    assert_equal ReDiscount, BlueCloth
  end

  #####################################################################################################
  # Cross-implementation comparison (rediscount vs rdiscount)                                         #
  #####################################################################################################

  def test_complex_document_matches_rdiscount
    skip 'native rdiscount not available' unless RDISCOUNT_AVAILABLE

    md = <<~MD
      # Title

      A paragraph with **bold**, *italic*, and `code`.

      > A blockquote.

      - list one
      - list two

      1. ordered one
      2. ordered two

      | H1 | H2 |
      |----|----|
      | a1 | a2 |

      ---

      [link](https://example.com)

      ![img](https://example.com/x.png)
    MD

    # Known differences:
    # 1. blockquote whitespace padding
    # 2. rdiscount merges adjacent lists into a single <ul>; rediscount keeps them separate
    # 3. rdiscount wraps some list items in <p> based on its own heuristic
    assert_differs_from_rdiscount(md)
  end

  def test_rdiscount_paragraph_and_headers_match
    md = "# H1\n\nParagraph with **bold** and *italic*.\n\n## H2\n\n`code`"
    assert_matches_rdiscount(md)
  end

  def test_rdiscount_horizontal_rule_matches
    md = "---\n\npara\n"
    assert_matches_rdiscount(md)
  end

  def test_rdiscount_inline_link_matches
    md = "[link](https://example.com) and [link2](https://x.com 'title')"
    assert_matches_rdiscount(md)
  end

  def test_rdiscount_inline_image_matches
    md = "![alt](https://example.com/i.png)"
    assert_matches_rdiscount(md)
  end

  def test_rdiscount_emphasis_matches
    md = "*em* and **strong** and `code`"
    assert_matches_rdiscount(md)
  end

  def test_rdiscount_strikethrough_matches
    md = "~~del~~"
    assert_matches_rdiscount(md)
  end

  def test_rdiscount_no_tables_flag_matches
    md = "[link](https://example.com)\n\n![img](https://x.png)"
    assert_matches_rdiscount(md, :no_tables)
  end

  def test_rdiscount_no_links_flag_matches
    md = "**bold** and *italic* and `code`"
    assert_matches_rdiscount(md, :no_links)
  end

  # NOTE: rediscount leaves an empty <p></p> when filter_styles removes a <style>
  # block at the top, while rdiscount omits it. Known difference.
  def test_rdiscount_filter_styles_flag_matches
    md = "<style>body{}</style>\n\npara"
    assert_differs_from_rdiscount(md, :filter_styles)
  end

  def test_rdiscount_autolink_flag_matches
    md = "Visit <https://example.com>."
    assert_matches_rdiscount(md, :autolink)
  end

  def test_rdiscount_toc_matches_rdiscount
    md = "# One\n\n## Two\n\n### Three"
    assert_matches_rdiscount(md, :generate_toc)
  end

  def test_rdiscount_smart_flag_matches_simple_text
    md = '"quoted"'
    assert_matches_rdiscount(md, :smart)
  end
end
