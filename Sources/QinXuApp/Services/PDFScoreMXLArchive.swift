import Foundation
import zlib

/// Packages already-produced MusicXML without changing its musical data.
/// The first, uncompressed `mimetype` entry follows the MusicXML container spec.
/// Optical accuracy and supported musical constructs remain the caller's checks.
enum PDFScoreMXLArchive {
    static func make(musicXML: Data) throws -> Data {
        guard !musicXML.isEmpty, musicXML.count <= CompressedMusicXML.maximumXMLBytes else {
            throw CompressedMusicXML.ImportError.invalid("识别曲谱为空或超过 5 MB，无法导出。")
        }
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container><rootfiles><rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/></rootfiles></container>
        """
        let entries: [(name: String, bytes: Data)] = [
            ("mimetype", Data("application/vnd.recordare.musicxml".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("score.musicxml", musicXML),
        ]
        var output = Data(), directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            // All lengths and offsets fit UInt32 because the whole archive is
            // bounded below the existing import limit (20 MB), well below ZIP64.
            let size = UInt32(entry.bytes.count), offset = UInt32(output.count)
            let checksum = entry.bytes.withUnsafeBytes { buffer in
                UInt32(truncatingIfNeeded: crc32(0, buffer.bindMemory(to: UInt8.self).baseAddress, uInt(buffer.count)))
            }
            output.appendUInt32(0x04034b50)
            output.appendUInt16(20) // Version needed: ZIP 2.0.
            output.appendUInt16(0x0800) // UTF-8 names; no encryption or descriptor.
            output.appendUInt16(0) // Stored, without compression.
            output.appendUInt16(0) // Fixed DOS time/date; no user metadata.
            output.appendUInt16(0x0021) // 1980-01-01, the ZIP epoch.
            output.appendUInt32(checksum)
            output.appendUInt32(size)
            output.appendUInt32(size)
            output.appendUInt16(UInt16(name.count))
            output.appendUInt16(0) // No extra field, including for mimetype.
            output.append(name)
            output.append(entry.bytes)

            directory.appendUInt32(0x02014b50)
            directory.appendUInt16(20) // Version made by: DOS, ZIP 2.0.
            directory.appendUInt16(20)
            directory.appendUInt16(0x0800)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0x0021)
            directory.appendUInt32(checksum)
            directory.appendUInt32(size)
            directory.appendUInt32(size)
            directory.appendUInt16(UInt16(name.count))
            directory.appendUInt16(0) // Extra length.
            directory.appendUInt16(0) // Comment length.
            directory.appendUInt16(0) // Disk number.
            directory.appendUInt16(0) // Internal attributes.
            directory.appendUInt32(0) // External attributes; no symbolic links.
            directory.appendUInt32(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(output.count)
        output.append(directory)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0) // Single disk.
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(directory.count))
        output.appendUInt32(directoryOffset)
        output.appendUInt16(0) // No archive comment.
        guard output.count <= CompressedMusicXML.maximumArchiveBytes else {
            throw CompressedMusicXML.ImportError.invalid("识别曲谱封装后超过 20 MB，无法导出。")
        }
        return output
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(truncatingIfNeeded: value))
        appendUInt16(UInt16(truncatingIfNeeded: value >> 16))
    }
}
