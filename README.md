# Manticore 

## XMLUtils Ruby XML 工具库（REXML 精简重写版）

本项目是`imdoc/XMLUtils`的再编集，改名为 `xml_doc.rb` 兼容层，将 `XmlUtils` DOM 转换为自定义 `XmlNode` 结构。
并重新实现了 Ruby XML 处理库，不再依赖原版 `REXML` Gem，完全独立命名空间 `XmlUtils`，包含解析器、DOM、XPath 和格式化输出四层架构。

### 架构原理

原版 `REXML` 的实现核心在于**基于事件的拉取解析器（Pull Parser）**与**树形构建器（Tree Parser）**的分离。本重写遵循同样的分层设计：

```
Source Text
    │
    ▼
┌─────────────────┐
│  Tokenizer      │  ← 词法分析：将原始字符流切分为 Token 序列
│  (词法分析器)    │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  TreeParser     │  ← 语法分析：根据 Token 序列构建 DOM 树
│  (树形解析器)    │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  DOM (Node)     │  ← 节点树：Document, Element, Text, Attribute...
│  (文档对象模型)  │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  XPath Engine   │  ← 查询引擎：基于节点树的路径表达式匹配
│  (查询引擎)      │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  Formatters     │  ← 序列化：将 DOM 树输出为格式化的 XML 字符串
│  (格式化输出)    │
└─────────────────┘
```

### 文件结构

```
lib/
├── manticore.rb             # 引用入口，require 'manticore'
├── xmlutils/
│   ├── node.rb              # 核心节点类（DOM）
│   ├── tokenizer.rb         # 词法分析器（Token）
│   ├── tree_parser.rb       # 树形解析器（Parser）
│   ├── xpath.rb             # XPath 简化查询引擎
│   ├── formatters.rb        # 序列化与格式化输出
│   └── xml_doc.rb           # 模型转换：XmlUtils DOM → XmlNode 
├── xlsxkit/
│   ├── zip_reader.rb        # 纯 Ruby ZIP32 读取器
│   ├── sax_parser.rb        # SAX 流式 XML 解析器
│   └── workbook.rb          # XLSX Workbook 高层 API
├── test/
│   ├── xml_doc_test.rb      # xml_doc测试用例
│   ├── xmlutils_test.rb     # xmlutils测试用例
│   └── xlsxkit_test.rb      # xlsxkit测试用例
├── manticore.gemspec        # Gem 打包配置
├── LICENSE                  # GNU AGPL-3.0 许可证
└── README.md
```

### 核心实现要点

#### 1. Tokenizer（词法分析器）

Tokenizer 将 XML 文本流拆分为语义化的 Token 序列。关键状态机逻辑：

- 遇到 `<` 时区分：起始标签 `<tag`、结束标签 `</tag>`、空标签 `<tag/>`、注释 `<!--`、CDATA `<![CDATA[`、DOCTYPE `<!DOCTYPE`、处理指令 `<?`
- 属性值支持单引号与双引号包裹
- 实体引用（`&amp;` 等）在词法阶段即展开为对应字符
- 文本节点在遇到 `<` 或 `&` 时截断，保证文本与标记严格分离

核心方法：`read_tag`、`read_comment`、`read_cdata`、`read_doctype`、`read_processing_instruction`、`read_text`、`read_entity_ref`

#### 2. TreeParser（树形解析器）

TreeParser 接收 Token 序列，递归构建 DOM 树：

- 使用栈隐式结构：遇到 `start_tag` 创建 `Element`，将其加入当前父节点；遇到 `close_tag` 时回溯
- 支持自闭合标签（`empty_tag`）无需等待关闭标签
- XML 声明、DOCTYPE、注释、CDATA、处理指令均作为独立节点插入树中
- 空白文本节点默认过滤（符合 REXML 标准行为）

#### 3. DOM 节点类（Node 层）

继承体系：

```
Node
├── ChildNode
│   ├── Text
│   ├── CData (继承 Text，raw 模式)
│   ├── Comment
│   ├── ProcessingInstruction
│   ├── DocType
│   └── Element (核心容器节点)
│       └── 包含 Attribute 哈希表 + children 数组
├── XMLDecl (继承 ProcessingInstruction)
└── Document (根节点，容纳所有顶层节点)
```

