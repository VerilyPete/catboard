//! OCR support using macOS Vision framework via catboard-ocr helper.
//!
//! This module provides text extraction from images using Apple's Vision framework.
//! It requires the `catboard-ocr` helper binary to be available.

use crate::error::{CatboardError, Result};
use std::path::Path;
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

/// Find the catboard-ocr helper binary.
///
/// Looks in the following locations:
/// 1. Same directory as the current executable
/// 2. PATH
fn find_ocr_helper() -> Option<std::path::PathBuf> {
    // Try same directory as current executable
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            let helper_path = exe_dir.join("catboard-ocr");
            if helper_path.exists() {
                return Some(helper_path);
            }
        }
    }

    // Try PATH
    if let Ok(output) = Command::new("which").arg("catboard-ocr").output() {
        if output.status.success() {
            let path_str = String::from_utf8_lossy(&output.stdout);
            let path = Path::new(path_str.trim());
            if path.exists() {
                return Some(path.to_path_buf());
            }
        }
    }

    None
}

/// Extract text from an image file using OCR.
///
/// This requires the `catboard-ocr` helper binary to be installed.
/// On non-macOS platforms, this will return an error.
#[cfg(target_os = "macos")]
pub fn extract_text_from_image(path: &Path) -> Result<String> {
    let helper = find_ocr_helper().ok_or_else(|| CatboardError::ExtractionError {
        path: path.to_path_buf(),
        message: "OCR helper 'catboard-ocr' not found. Install it alongside catboard.".to_string(),
    })?;

    let output = Command::new(&helper)
        .arg(path)
        .output()
        .map_err(|e| CatboardError::ExtractionError {
            path: path.to_path_buf(),
            message: format!("Failed to run OCR helper: {}", e),
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(CatboardError::ExtractionError {
            path: path.to_path_buf(),
            message: format!("OCR failed: {}", stderr.trim()),
        });
    }

    let text = String::from_utf8_lossy(&output.stdout).to_string();

    if text.trim().is_empty() {
        return Err(CatboardError::ExtractionError {
            path: path.to_path_buf(),
            message: "Image contains no recognizable text".to_string(),
        });
    }

    Ok(text)
}

/// Extract text from an image file using OCR.
///
/// On non-macOS platforms, OCR is not supported.
#[cfg(not(target_os = "macos"))]
pub fn extract_text_from_image(path: &Path) -> Result<String> {
    Err(CatboardError::ExtractionError {
        path: path.to_path_buf(),
        message: "OCR is only supported on macOS".to_string(),
    })
}

/// Check if OCR is available on this system.
#[cfg(target_os = "macos")]
pub fn is_ocr_available() -> bool {
    find_ocr_helper().is_some()
}

/// Check if OCR is available on this system.
#[cfg(not(target_os = "macos"))]
pub fn is_ocr_available() -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_image_file() {
        assert!(is_image_file(Path::new("photo.png")));
        assert!(is_image_file(Path::new("photo.PNG")));
        assert!(is_image_file(Path::new("photo.jpg")));
        assert!(is_image_file(Path::new("photo.jpeg")));
        assert!(is_image_file(Path::new("photo.JPEG")));
        assert!(is_image_file(Path::new("photo.tiff")));
        assert!(is_image_file(Path::new("photo.heic")));
        assert!(!is_image_file(Path::new("document.txt")));
        assert!(!is_image_file(Path::new("document.pdf")));
        assert!(!is_image_file(Path::new("no_extension")));
    }
}
