use crate::error::{CatboardError, Result};
use crate::ocr;
use pdf_oxide::PdfDocument;
use std::ffi::OsStr;
use std::fs;
use std::io::{self, Read};
use std::path::Path;

/// Maximum bytes to check for binary content detection
const BINARY_CHECK_SIZE: usize = 8192;

/// Check if extension matches PDF (case-insensitive)
fn is_pdf_extension(ext: Option<&str>) -> bool {
    ext.map(|e| e.eq_ignore_ascii_case("pdf")).unwrap_or(false)
}

/// Reads the contents of a file as a UTF-8 string.
///
/// Supports multiple file types:
/// - **Text files**: Read directly with binary detection
/// - **PDF files**: Extract embedded text, with OCR fallback for scanned pages
/// - **Image files**: OCR using macOS Vision framework (macOS only)
///
/// # Errors
/// - `FileNotFound` if the file doesn't exist
/// - `PermissionDenied` if the file can't be accessed
/// - `BinaryFile` if the file contains null bytes (likely binary)
/// - `ExtractionError` if text extraction or OCR fails
/// - `IoError` for other I/O failures
pub fn read_file_contents<P: AsRef<Path>>(path: P) -> Result<String> {
    let path = path.as_ref();

    // Check if file exists and is accessible
    if !path.exists() {
        return Err(CatboardError::FileNotFound(path.to_path_buf()));
    }

    // Check file extension for special handling
    let extension = path.extension().and_then(OsStr::to_str);

    if is_pdf_extension(extension) {
        extract_pdf_text(path)
    } else if ocr::is_image_file(path) {
        ocr::extract_text_from_image(path)
    } else {
        read_text_file(path)
    }
}

/// Extract text from a PDF file.
///
/// First attempts to extract embedded text. If the PDF appears to be scanned
/// (no text but has images), falls back to OCR on macOS.
fn extract_pdf_text(path: &Path) -> Result<String> {
    let mut doc = PdfDocument::open(path).map_err(|e| CatboardError::ExtractionError {
        path: path.to_path_buf(),
        message: e.to_string(),
    })?;

    let page_count = doc
        .page_count()
        .map_err(|e| CatboardError::ExtractionError {
            path: path.to_path_buf(),
            message: e.to_string(),
        })?;
    let mut all_text = String::new();

    for page_num in 0..page_count {
        match doc.extract_text(page_num) {
            Ok(text) => {
                if !all_text.is_empty() {
                    all_text.push('\n');
                }
                all_text.push_str(&text);
            }
            Err(e) => {
                return Err(CatboardError::ExtractionError {
                    path: path.to_path_buf(),
                    message: format!("Failed to extract page {}: {}", page_num + 1, e),
                });
            }
        }
    }

    // If we got text, return it
    if !all_text.trim().is_empty() {
        return Ok(all_text);
    }

    // No text found - try OCR if available (scanned PDF)
    if ocr::is_ocr_available() {
        return extract_pdf_with_ocr(&mut doc, path, page_count);
    }

    Err(CatboardError::ExtractionError {
        path: path.to_path_buf(),
        message: "PDF contains no extractable text".to_string(),
    })
}

/// Extract text from a scanned PDF using OCR.
///
/// Uses macOS Vision framework via catboard-ocr helper.
/// NSImage can render PDFs directly, so we pass the PDF to OCR
/// rather than extracting individual images (which can lose quality).
#[cfg(target_os = "macos")]
fn extract_pdf_with_ocr(_doc: &mut PdfDocument, path: &Path, _page_count: usize) -> Result<String> {
    // NSImage can render PDFs directly, and catboard-ocr uses NSImage.
    // This is simpler and more reliable than extracting images with pdf_oxide.
    // Note: For multi-page PDFs, NSImage renders the first page only.
    // This is acceptable for most scanned documents which are single-page.
    let text = ocr::extract_text_from_image(path)?;

    if text.trim().is_empty() {
        return Err(CatboardError::ExtractionError {
            path: path.to_path_buf(),
            message: "PDF contains no recognizable text (OCR found nothing)".to_string(),
        });
    }

    Ok(text)
}

/// Stub for non-macOS platforms - OCR not available
#[cfg(not(target_os = "macos"))]
fn extract_pdf_with_ocr(_doc: &mut PdfDocument, path: &Path, _page_count: usize) -> Result<String> {
    Err(CatboardError::ExtractionError {
        path: path.to_path_buf(),
        message: "PDF contains no extractable text (OCR only available on macOS)".to_string(),
    })
}

