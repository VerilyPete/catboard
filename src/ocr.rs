//! OCR support using macOS Vision framework via catboard-ocr helper.
//!
//! This module provides text extraction from images using Apple's Vision framework.
//! It requires the `catboard-ocr` helper binary to be available.

use crate::error::{CatboardError, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Known image extensions that we can OCR
const IMAGE_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "tiff", "tif", "gif", "bmp", "webp", "heic", "heif",
];

/// Check if a file extension indicates an image file
pub fn is_image_file(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| IMAGE_EXTENSIONS.contains(&ext.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// Trait for OCR operations, allowing for mocking in tests
pub trait OcrEngine: Send + Sync {
    /// Extract text from an image file
    fn extract_text(&self, path: &Path) -> Result<String>;

    /// Check if OCR is available
    fn is_available(&self) -> bool;
}

/// Real OCR engine using catboard-ocr helper
pub struct SystemOcrEngine {
    // Only used on macOS; stored on all platforms for API consistency
    #[allow(dead_code)]
    helper_path: Option<PathBuf>,
}

impl SystemOcrEngine {
    /// Create a new system OCR engine, searching for the helper binary
    pub fn new() -> Self {
        Self {
            helper_path: find_ocr_helper(),
        }
    }

    /// Create with a specific helper path (for testing)
    #[cfg(test)]
    pub fn with_helper(path: PathBuf) -> Self {
        Self {
            helper_path: Some(path),
        }
    }
}

impl Default for SystemOcrEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl OcrEngine for SystemOcrEngine {
    #[cfg(target_os = "macos")]
    fn extract_text(&self, path: &Path) -> Result<String> {
        let helper = self
            .helper_path
            .as_ref()
            .ok_or_else(|| CatboardError::ExtractionError {
                path: path.to_path_buf(),
                message: "OCR helper 'catboard-ocr' not found. Install it alongside catboard."
                    .to_string(),
            })?;

        run_ocr_helper(helper, path)
    }

    #[cfg(not(target_os = "macos"))]
    fn extract_text(&self, path: &Path) -> Result<String> {
        Err(CatboardError::ExtractionError {
            path: path.to_path_buf(),
            message: "OCR is only supported on macOS".to_string(),
        })
    }

    fn is_available(&self) -> bool {
        #[cfg(target_os = "macos")]
        {
            self.helper_path.is_some()
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }
}

/// Run the OCR helper binary and extract text
#[cfg(target_os = "macos")]
fn run_ocr_helper(helper: &Path, image_path: &Path) -> Result<String> {
    let output = Command::new(helper).arg(image_path).output().map_err(|e| {
        CatboardError::ExtractionError {
            path: image_path.to_path_buf(),
            message: format!("Failed to run OCR helper: {}", e),
        }
    })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(CatboardError::ExtractionError {
            path: image_path.to_path_buf(),
            message: format!("OCR failed: {}", stderr.trim()),
        });
    }

    let text = String::from_utf8_lossy(&output.stdout).to_string();

    if text.trim().is_empty() {
        return Err(CatboardError::ExtractionError {
            path: image_path.to_path_buf(),
            message: "Image contains no recognizable text".to_string(),
        });
    }

    Ok(text)
}

/// Find the catboard-ocr helper binary.
///
/// Looks in the following locations:
/// 1. Same directory as the current executable
/// 2. PATH
fn find_ocr_helper() -> Option<PathBuf> {
    // Try same directory as current executable
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            let helper_path = exe_dir.join("catboard-ocr");
            if helper_path.exists() {
                return Some(helper_path);
            }
        }
    }

    // Try PATH using `which` on Unix
    #[cfg(unix)]
    if let Ok(output) = Command::new("which").arg("catboard-ocr").output() {
        if output.status.success() {
            let path_str = String::from_utf8_lossy(&output.stdout);
            let path = PathBuf::from(path_str.trim());
            if path.exists() {
                return Some(path);
            }
        }
    }

    // Try PATH using `where` on Windows
    #[cfg(windows)]
    if let Ok(output) = Command::new("where").arg("catboard-ocr").output() {
        if output.status.success() {
            let path_str = String::from_utf8_lossy(&output.stdout);
            if let Some(first_line) = path_str.lines().next() {
                let path = PathBuf::from(first_line.trim());
                if path.exists() {
                    return Some(path);
                }
            }
        }
    }

    None
}

/// Extract text from an image file using OCR.
///
/// This requires the `catboard-ocr` helper binary to be installed.
/// On non-macOS platforms, this will return an error.
pub fn extract_text_from_image(path: &Path) -> Result<String> {
    SystemOcrEngine::new().extract_text(path)
}

/// Check if OCR is available on this system.
pub fn is_ocr_available() -> bool {
    SystemOcrEngine::new().is_available()
}

#[cfg(test)]
pub mod mock {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    /// Represents a mock OCR response
    #[derive(Clone)]
    pub enum MockResponse {
        /// Successful text extraction
        Text(String),
        /// Extraction error with message
        Error(String),
    }

    /// Mock OCR engine for testing
    pub struct MockOcrEngine {
        responses: Mutex<HashMap<PathBuf, MockResponse>>,
        available: bool,
    }

    impl MockOcrEngine {
        /// Create a new mock OCR engine
        pub fn new(available: bool) -> Self {
            Self {
                responses: Mutex::new(HashMap::new()),
                available,
            }
        }

        /// Set a successful response for a path
        pub fn set_text(&self, path: PathBuf, text: &str) {
            self.responses
                .lock()
                .unwrap()
                .insert(path, MockResponse::Text(text.to_string()));
        }

