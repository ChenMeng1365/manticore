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
├── test/
│   ├── xml_doc_test.rb      # xml_doc测试用例
│   └── xmlutils_test.rb     # xmlutils测试用例
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
gem install --local manticore-3.0.0.gem
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
