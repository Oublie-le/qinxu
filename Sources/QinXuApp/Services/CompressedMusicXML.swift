import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import zlib

/// MXL only locates and decompresses the first declared MusicXML root. Musical
/// validation remains in QinXuCore.MusicXMLParser. No archive entry is written.
/// Container contract: https://www.w3.org/2021/06/musicxml40/tutorial/compressed-mxl-files/
enum CompressedMusicXML {
    static let maximumArchiveBytes = 20_000_000
    static let maximumXMLBytes = 5_000_000

    static func scoreData(from archive: Data) throws -> Data {
        let zip = try ZIP(archive)
        let manifest = try zip.extract("META-INF/container.xml", limit: 65_536)
        guard let text = String(data: manifest, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw ImportError.invalid("MXL 容器说明包含不支持的 XML 声明。")
        }
        let delegate = ContainerParser()
        let parser = XMLParser(data: manifest)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.firstRoot, ZIP.validPath(root.path),
              root.mediaType == nil || root.mediaType == "application/vnd.recordare.musicxml+xml" else {
            throw ImportError.invalid("MXL 未声明可读取的主 MusicXML 曲谱。")
        }
        if zip.entries["mimetype"] != nil {
            let mime = try zip.extract("mimetype", limit: 100)
            guard mime == Data("application/vnd.recordare.musicxml".utf8) else {
                throw ImportError.invalid("MXL 的文件类型声明不正确。")
            }
        }
        return try zip.extract(root.path, limit: maximumXMLBytes)
    }

