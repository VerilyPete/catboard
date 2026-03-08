import XCTest
import Quartz
import CoreText
@testable import CatboardCore

final class PDFExtractorTests: XCTestCase {

    // MARK: - Helpers

    private func tempURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    override func tearDown() {
        super.tearDown()
    }

    /// Create a PDF with selectable text using CoreText (CTFramesetter).
    private func createPDFWithText(_ text: String) -> URL {
        let url = tempURL(extension: "pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
            XCTFail("Could not create PDF context")
            return url
        }

        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)

        let attrString = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.black
            ]
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let path = CGPath(rect: pageRect.insetBy(dx: 50, dy: 50), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, context)

        context.endPage()
        context.closePDF()

        return url
    }

    /// Create a password-protected PDF.
    private func createLockedPDF() -> URL {
        let url = tempURL(extension: "pdf")

        // First create a normal PDF with a page
        let sourceURL = createPDFWithText("Locked content")
        guard let doc = PDFDocument(url: sourceURL) else {
            XCTFail("Could not open source PDF")
            return url
        }

        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: "secret",
            .ownerPasswordOption: "owner"
        ]

        doc.write(to: url, withOptions: options)
        try? FileManager.default.removeItem(at: sourceURL)

        return url
    }

    /// Create an empty PDF (no pages).
    private func createEmptyPDF() -> URL {
        let url = tempURL(extension: "pdf")
        let doc = PDFDocument()
        doc.write(to: url)
        return url
    }

    // MARK: - PDFExtractor Tests

    func testPDFExtractsEmbeddedText() throws {
        let knownText = "Hello Catboard PDF Test"
        let url = createPDFWithText(knownText)
        defer { try? FileManager.default.removeItem(at: url) }

        // Verify the PDF was created with selectable text
        let doc = PDFDocument(url: url)
        XCTAssertNotNil(doc, "PDF document should be loadable")
        let pageString = doc?.page(at: 0)?.string
        XCTAssertNotNil(pageString, "Page should have extractable text")

        let result = try PDFExtractor.extractText(from: url)
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), knownText)
    }

    func testPDFRejectsLockedPDF() {
        let url = createLockedPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try PDFExtractor.extractText(from: url)) { error in
            guard case CatboardError.extractionFailed = error else {
                XCTFail("Expected extractionFailed error, got \(error)")
                return
            }
        }
    }

    func testPDFRejectsEmptyPDF() {
        let url = createEmptyPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        // PDFDocument(url:) may return nil for an empty PDF, which triggers
        // "Could not open PDF" — or it may load with pageCount 0, which triggers
        // "PDF has no pages". Either is an extractionFailed error.
        XCTAssertThrowsError(try PDFExtractor.extractText(from: url)) { error in
            guard case CatboardError.extractionFailed = error else {
                XCTFail("Expected extractionFailed error, got \(error)")
                return
            }
        }
    }

    // MARK: - OCREngine PDF guard test

    func testOCRRejectsLockedPDF() {
        let url = createLockedPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try OCREngine.extractText(from: url)) { error in
            guard case CatboardError.extractionFailed = error else {
                XCTFail("Expected extractionFailed error, got \(error)")
                return
            }
        }
    }
}