        /// Set an error response for a path
        pub fn set_error(&self, path: PathBuf, message: &str) {
            self.responses
                .lock()
                .unwrap()
                .insert(path, MockResponse::Error(message.to_string()));
        }
    }

    impl OcrEngine for MockOcrEngine {
        fn extract_text(&self, path: &Path) -> Result<String> {
            let responses = self.responses.lock().unwrap();
            match responses.get(path) {
                Some(MockResponse::Text(text)) => Ok(text.clone()),
                Some(MockResponse::Error(msg)) => Err(CatboardError::ExtractionError {
                    path: path.to_path_buf(),
                    message: msg.clone(),
                }),
                None => Err(CatboardError::ExtractionError {
                    path: path.to_path_buf(),
                    message: "No mock response configured for this path".to_string(),
                }),
            }
        }

        fn is_available(&self) -> bool {
            self.available
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    use tempfile::TempDir;

    #[test]
    fn test_is_image_file_common_formats() {
        assert!(is_image_file(Path::new("photo.png")));
        assert!(is_image_file(Path::new("photo.jpg")));
        assert!(is_image_file(Path::new("photo.jpeg")));
        assert!(is_image_file(Path::new("photo.gif")));
        assert!(is_image_file(Path::new("photo.bmp")));
        assert!(is_image_file(Path::new("photo.webp")));
    }

    #[test]
    fn test_is_image_file_case_insensitive() {
        assert!(is_image_file(Path::new("photo.PNG")));
        assert!(is_image_file(Path::new("photo.JPG")));
        assert!(is_image_file(Path::new("photo.JPEG")));
        assert!(is_image_file(Path::new("photo.Tiff")));
        assert!(is_image_file(Path::new("photo.HEIC")));
    }

    #[test]
    fn test_is_image_file_apple_formats() {
        assert!(is_image_file(Path::new("photo.heic")));
        assert!(is_image_file(Path::new("photo.heif")));
        assert!(is_image_file(Path::new("photo.tiff")));
        assert!(is_image_file(Path::new("photo.tif")));
    }

    #[test]
    fn test_is_image_file_non_images() {
        assert!(!is_image_file(Path::new("document.txt")));
        assert!(!is_image_file(Path::new("document.pdf")));
        assert!(!is_image_file(Path::new("script.sh")));
        assert!(!is_image_file(Path::new("code.rs")));
        assert!(!is_image_file(Path::new("no_extension")));
        assert!(!is_image_file(Path::new(".hidden")));
    }

    #[test]
    fn test_is_image_file_with_path() {
        assert!(is_image_file(Path::new("/path/to/photo.png")));
        assert!(is_image_file(Path::new("./relative/photo.jpg")));
        assert!(is_image_file(Path::new("../parent/photo.tiff")));
    }

    #[test]
    fn test_mock_ocr_engine_success() {
        let engine = mock::MockOcrEngine::new(true);
        let path = PathBuf::from("/test/image.png");
        engine.set_text(path.clone(), "Hello, World!");

        let result = engine.extract_text(&path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "Hello, World!");
    }

    #[test]
    fn test_mock_ocr_engine_error() {
        let engine = mock::MockOcrEngine::new(true);
        let path = PathBuf::from("/test/image.png");
        engine.set_error(path.clone(), "OCR failed");

        let result = engine.extract_text(&path);
        assert!(result.is_err());
    }

    #[test]
    fn test_mock_ocr_engine_no_response() {
        let engine = mock::MockOcrEngine::new(true);
        let path = PathBuf::from("/test/unknown.png");

        let result = engine.extract_text(&path);
        assert!(result.is_err());
    }

    #[test]
    fn test_mock_ocr_engine_availability() {
        let available = mock::MockOcrEngine::new(true);
        let unavailable = mock::MockOcrEngine::new(false);

        assert!(available.is_available());
        assert!(!unavailable.is_available());
    }

    #[test]
    fn test_system_ocr_engine_not_available_without_helper() {
        // Create engine with no helper
        let engine = SystemOcrEngine { helper_path: None };
        assert!(!engine.is_available());
    }

    #[test]
    fn test_image_file_detection_in_read_file_contents() {
        let dir = TempDir::new().unwrap();

        // Create a fake image file (will fail OCR but tests routing)
        let png_path = dir.path().join("test.png");
        let mut file = File::create(&png_path).unwrap();
        file.write_all(b"fake png data").unwrap();

        // On non-macOS, should get "OCR only supported on macOS"
        // On macOS without helper, should get "OCR helper not found"
        let result = crate::file::read_file_contents(&png_path);
        assert!(result.is_err());

        let err = result.unwrap_err();
        let err_msg = err.to_string();

        // Should be routed to OCR, not treated as text or binary
        assert!(
            err_msg.contains("OCR") || err_msg.contains("extract"),
            "Expected OCR-related error, got: {}",
            err_msg
        );
    }

    // Integration test - only runs on macOS with helper installed
    #[test]
    #[ignore = "Requires catboard-ocr helper installed on macOS"]
    fn test_real_ocr_with_helper() {
        // This test requires:
        // 1. Running on macOS
        // 2. catboard-ocr helper compiled and in PATH or next to test binary

        let dir = TempDir::new().unwrap();
        let _image_path = dir.path().join("test.png");

        // Would need a real image with text here
        // For now, this is a placeholder for manual testing

        if is_ocr_available() {
            // If we had a real test image, we'd test it here
            println!("OCR helper is available");
        } else {
            println!("OCR helper not found, skipping");
        }
    }
}