    enum ImportError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }

    private final class ContainerParser: NSObject, XMLParserDelegate {
        var stack: [String] = []
        var firstRoot: (path: String, mediaType: String?)?
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            stack.append(elementName)
            guard stack.count <= 8 else { parser.abortParsing(); return }
            if stack == ["container", "rootfiles", "rootfile"], firstRoot == nil {
                guard let path = attributeDict["full-path"] else { parser.abortParsing(); return }
                firstRoot = (path, attributeDict["media-type"])
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if !stack.isEmpty { stack.removeLast() }
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
    }

    private struct Entry {
        let path: String
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
    }

    private struct ZIP {
        let bytes: [UInt8]
        let centralOffset: Int
        let entries: [String: Entry]

        init(_ data: Data) throws {
            guard data.count >= 22, data.count <= maximumArchiveBytes else {
                throw ImportError.invalid("MXL 文件为空、损坏或超过 20 MB。")
            }
            let bytes = [UInt8](data)
            func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
            func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
            let lower = max(0, bytes.count - 65_557)
            let end = stride(from: bytes.count - 22, through: lower, by: -1).first {
                u32($0) == 0x06054b50 && $0 + 22 + Int(u16($0 + 20)) == bytes.count
            }
            guard let end, u16(end + 4) == 0, u16(end + 6) == 0,
                  u16(end + 8) == u16(end + 10), (1...512).contains(Int(u16(end + 10))) else {
                throw ImportError.invalid("MXL 压缩目录无效；不支持分卷或 ZIP64。")
            }
            let offset = Int(u32(end + 16)), size = Int(u32(end + 12))
            guard offset <= end, size == end - offset else {
                throw ImportError.invalid("MXL 压缩目录位置无效。")
            }
            var found: [String: Entry] = [:]
            var cursor = offset, expandedTotal = 0
            for _ in 0..<Int(u16(end + 10)) {
                guard cursor <= end - 46, u32(cursor) == 0x02014b50 else {
                    throw ImportError.invalid("MXL 压缩目录不完整。")
                }
                let flags = u16(cursor + 8), method = u16(cursor + 10)
                let nameLength = Int(u16(cursor + 28)), extraLength = Int(u16(cursor + 30)), commentLength = Int(u16(cursor + 32))
                let length = 46 + nameLength + extraLength + commentLength
                guard nameLength > 0, nameLength <= 1_024, length <= end - cursor,
                      flags & 0x0041 == 0, method == 0 || method == 8, u16(cursor + 34) == 0,
                      ((u32(cursor + 38) >> 16) & 0xf000) != 0xa000,
                      let path = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                      Self.validPath(path), found[path] == nil else {
                    throw ImportError.invalid("MXL 含加密、重复路径、链接或不支持的压缩条目。")
                }
                let compressed = Int(u32(cursor + 20)), expanded = Int(u32(cursor + 24)), localOffset = Int(u32(cursor + 42))
                guard compressed <= maximumArchiveBytes, expanded <= 64_000_000,
                      localOffset < offset else { throw ImportError.invalid("MXL 条目尺寸或位置超出限制。") }
                expandedTotal += expanded
                guard expandedTotal <= 64_000_000 else { throw ImportError.invalid("MXL 解压后的总量超过限制。") }
                found[path] = Entry(path: path, flags: flags, method: method, crc: u32(cursor + 16),
                                    compressed: compressed, expanded: expanded, offset: localOffset)
                cursor += length
            }
            guard cursor == end else { throw ImportError.invalid("MXL 压缩目录长度不一致。") }
            self.bytes = bytes; centralOffset = offset; entries = found
        }

        static func validPath(_ path: String) -> Bool {
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
                  !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
            let value = path.hasSuffix("/") ? String(path.dropLast()) : path
            return !value.isEmpty && value.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        }

        func extract(_ path: String, limit: Int) throws -> Data {
            guard let entry = entries[path], !path.hasSuffix("/"), entry.expanded <= limit,
                  entry.offset <= centralOffset - 30 else {
                throw ImportError.invalid("MXL 缺少必要文件，或主曲谱超过 5 MB。")
            }
            func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
            func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
            let i = entry.offset
            let nameLength = Int(u16(i + 26)), extraLength = Int(u16(i + 28))
            let payload = i + 30 + nameLength + extraLength
            guard u32(i) == 0x04034b50, u16(i + 6) == entry.flags, u16(i + 8) == entry.method,
                  payload <= centralOffset, entry.compressed <= centralOffset - payload,
                  String(bytes: bytes[(i + 30)..<(i + 30 + nameLength)], encoding: .utf8) == entry.path else {
                throw ImportError.invalid("MXL 文件头与压缩目录不一致。")
            }
            if entry.flags & 8 == 0 {
                guard u32(i + 14) == entry.crc, Int(u32(i + 18)) == entry.compressed,
                      Int(u32(i + 22)) == entry.expanded else { throw ImportError.invalid("MXL 文件头尺寸不一致。") }
            }
            let source = Array(bytes[payload..<(payload + entry.compressed)])
            let output: [UInt8]
            if entry.method == 0 {
                guard source.count == entry.expanded else { throw ImportError.invalid("MXL 存储条目长度错误。") }
                output = source
            } else {
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                    throw ImportError.invalid("无法初始化 MXL 解压。")
                }
                defer { inflateEnd(&stream) }
                var buffer = [UInt8](repeating: 0, count: entry.expanded + 1)
                let result = source.withUnsafeBufferPointer { input in
                    buffer.withUnsafeMutableBufferPointer { destination -> Int32 in
                        stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress)
                        stream.avail_in = uInt(input.count)
                        stream.next_out = destination.baseAddress
                        stream.avail_out = uInt(destination.count)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard result == Z_STREAM_END, stream.total_in == source.count,
                      stream.total_out == entry.expanded else { throw ImportError.invalid("MXL 解压失败或实际尺寸超出声明。") }
                output = Array(buffer.prefix(entry.expanded))
            }
            let checksum = output.withUnsafeBufferPointer { crc32(0, $0.baseAddress, uInt($0.count)) }
            guard UInt32(truncatingIfNeeded: checksum) == entry.crc else { throw ImportError.invalid("MXL 文件校验失败，内容可能已损坏。") }
            return Data(output)
        }
    }
}

enum StructuredScoreImport {
    static func xmlData(from url: URL) throws -> Data {
        let compressed = url.pathExtension.lowercased() == "mxl"
        let limit = compressed ? CompressedMusicXML.maximumArchiveBytes : CompressedMusicXML.maximumXMLBytes
        let data = try boundedData(from: url, limit: limit)
        return compressed ? try CompressedMusicXML.scoreData(from: data) : data
    }

    static func boundedData(from url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false, (values.fileSize ?? 0) <= limit else {
            throw CompressedMusicXML.ImportError.invalid("文件不是普通文件，或超过 \(limit / 1_000_000) MB 限制。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CompressedMusicXML.ImportError.invalid("文件超过 \(limit / 1_000_000) MB 限制。") }
        return data
    }
}