/// Read a plain text file with binary detection
fn read_text_file(path: &Path) -> Result<String> {
    // Try to open the file
    let mut file = fs::File::open(path).map_err(|e| match e.kind() {
        io::ErrorKind::PermissionDenied => CatboardError::PermissionDenied(path.to_path_buf()),
        io::ErrorKind::NotFound => CatboardError::FileNotFound(path.to_path_buf()),
        _ => CatboardError::IoError {
            path: path.to_path_buf(),
            source: e,
        },
    })?;

    // Check for binary content by reading first chunk
    let mut buffer = vec![0u8; BINARY_CHECK_SIZE];
    let bytes_read = file.read(&mut buffer).map_err(|e| CatboardError::IoError {
        path: path.to_path_buf(),
        source: e,
    })?;

    // Check for null bytes which indicate binary content
    if buffer[..bytes_read].contains(&0) {
        return Err(CatboardError::BinaryFile(path.to_path_buf()));
    }

    // Re-read the entire file as a string
    fs::read_to_string(path).map_err(|e| CatboardError::IoError {
        path: path.to_path_buf(),
        source: e,
    })
}

/// Reads content from stdin
pub fn read_stdin() -> Result<String> {
    let mut buffer = String::new();
    io::stdin()
        .read_to_string(&mut buffer)
        .map_err(|e| CatboardError::IoError {
            path: "-".into(),
            source: e,
        })?;
    Ok(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    use tempfile::TempDir;

    #[test]
    fn test_read_valid_text_file() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("test.txt");
        let content = "Hello, world!\nThis is a test file.";

        let mut file = File::create(&file_path).unwrap();
        file.write_all(content.as_bytes()).unwrap();

        let result = read_file_contents(&file_path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), content);
    }

    #[test]
    fn test_read_empty_file() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("empty.txt");

        File::create(&file_path).unwrap();

        let result = read_file_contents(&file_path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "");
    }

    #[test]
    fn test_read_file_with_unicode() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("unicode.txt");
        let content = "Hello \u{1F600} emoji and \u{4E2D}\u{6587} chinese!";

        let mut file = File::create(&file_path).unwrap();
        file.write_all(content.as_bytes()).unwrap();

        let result = read_file_contents(&file_path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), content);
    }

    #[test]
    fn test_file_not_found() {
        let result = read_file_contents("/nonexistent/path/file.txt");
        assert!(matches!(result, Err(CatboardError::FileNotFound(_))));
    }

    #[test]
    fn test_binary_file_detection() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("binary.bin");

        // Create a file with null bytes (binary content)
        let mut file = File::create(&file_path).unwrap();
        file.write_all(&[0x48, 0x65, 0x6c, 0x00, 0x6f]).unwrap(); // "Hel\0o"

        let result = read_file_contents(&file_path);
        assert!(matches!(result, Err(CatboardError::BinaryFile(_))));
    }

    #[test]
    fn test_read_large_text_file() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("large.txt");

        // Create a file larger than BINARY_CHECK_SIZE
        let content = "A".repeat(10000);
        let mut file = File::create(&file_path).unwrap();
        file.write_all(content.as_bytes()).unwrap();

        let result = read_file_contents(&file_path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().len(), 10000);
    }

    #[test]
    fn test_binary_file_with_late_null() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("late_null.bin");

        // Null byte within the check window
        let mut content = vec![0x41u8; 5000]; // 'A' repeated
        content[4000] = 0x00; // null byte at position 4000

        let mut file = File::create(&file_path).unwrap();
        file.write_all(&content).unwrap();

        let result = read_file_contents(&file_path);
        assert!(matches!(result, Err(CatboardError::BinaryFile(_))));
    }

    #[test]
    fn test_pdf_extension_detected() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("test.pdf");

        // Create a fake PDF (will fail extraction but tests extension detection)
        let mut file = File::create(&file_path).unwrap();
        file.write_all(b"not a real pdf").unwrap();

        let result = read_file_contents(&file_path);
        // Should fail with ExtractionError, not BinaryFile
        assert!(matches!(result, Err(CatboardError::ExtractionError { .. })));
    }

    #[test]
    fn test_rotated_pdf_detected_as_pdf() {
        // Test that a rotated PDF is properly recognized as a PDF
        // (not rejected as binary)
        let pdf_path = std::path::Path::new("tests/2025-12-12_12-11-14.pdf");
        if pdf_path.exists() {
            let result = read_file_contents(pdf_path);
            // Should fail with ExtractionError (no text or no OCR), not BinaryFile
            match result {
                Err(CatboardError::BinaryFile(_)) => {
                    panic!("Rotated PDF should not be rejected as binary file");
                }
                Err(CatboardError::ExtractionError { .. }) => {
                    // Expected - PDF has no text and OCR may not be available
                }
                Ok(_) => {
                    // Also acceptable if OCR is available and works
                }
                Err(e) => {
                    panic!("Unexpected error type: {:?}", e);
                }
            }
        }
    }
}
