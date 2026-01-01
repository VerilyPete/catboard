//! # Catboard
//!
//! A cross-platform utility to copy file contents to the system clipboard.
//!
//! ## Features
//!
//! - Copy text file contents to clipboard from CLI
//! - macOS Finder integration via Quick Action
//! - Cross-platform support (macOS, Linux, Windows)
//! - Binary file detection to prevent clipboard corruption
//! - PDF text extraction
//! - Image OCR on macOS via Vision framework
//!
//! ## Example
//!
//! ```no_run
//! use catboard::{read_file_contents, copy_to_clipboard};
//!
//! let content = read_file_contents("file.txt").unwrap();
//! copy_to_clipboard(&content).unwrap();
//! ```

pub mod clipboard;
pub mod error;
pub mod file;
pub mod ocr;

pub use clipboard::{copy_to_clipboard, Clipboard, SystemClipboard};
pub use error::{CatboardError, Result};
pub use file::{read_file_contents, read_stdin};

/// Copy contents of a file to the clipboard
///
/// This is the main high-level function that combines file reading
/// and clipboard operations.
pub fn copy_file_to_clipboard<P: AsRef<std::path::Path>>(path: P) -> Result<usize> {
    let content = read_file_contents(path)?;
    let len = content.len();
    copy_to_clipboard(&content)?;
    Ok(len)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    use tempfile::TempDir;

    #[test]
    fn test_copy_file_to_clipboard_file_not_found() {
        let result = copy_file_to_clipboard("/nonexistent/file.txt");
        assert!(matches!(result, Err(CatboardError::FileNotFound(_))));
    }

    #[test]
    fn test_copy_file_to_clipboard_binary_file() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("binary.bin");

        let mut file = File::create(&file_path).unwrap();
        file.write_all(&[0x00, 0x01, 0x02]).unwrap();

        let result = copy_file_to_clipboard(&file_path);
        assert!(matches!(result, Err(CatboardError::BinaryFile(_))));
    }

    // Integration test for actual clipboard - skipped in CI
    #[test]
    #[ignore = "Requires display server"]
    fn test_copy_file_to_clipboard_success() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("test.txt");

        let mut file = File::create(&file_path).unwrap();
        file.write_all(b"Test content").unwrap();

        let result = copy_file_to_clipboard(&file_path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 12); // "Test content" length
    }
}