`Element` 是最核心的容器：
- `attributes` 存储 `Attribute` 对象，支持 `[]`、`[]=`、`add_attribute`、`delete_attribute`
- `children` 存储子节点数组，支持 `add`、`delete`、`each_element`
- `text` 方法提取所有文本子节点拼接值
- `namespaces` 方法自动解析 `xmlns` 和 `xmlns:prefix` 属性

#### 4. XPath 引擎

实现为简化但功能完整的 XPath 子集：

- 支持 `/root/person/name` 路径导航
- 支持 `*` 通配符匹配任意元素
- 支持 `..` 父节点轴
- 支持 `[n]` 位置谓词（1-based）
- 支持 `[@attr]` 存在性谓词
- 支持 `[@attr='value']` 等值谓词

核心算法：`match_step` 逐层过滤候选节点，`apply_predicate` 应用谓词筛选。

#### 5. Formatters（序列化）

`Formatters::Default` 负责 DOM → XML 字符串：

- 自动判断元素是否只包含文本节点，若是则内联输出不换行
- 混合内容（子元素 + 文本）自动缩进
- 转义规则：`&` → `&amp;`，`<` → `&lt;`，`>` → `&gt;`，`"` → `&quot;`

#### 6. 设计取舍

- **Tokenizer 使用正则与字符串扫描** 而非原版复杂的 `Source` 类，实现更简洁，但大文件流式读取性能略逊。
- **XPath 使用朴素递归过滤** 而非原版编译为内部指令集，实现简单但复杂查询性能较低。
- **格式化输出基于递归判断** 是否仅含文本节点，与原版 `Formatters::Pretty` 的 `write` 策略一致。
- **Node 不提供 `previous_sibling`/`next_sibling` 的缓存优化**，每次通过父节点的 `children` 数组查找，符合大多数使用场景。

未实现的部分（原版 REXML 的高级功能）：

- **PullParser / SAX 流式解析**：原版提供基于事件的流式解析，本版仅提供树形 DOM 解析。
- **DTD 内部子集解析**：如 `<!ENTITY>`、`<!ATTLIST>` 等声明未展开；仅支持外部声明行读取，忽略内部实体定义。
- **完整的 XPath 1.0**：未实现 `descendant-or-self::`、函数调用（除 `contains` 占位外）、复杂轴、`or/and` 逻辑谓词、字符串处理函数等。
- **UTF-16 / ISO-2022-JP 编码处理**：简化假设输入为 UTF-8 或系统兼容编码；XML 声明中的 encoding 字段仅读取不执行转码。
- **XML 命名空间前缀重写**：保留前缀但不验证 URI 一致性；不自动为元素添加默认命名空间声明。
- **实体声明外部解析**：不支持 SYSTEM 公共标识符指向的外部 DTD 实体；不解析参数实体。
- **XML 命名空间默认声明**：不支持 `xmlns="..."` 对无前缀元素的自动命名空间绑定。
- **CDATA 区块内的 `]]>` 拆分**：标准允许将 `]]>` 拆分为两个相邻 CDATA 节点，本版未实现。
- **ProcessingInstruction 目标名大小写敏感**：按原样保留，不做规范化处理。
- **文档片段（DocumentFragment）**：未提供 `REXML::DocumentFragment` 等价类。
- **XML 编码声明的自动检测**：不扫描 BOM 头，不根据前几个字节推断编码。
- **XML 规范化（C14N）**：未提供Canonical XML输出模式。
- **XML 数字签名相关**：不涉及 `Signature`、`SignedInfo` 等元素的特化处理。

功能对照表：

| 功能 | 原版 REXML | 本 XmlUtils | 状态 |
|------|-----------|-------------|------|
| `REXML::Document.new(string)` | ✅ | `XmlUtils.parse(source)` | 等价 |
| `doc.root` | ✅ | ✅ | 完全兼容 |
| `element['attr']` | ✅ | ✅ | 完全兼容 |
| `element.add_text` | ✅ | ✅ | 完全兼容 |
| `element.each_element` | ✅ | ✅ | 完全兼容 |
| `XPath.match` | ✅ | ✅ | 支持路径+谓词 |
| `XPath.first` | ✅ | ✅ | 完全兼容 |
| `Formatters::Pretty` | ✅ | ✅ | 简化实现 |
| `Parsers::PullParser` | ✅ | ❌ | 未实现（本版专注 TreeParser） |
| `Validation` | ✅ | ❌ | 未实现 |
| `StreamListener` (SAX) | ✅ | ❌ | 未实现 |
| `DTD` 完整解析 | ✅ | ⚠️ | 仅支持声明行，忽略内部实体定义 |

