import XCTest
@testable import CatboardCore

final class FileReaderTests: XCTestCase {

    // MARK: - Helper

    private func makeTempFile(
        name: String = UUID().uuidString,
        extension ext: String = "txt",
        contents: Data
    ) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
        FileManager.default.createFile(atPath: url.path, contents: contents)
        return url
    }

    // MARK: - Fix 2: Happy path

    func testReadsValidTextFile() throws {
        let url = makeTempFile(contents: "Hello, world!".data(using: .utf8)!)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertEqual(result, "Hello, world!")
    }

    // MARK: - Fix 1: Encoding detection

    func testReadsUTF16LEWithBOM() throws {
        var data = Data([0xFF, 0xFE]) // BOM
        data.append("Hello".data(using: .utf16LittleEndian)!)
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertEqual(result, "Hello")
    }

    func testReadsUTF16BEWithBOM() throws {
        var data = Data([0xFE, 0xFF]) // BOM
        data.append("Hello".data(using: .utf16BigEndian)!)
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertEqual(result, "Hello")
    }

    func testReadsUTF32LEWithBOM() throws {
        // Swift's .utf32LittleEndian encoding may include its own BOM in the data.
        let encoded = "Hi".data(using: .utf32LittleEndian)!
        var data: Data
        if encoded.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            data = encoded
        } else {
            data = Data([0xFF, 0xFE, 0x00, 0x00])
            data.append(encoded)
        }
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertEqual(result, "Hi")
    }

    func testReadsUTF32BEWithBOM() throws {
        let encoded = "Hi".data(using: .utf32BigEndian)!
        var data: Data
        if encoded.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            data = encoded
        } else {
            data = Data([0x00, 0x00, 0xFE, 0xFF])
            data.append(encoded)
        }
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertEqual(result, "Hi")
    }

    func testReadsUTF16WithoutBOM() throws {
        // UTF-16LE without BOM — null bytes trigger isBinary, then UTF-16 fallback
        let data = "Test".data(using: .utf16LittleEndian)!
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertEqual(result, "Test")
    }

    func testReadsISOLatin1Fallback() throws {
        // 0xE9 is 'é' in ISO-Latin-1, but an incomplete UTF-8 leading byte
        let data = Data([0xE9])
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FileReader.readContents(of: url)
        XCTAssertTrue(result.contains("é"))
    }

    func testRejectsBinaryFile() throws {
        // Bytes that trigger binary detection (contain nulls) and fail both
        // UTF-16 decodings. 0xD8D8 is a lone high surrogate (U+D8D8 falls in
        // the surrogate range 0xD800-0xDFFF) which is invalid in both LE and BE
        // interpretations. The trailing 0x00 provides the required null byte.
        let data = Data([0xD8, 0xD8, 0x00])
        let url = makeTempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.binaryFile = error else {
                XCTFail("Expected binaryFile error, got \(error)")
                return
            }
        }
    }

    // MARK: - Fix 3: File too large

    func testRejectsFileTooLarge() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: url) }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let fh = try FileHandle(forWritingTo: url)
        fh.truncateFile(atOffset: 51 * 1024 * 1024)
        fh.closeFile()

        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge error, got \(error)")
                return
            }
        }
    }
}
