import XCTest
@testable import CatboardCore

final class CatboardCoreTests: XCTestCase {

    // MARK: - FileReader Tests

    func testRejectsNetworkURL() {
        let url = URL(string: "https://example.com/file.txt")!
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.notFileURL = error else {
                XCTFail("Expected notFileURL error, got \(error)")
                return
            }
        }
    }

    func testRejectsNonexistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/to/file.txt")
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }

    func testRejectsDirectory() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.isDirectory = error else {
                XCTFail("Expected isDirectory error, got \(error)")
                return
            }
        }
    }

    // MARK: - CatboardError Tests

    func testErrorDescriptions() {
        let url = URL(fileURLWithPath: "/test/file.txt")

        XCTAssertNotNil(CatboardError.fileNotFound(url).errorDescription)
        XCTAssertNotNil(CatboardError.permissionDenied(url).errorDescription)
        XCTAssertNotNil(CatboardError.binaryFile(url).errorDescription)
        XCTAssertNotNil(CatboardError.fileTooLarge(url, 100_000_000).errorDescription)
        XCTAssertNotNil(CatboardError.outputTooLarge(200_000_000).errorDescription)
        XCTAssertNotNil(CatboardError.imageTooLarge(url, 10000, 10000).errorDescription)
        XCTAssertNotNil(CatboardError.isDirectory(url).errorDescription)
        XCTAssertNotNil(CatboardError.notFileURL(url).errorDescription)
        XCTAssertNotNil(CatboardError.extractionFailed(url, "Test error").errorDescription)
        XCTAssertNotNil(CatboardError.ocrTimeout(url).errorDescription)
    }

    // MARK: - Clipboard Tests

    func testClipboardCopyAndRetrieve() {
        let testString = "Test clipboard content \(UUID().uuidString)"
        let expectation = self.expectation(description: "Copy completion")

        Clipboard.copy(testString) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify content was copied
        let retrieved = Clipboard.getText()
        XCTAssertEqual(retrieved, testString)
    }
}
