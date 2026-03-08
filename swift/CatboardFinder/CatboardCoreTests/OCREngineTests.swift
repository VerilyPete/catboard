import XCTest
import AppKit
import CoreGraphics
import ImageIO
@testable import CatboardCore

final class OCREngineTests: XCTestCase {

    // MARK: - Helpers

    private func tempURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    /// Create an oversized PNG that exceeds the 50MP limit.
    /// 8000 x 7000 = 56,000,000 pixels > 50,000,000.
    private func createOversizedPNG() -> URL {
        let url = tempURL(extension: "png")
        let width = 8000
        let height = 7000

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create CGContext for oversized image")
            return url
        }

        // Fill with solid color
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            XCTFail("Could not create CGImage")
            return url
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            XCTFail("Could not create image destination")
            return url
        }

        // No DPI properties — defaults to 72 DPI
        CGImageDestinationAddImage(destination, cgImage, nil)
        let success = CGImageDestinationFinalize(destination)
        XCTAssertTrue(success, "Should write PNG to disk")

        return url
    }

    // MARK: - Tests

    func testOCRRejectsOversizedImage() {
        let url = createOversizedPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try OCREngine.extractText(from: url)) { error in
            guard case CatboardError.imageTooLarge = error else {
                XCTFail("Expected imageTooLarge error, got \(error)")
                return
            }
        }
    }
}