#### 7. xml_doc 移植问题

`lib/xmlutils/xml_doc.rb` 在适配原版 IMDOC/XMLUtils 的过程中，发现并修复了以下问题：

已修复问题：

| 问题 | 严重度 | 说明 |
|------|--------|------|
| `to_xml` 未转义属性和文本内容 | **高** | 原始实现直接拼接 `@attributes` 值到 XML 字符串，若值含 `<`、`&` 或 `"` 会生成非法 XML。已新增 `escape_xml` 和 `escape_xml_attr` 方法。 |
| `make_xml_from` 转义顺序错误 | **高** | 原始实现用数组 `zip` + `gsub!` 按 `['&','<','>',"'",'"']` 顺序替换，导致 `&` 先被替换为 `&amp;`，后续 `&lt;` 等被错误二次转义为 `&amp;lt;`。已改为 `gsub` 链式调用，顺序修正为 `&` → `&amp;`。 |
| `load` 使用 `open(filepath)` | 中 | `Kernel#open` 在 Ruby 3.x 中已被限制，可能调用 URI 解析而非本地文件读取。已改为 `File.read(filepath)`。 |
| `make_xml_from` / `make_str_from` 使用 `gsub!` | 中 | `gsub!` 直接修改传入字符串，产生副作用。已改为 `dup` + `gsub` 或 `gsub` 非破坏性调用。 |
| `self.copy` 浅拷贝属性 | 中 | `attributes: node.attributes` 是引用传递，修改副本属性会影响原节点。已改为 `node.attributes.dup`。 |
| `delete_elements` 空 block 时未定义变量 | 中 | 当未传入 block 时 `elems` 未定义，后续 `elems.each` 抛出 `NameError`。已加 `return [] unless block`。 |
| `pretty` 缺少非法 method 分支 | 低 | 传入 `:xml` 或 `:json` 以外的 method 会静默返回 `nil`。已加 `raise ArgumentError`。 |
| `to_xml` 字符串子元素未转义 | 中 | `@elements` 中若为 `String` 实例直接拼接，未做 XML 转义。已加 `XmlNode.escape_xml(e)`。 |

未修复的设计层面问题：

| 问题 | 说明 |
|------|------|
| `@prev` 语义混乱 | 构造函数将父节点放入 `@prev` 数组，但 `prev` 通常表示「前一个兄弟节点」。这导致双向链表遍历逻辑可能不符合预期。 |
| `to_obj` 同名覆盖 | 若两个子元素同名，`Hash#merge!` 会覆盖，只能保留最后一个。如需保留全部同名子元素，建议改用数组结构。 |
| `add_content` 与 `modify_content` 语义不一致 | `add_content` 追加到 `@elements` 数组；`modify_content` 先清空所有 `XmlNode` 子元素再添加。混合使用可能导致非文本子元素被意外删除。 |
| `pretty` 的 `indent` 参数失效 | 原 `REXML::Document.write(output, indent)` 支持自定义缩进宽度。`XmlUtils::Formatters::Default` 当前硬编码为 2 空格，`indent` 参数仅保留接口兼容，实际未生效。 |

### 使用示例

#### 1. 打包 和 测试

```bash
gem build manticore.gemspec
gem install --local manticore-smash-3.0.0.gem
```

测试脚本覆盖以下场景：

1. 基本 XML 解析（多层嵌套元素）
2. XPath 查询（路径导航、位置谓词、属性筛选）
3. CDATA 与注释处理
4. 空元素与属性读写
5. 序列化与反序列化 round-trip
6. 程序化 DOM 构建
7. XML 声明与 DOCTYPE 解析

运行方式：
```bash
ruby -I lib test/xmlutils_test.rb
```

#### 2. DOM节点 和 XPath

