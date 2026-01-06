import Quartz
import os.log

public struct PDFExtractor {
    /// Extract text from PDF, falling back to OCR for scanned documents
    public static func extractText(from url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw CatboardError.extractionFailed(url, "Could not open PDF")
        }

        if pdf.isLocked {
            throw CatboardError.extractionFailed(url, "PDF is password-protected")
        }

        if pdf.pageCount == 0 {
            throw CatboardError.extractionFailed(url, "PDF has no pages")
        }

        os_log("PDF has %d pages", log: .pdf, type: .info, pdf.pageCount)

        // Try embedded text extraction first
        var allText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let text = page.string {
                if !allText.isEmpty { allText += "\n" }
                allText += text
            }
        }

        // If we got meaningful text, return it
        if !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            os_log("Extracted embedded text from PDF", log: .pdf, type: .info)
            return allText
        }

        // Fall back to OCR for scanned PDFs
        os_log("No embedded text, falling back to OCR", log: .pdf, type: .info)
        return try OCREngine.extractText(from: url)
    }
}
