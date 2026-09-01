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
require 'zlib'

module XlsxKit
  ##
  # 最小化 ZIP32 读取器，专为 XLSX 解包设计。
  #
  # 不依赖 rubyzip 等第三方 gem，仅支持 XLSX 中出现的两种压缩方式：
  #   - DEFLATE (method 8): 通用压缩
  #   - STORED  (method 0):  无压缩
  #
  # 实现思路：
  #   1. 从文件末尾反向搜索 EOCD (End of Central Directory) 签名
  #   2. 解析中央目录，获取所有条目的元数据与 Local Header 偏移
  #   3. 按需读取单个条目：定位 Local Header → 跳过头部 → Zlib::Inflate 解压
  #
  # 与全量解包不同，本 reader 仅按 name 读取单个条目，避免将整个 ZIP 展开到内存或磁盘。

  class ZipReader
    # ZIP 格式签名（freeze 防止外部 << 修改）
    EOCD_SIG     = "PK\x05\x06".b.freeze   # End of Central Directory
    CDENTRY_SIG  = "PK\x01\x02".b.freeze   # Central Directory File Header
    LOCAL_SIG    = "PK\x03\x04".b.freeze   # Local File Header

    # 压缩方法
    STORED  = 0
    DEFLATE = 8

    attr_reader :entries

    ##
    # 初始化 ZIP 读取器。
    #
    # @param io [IO, String] 文件路径或已打开的 IO（必须可 seek）
    def initialize(io)
      @io = io.is_a?(String) ? File.open(io, 'rb') : io
      @entries = nil
    end

    ##
    # 便捷类方法：打开文件并读取后关闭。
    def self.open(path)
      reader = new(path)
      yield reader
    ensure
      reader&.close
    end

    ##
    # 关闭底层 IO（若由本类打开）。
    def close
      @io.close unless @io.closed?
    end

    ##
    # 解析中央目录，返回 {name => entry} 的 Hash。
    # entry 为包含 :name, :method, :compressed_size, :uncompressed_size, :local_offset 的 Hash。
    def entries
      return @entries if @entries

      offset = find_eocd
      @io.seek(offset)
      sig = @io.read(4)
      raise "EOCD signature not found" unless sig == EOCD_SIG

      _disk_num, _ent_disk, _ent_here, total_ent,
        _cd_size, cd_offset = @io.read(16).unpack('vvvvVV')

      @io.seek(cd_offset)
      @entries = {}

      total_ent.times do
        sig = @io.read(4)
        break unless sig == CDENTRY_SIG

        _ver_made, _ver_need, _flags, method,
          _mtime, _mdate, crc32, comp_size, uncomp_size,
          name_len, extra_len, comm_len,
          _disk, _iattr, _eattr, local_offset = @io.read(42).unpack('vvvvvvVVVvvvvvVV')

        name = @io.read(name_len).force_encoding('UTF-8')
        @io.read(extra_len + comm_len)  # 跳过 extra field 与 comment

        @entries[name] = {
          name: name,
          method: method,
          compressed_size: comp_size,
          uncompressed_size: uncomp_size,
          crc32: crc32,
          local_offset: local_offset
        }
      end

      @entries
    end

    ##
    # 读取指定条目的原始字节（已解压）。
    #
    # @param name [String] 条目名（如 "xl/sharedStrings.xml"）
    # @return [String, nil] 二进制内容；条目不存在时返回 nil
    def read_entry(name)
      entry = entries[name]
      return nil unless entry

      data_offset = resolve_data_offset(entry[:local_offset])
      @io.seek(data_offset)
      raw = @io.read(entry[:compressed_size])

      case entry[:method]
      when STORED
        raw
      when DEFLATE
        Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
      else
        raise "Unsupported compression method: #{entry[:method]}"
      end
    end

    ##
    # 读取指定条目并强制 UTF-8 编码（用于 XML 文本）。
    def read_entry_utf8(name)
      data = read_entry(name)
      return nil unless data
      data.force_encoding('UTF-8')
    end

    private

    ##
    # 从文件末尾反向搜索 EOCD 签名。
    # EOCD 最小 22 字节，最大 22 + 65535（comment 区段），从尾部向前扫。
    def find_eocd
      size = @io.size
      scan_size = [size, 65557].min  # 22 + 65535
      @io.seek(size - scan_size)
      tail = @io.read(scan_size)
      tail = tail.force_encoding('BINARY')

      pat = EOCD_SIG.b  # dup 避免修改 frozen 常量
      pos = tail.rindex(pat)
      raise "EOCD record not found — not a valid ZIP file" unless pos

      size - scan_size + pos
    end

    ##
    # 解析 Local File Header，返回实际数据起始偏移。
    def resolve_data_offset(local_offset)
      @io.seek(local_offset)
      sig = @io.read(4)
      raise "Local file header signature not found at #{local_offset}" unless sig == LOCAL_SIG

      _ver, _flags, _method, _mtime, _mdate,
        _crc, _comp, _uncomp, name_len, extra_len = @io.read(26).unpack('vvvvvVVVvv')

      local_offset + 30 + name_len + extra_len
    end
  end
end
