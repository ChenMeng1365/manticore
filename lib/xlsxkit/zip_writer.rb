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

require 'zlib'

module XlsxKit
  ##
  # 最小化 ZIP32 写入器，专为 XLSX 打包设计。
  #
  # 与 ZipReader 对应，不依赖 rubyzip，仅支持写入 XLSX 所需的两种压缩方式：
  #   - DEFLATE (method 8): 通用压缩
  #   - STORED  (method 0):  无压缩
  #
  # 实现思路：
  #   1. add_entry 时即时写出 Local File Header + 数据，并记录偏移
  #   2. 同时在内存累积 Central Directory 记录
  #   3. close 时写出 Central Directory + EOCD 收尾
  #
  # 边写边压，避免将整个 ZIP 缓冲在内存或磁盘。

  class ZipWriter
    # ZIP 格式签名
    LOCAL_SIG   = "PK\x03\x04".b.freeze   # Local File Header
    CDENTRY_SIG = "PK\x01\x02".b.freeze   # Central Directory File Header
    EOCD_SIG    = "PK\x05\x06".b.freeze   # End of Central Directory

    # 压缩方法
    STORED  = 0
    DEFLATE = 8

    ##
    # 初始化写入器。
    #
    # @param io [IO] 可写 IO（必须已以二进制模式打开）
    def initialize(io)
      @io      = io
      @offset  = 0          # 当前数据起始偏移（用于 Central Directory 定位）
      @count   = 0          # 条目数
      @central = ''.b       # 中央目录累积缓冲
    end

    ##
    # 便捷类方法：写入文件路径，块结束后自动收尾并关闭。
    def self.open(path)
      File.open(path, 'wb') do |f|
        writer = new(f)
        yield writer
        writer.close
      end
    end

    ##
    # 添加一个条目（文件），立即写出数据。
    #
    # @param name [String] 条目名（如 "xl/worksheets/sheet1.xml"）
    # @param data [String] 内容（UTF-8 字符串或二进制）
    # @param method [Integer] 压缩方式（DEFLATE / STORED）
    def add_entry(name, data, method: DEFLATE)
      name_bytes = name.b
      data_bytes = data.b
      crc = Zlib.crc32(data_bytes)

      compressed =
        case method
        when STORED  then data_bytes
        when DEFLATE then Zlib::Deflate.new(nil, -Zlib::MAX_WBITS).deflate(data_bytes, Zlib::FINISH)
        else raise ArgumentError, "unsupported compression method: #{method}"
        end

      # Local File Header (30 bytes + name + data)
      local = LOCAL_SIG.dup
      local << [20, 0, method, 0, 0, crc,
                compressed.bytesize, data_bytes.bytesize,
                name_bytes.bytesize, 0].pack('vvvvvVVVvv')
      local << name_bytes
      local << compressed
      @io.write(local)

      # Central Directory Record (46 bytes + name)
      cd = CDENTRY_SIG.dup
      cd << [20, 20, 0, method, 0, 0, crc,
             compressed.bytesize, data_bytes.bytesize,
             name_bytes.bytesize, 0, 0, 0, 0, 0, @offset].pack('vvvvvvVVVvvvvvVV')
      cd << name_bytes
      @central << cd

      @offset += local.bytesize
      @count += 1
      self
    end

    ##
    # 写出 Central Directory 与 EOCD，收尾 ZIP 文件。
    def close
      cd_offset = @offset
      @io.write(@central)

      eocd = EOCD_SIG.dup
      eocd << [0, 0, @count, @count, @central.bytesize, cd_offset, 0].pack('vvvvVVv')
      @io.write(eocd)
      @io
    end
  end
end