```ruby
require 'manticore'

# 解析 XML
xml = <<-XML
<?xml version="1.0"?>
<root>
  <person id="1">
    <name>Alice</name>
  </person>
</root>
XML

doc = XmlUtils.parse(xml)

# XPath 查询
person = XmlUtils::XPath.first(doc.root, 'person')
name   = XmlUtils::XPath.first(doc.root, 'person/name').text
puts name  # => "Alice"

# 构造文档
doc2 = XmlUtils.new_document
root = XmlUtils::Element.new('catalog')
doc2.add(root)
item = XmlUtils::Element.new('item')
item['id'] = '99'
item.add_text('Widget')
root.add(item)

puts XmlUtils.to_xml_string(doc2)
# => <catalog>
#      <item id="99">Widget</item>
#    </catalog>
```

#### 3. 模型转换兼容层

`xml_doc.rb` 提供 `XmlNode` 自定义树结构，适合需要更灵活遍历或双向链表关系的场景。内部使用 `XmlUtils` 解析，然后递归转换为 `XmlNode`：

```ruby
require 'manticore'

node = XmlParser.parse('<root><a>1</a><b id="2">text</b></root>')
puts node.to_xml #=> <root><a>1</a><b id="2">text</b></root>

# 格式化输出
puts node.pretty(:to_xml, :xml)

# 三元组 / 对象 / JSON 转换
p node.to_triad, node.to_obj
```

---

## XlsxKit — 纯 Ruby XLSX 读取器（零第三方依赖）

`xlsxkit` 是 XLSX（Office Open XML Spreadsheet）读取组件，提供流式读取与多格式输出，不依赖 rubyzip、roo、creek 等第三方 gem。

### 设计目标

- **零依赖**：纯 Ruby 实现 ZIP32 解包 + SAX 流式 XML 解析，无需安装任何 gem。
- **流式读取**：SAX 风格逐行处理，内存占用恒定，适合大文件（>100MB）。
- **多格式输出**：原生 Ruby 二维数组、JSON 字符串/文件、CSV 字符串/文件。
- **稀疏单元格补齐**：根据 `r` 属性（如 `A1`、`C1`）自动补齐缺失列为 `nil`。

### 文件结构

```
lib/
├── xlsxkit/
│   ├── zip_reader.rb          # 纯 Ruby ZIP32 读取器（DEFLATE / STORED）
│   ├── sax_parser.rb          # SAX 流式 XML 解析器（增量缓冲，64KB 块读取）
│   └── workbook.rb            # Workbook 高层 API（read_rows / to_a / to_json / to_csv）
├── test/
│   └── xlsxkit_test.rb        # 测试套件（15 用例，含 XLSX 生成辅助方法）
└── manticore.rb               # 统一入口，require 'manticore' 自动加载
```

### 架构原理

```
XLSX 文件（ZIP 容器）
    │
    ▼
┌─────────────────┐
│  ZipReader       │  ← 按需读取单个 ZIP 条目，不全量解包
│  (ZIP32 读取器)  │     支持 DEFLATE (method 8) 与 STORED (method 0)
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  SAXParser       │  ← 流式 XML 解析，增量缓冲，不构建 DOM 树
│  (SAX 解析器)    │     64KB 块读取，内存占用恒定
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  Workbook        │  ← 高层 API：Sheet 选择、Shared Strings 缓存
│  (工作簿 API)    │     行回调 → 数组 / JSON / CSV 输出
└─────────────────┘
```

### 核心实现要点

#### 1. ZipReader（ZIP32 读取器）

- 从文件末尾反向搜索 EOCD（End of Central Directory）签名，定位中央目录。
- 解析中央目录条目，获取每个文件的元数据（压缩方式、大小、Local Header 偏移）。
- 按需读取单个条目：定位 Local Header → 跳过头部 → Zlib::Inflate 解压。
- 与全量解包不同，仅按 name 读取所需条目，避免将整个 ZIP 展开到内存或磁盘。

#### 2. SAXParser（流式 XML 解析器）

- 基于增量缓冲的 SAX 解析器，不构建完整 DOM 树。
- 64KB 块读取，逐标签回调 `start_element` / `characters` / `end_element`。
- 支持标签属性解析、自闭合标签、CDATA 区段、实体引用展开。
- 内存占用恒定，适合大 XML 文件（如 >50MB 的 sheet 数据）。

#### 3. Workbook（高层 API）

- **Sheet 解析**：从 `xl/workbook.xml` 提取 sheet 名称列表，通过 `xl/_rels/workbook.xml.rels` 映射 rId → 文件路径。
- **Shared Strings 缓存**：首次访问时加载 `xl/sharedStrings.xml`，后续复用。
- **行处理**：SAX 回调驱动，每行输出为一个数组。根据单元格引用（`r` 属性如 `A1`、`C1`）自动补齐缺失列为 `nil`。
- **数据类型**：支持 shared string（`t="s"`）、inline string（`t="inlineStr"`）、boolean（`t="b"`）、error（`t="e"`）、formula string（`t="str"`）、数值（默认）。

### 使用示例

#### 基础读取

```ruby
require 'manticore'

wb = XlsxKit::Workbook.open('data.xlsx')

# 获取所有 sheet 名称
puts wb.sheet_names  # => ["Sheet1", "Sheet2"]

# 流式逐行读取
wb.read_rows('Sheet1') do |row|
  puts row.inspect  # => ["Alice", 30, nil, "alice@example.com"]
end

# 读取全部到数组
rows = wb.to_a('Sheet1')  # => [["Name", "Age"], ["Alice", 30], ...]
```

#### JSON / CSV 输出

```ruby
wb = XlsxKit::Workbook.open('data.xlsx')

# JSON 字符串
json = wb.to_json('Sheet1', pretty: true)

# JSON 文件
wb.to_json_file('output.json', 'Sheet1')

# CSV 字符串
csv = wb.to_csv('Sheet1')

# CSV 文件（流式写入，适合大数据量）
wb.to_csv_file('output.csv', 'Sheet1')
```

#### Headers 模式（首行作为表头）

```ruby
wb = XlsxKit::Workbook.open('data.xlsx')

# read_rows + headers: 每行返回 Hash
wb.read_rows(0, headers: true) do |row|
  puts row  # => {"Name"=>"Alice", "Age"=>30}
end

# to_a + headers: 返回 Hash 数组
data = wb.to_a(0, headers: true)  # => [{"Name"=>"Alice", "Age"=>30}, ...]

# to_json + headers: 输出 JSON 对象数组
json = wb.to_json(0, headers: true)
# => [{"Name":"Alice","Age":30}, {"Name":"Bob","Age":25}]
```

#### Sheet 选择

```ruby
wb = XlsxKit::Workbook.open('data.xlsx')

# 按名称选择
wb.read_rows('Sheet2') { |row| ... }

# 按序号选择（0-based）
wb.read_rows(1) { |row| ... }  # 第二个 sheet

# 默认选择第一个 sheet
wb.read_rows { |row| ... }
```

### 测试

```bash
ruby -I lib test/xlsxkit_test.rb
```

测试套件覆盖 15 个用例：

1. 基础读取（字符串、数值）
2. 多 sheet 选择（按名称、按序号）
3. 共享字符串与内联字符串
4. 布尔值与错误值
5. 特殊字符（引号、换行、Unicode）
6. 稀疏单元格（空列补 nil）
7. Headers 模式
8. JSON / CSV 输出
9. 大文件流式读取

---

## ReDiscount Markdown 解析器（rdiscount API 兼容层）

`mdutils/rediscount` 是 Markdown 处理组件，提供 Markdown → HTML 文档解析转换，完全兼容 `rdiscount` Gem 的 API 接口，无需编译 C 扩展即可在任何 Ruby 3.0+ 环境中运行。

### 设计目标

- **零原生依赖**：摆脱 `rdiscount` 对 C 库 `libmarkdown` 的编译依赖，解决 Windows / 跨平台部署难题。
- **API 平替**：构造函数、标志位、方法名与 `RDiscount` 逐一对齐，现有项目只需 `s/RDiscount/ReDiscount/` 即可迁移。
- **功能对齐**：覆盖 `rdiscount` 的核心扩展特性（表格、脚注、目录、SmartyPants 等），并保留 BlueCloth 兼容别名。

### 文件结构

```
lib/
├── mdutils/
│   └── rediscount.rb          # 纯 Ruby Markdown 解析器（ReDiscount + MarkdownParser）
├── test/
│   └── mdutils_test.rb        # 与原生 rdiscount 的对比测试套件
└── manticore.rb               # 统一入口，require 'manticore' 自动加载
```

---

### 核心实现要点

#### 1. 双层架构

```
┌─────────────────┐
│   ReDiscount    │  ← 公共 API：标志管理、入口方法 to_html / toc_content
│   (接口类)       │
└─────────────────┘
         │
         ▼
┌─────────────────┐
│ MarkdownParser  │  ← 内部实现：分块 → 渲染 → 后处理
│   (解析引擎)    │
└─────────────────┘
```

- **ReDiscount** 负责接收原始 Markdown 文本与开关标志，提供 `to_html`、`toc_content` 及所有 `attr_accessor` 标志位。
- **MarkdownParser** 为内部无状态解析引擎，执行「预处理 → 块级分块 → 内联渲染 → 后处理」四阶段流水线。

#### 2. 预处理阶段

1. **换行标准化**：统一 `\r\n`、`\r` 为 `\n`。
2. **引用定义提取**：识别 `[^id]: url "title"` 形式的引用链接与脚注定义，从正文中剥离并建立查找表。
3. **脚注多行合并**：支持缩进续行的脚注内容收集。

#### 3. 块级解析（Block-level）

扫描器按优先级逐行识别以下块类型：

| 块类型 | 识别规则 | 说明 |
|--------|----------|------|
| 水平线 (`:hr`) | `^*{3,}` / `^-{3,}` / `^_{3,}` | 标准分隔线 |
| ATX 标题 (`:header`) | `^#{1,6}\s+...` | 1–6 级标题 |
| Setext 标题 (`:header`) | 下划线 `====` / `----` | 1–2 级标题 |
| 围栏代码 (`:code`) | \`\`\`lang … \`\`\` | GFM 风格代码块 |
| 缩进代码 (`:code`) | `^    ` 或 `^\t` | 经典 4 空格/Tab 缩进 |
| 引用块 (`:blockquote`) | `^>\s?...` | 支持嵌套 |
| 表格 (`:table`) | `\|...\|` + `\|:-:\|` | GFM / Discount 扩展 |
| 定义列表 (`:deflist`) | term + `^:\s+def` | Discount 扩展 |
| 无序列表 (`:ul`) | `* ` / `+ ` / `- ` | 支持嵌套与多行项 |
| 有序列表 (`:ol`) | `1. ` / `1) ` | 数字序号 |
| 字母列表 (`:ol_alpha`) | `a. ` / `a) ` | 需 `:md1compat` 标志 |
| HTML 块 (`:html`) | `<div>` / `<table>` 等 | 保留原始标签 |
| 段落 (`:paragraph`) | 默认兜底 | 连续非空行 |

#### 4. 内联渲染（Inline）

处理顺序经过精心设计，避免嵌套冲突：

1. **代码片段保护** `` `code` `` → 占位符，防止后续正则误匹配。
2. **图片** `![alt](url =WxH)` → 支持 Discount 尺寸扩展。
3. **链接** `[text](url "title")` 与引用链接 `[text][ref]`。
4. **自动链接** `<https://...>` / `<mail@...>`（需 `:autolink`）。
5. **删除线** `~~text~~` → `<del>`。
6. **上标** `^text^` → `<sup>`。
7. **强调** `**strong**` / `*em*` / `__strong__` / `_em_`。
8. **硬换行** 行尾两空格 → `<br />`。
9. **脚注引用** `[^id]` → 上标链接。
10. **恢复代码片段** 占位符还原为 `<code>`。

#### 5. 后处理阶段

- **Smartypants**（`:smart`）： `"..."` → `&ldquo;...&rdquo;`，`'...'` → `&lsquo;...&rsquo;`，`--` → `&mdash;`，`...` → `&hellip;`。
- **脚注列表生成**：在文档末尾追加 `<div class="footnotes">` 有序列表。
- **HTML 过滤**：`:filter_html`  strip 全部标签；`:filter_styles` 移除 `<style>` 块。

### 支持标志位（Flags）

构造函数支持通过 Symbol 列表一键开启：

```ruby
rd = ReDiscount.new(text, :smart, :footnotes, :autolink)
```

| 标志 | 说明 | 默认 |
|------|------|------|
| `:smart` | 智能引号与排版符号（SmartyPants） | false |
| `:filter_html` | 过滤所有 HTML 标签 | false |
| `:filter_styles` | 过滤 `<style>` 块 | false |
| `:footnotes` | 启用脚注 `[^id]` | false |
| `:generate_toc` | 生成目录并插入标题锚点 | false |
| `:no_image` | 禁用图片解析 | false |
| `:no_links` | 禁用链接解析 | false |
| `:no_tables` | 禁用表格解析 | false |
| `:strict` | 严格模式 | false |
| `:autolink` | 自动识别 URL 与邮箱链接 | false |
| `:safelink` | 安全链接（仅允许 http/https/ftp/news） | false |
| `:no_pseudo_protocols` | 禁用伪协议链接 | false |
| `:no_superscript` | 禁用上标 | false |
| `:no_strikethrough` | 禁用删除线 | false |
| `:latex` | LaTeX 支持占位 | false |
| `:explicitlist` | 显式列表（多行项不嵌套 `<p>`） | false |
| `:md1compat` | Markdown 1.0 兼容（字母列表等） | false |

### 使用示例

#### 基础用法

```ruby
require 'mdutils/rediscount'

markdown = ReDiscount.new("Hello **World**!")
puts markdown.to_html
# => <p>Hello <strong>World</strong>!</p>
```

#### 生成目录

```ruby
text = <<~MD
  # 第一章
  ## 1.1 小节
  # 第二章
MD

rd = ReDiscount.new(text, :generate_toc)
puts rd.toc_content
# => <ul>...<a href="#第一章">第一章</a>...</ul>
puts rd.to_html
# => 标题自动附带 <a name="第一章"></a> 锚点
```

#### 表格与对齐

```ruby
text = <<~MD
  | 左对齐 | 居中 | 右对齐 |
  |:-------|:----:|-------:|
  | A      | B    | C      |
MD

puts ReDiscount.new(text).to_html
# => <table>...<th style="text-align:left;">...
```

#### 脚注

```ruby
text = <<~MD
  这是一个脚注示例[^1]。

  [^1]: 脚注内容支持多行
      续行缩进。
MD

puts ReDiscount.new(text, :footnotes).to_html
# => <sup><a href="#fn1" id="ref1">1</a></sup>
# => <div class="footnotes">...</div>
```

#### BlueCloth 兼容

```ruby
require 'mdutils/rediscount'
# BlueCloth 自动别名为 ReDiscount
markdown = BlueCloth.new("Hello World!")
puts markdown.to_html
```

### 与原生 rdiscount 的差异

本实现以「最大兼容」为目标，但纯 Ruby 解析与 C 扩展在边界处理上仍有细微差异，测试套件中已标记为已知差异（`assert_differs_from_rdiscount`）：

| 差异点 | 说明 |
|--------|------|
| 引用块空白 | 嵌套引用块的内部 `<p>` 剥离策略与 `rdiscount` 不同，导致空白字符差异。 |
| 上标尾部 `^` | `x^2^` 中 `rdiscount` 会残留尾部 `^`，本实现完全移除。 |
| 相邻列表合并 | `rdiscount` 会将相邻同类型列表合并为一个 `<ul>`；本实现保持独立列表。 |
| `filter_html` 段落 | 当 HTML 块位于顶部时，`rdiscount` 会保留空 `<p></p>`，本实现可能将其一并过滤。 |
| `explicitlist` 多行项 | 多行列表项的换行与 `<p>` 嵌套策略不同。 |

> 注：以上差异不影响语义正确性，仅影响 HTML 空白与标签嵌套细节。常规文档（段落、标题、列表、表格、链接、图片、代码块）的输出与 `rdiscount` 完全一致。

### 测试

测试脚本与原生 `rdiscount` 进行交叉比对，覆盖块级元素、内联元素、扩展语法与全部标志位：

```bash
ruby -I lib test/mdutils_test.rb
```

运行时会自动检测系统中是否安装了原生 `rdiscount` Gem：
- 若已安装，则执行输出对比，标记已知差异。
- 若未安装，则跳过比对测试，仅运行纯 Ruby 断言。

---
