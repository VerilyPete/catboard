use std::path::PathBuf;
use thiserror::Error;

/// Errors that can occur during catboard operations
#[derive(Error, Debug)]
pub enum CatboardError {
    #[error("File not found: {0}")]
    FileNotFound(PathBuf),

    #[error("Permission denied: {0}")]
    PermissionDenied(PathBuf),

    #[error("Cannot read binary file: {0}")]
    BinaryFile(PathBuf),

    #[error("Failed to read file '{path}': {source}")]
    IoError {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("Clipboard error: {0}")]
    ClipboardError(String),

    #[error("No files specified")]
    NoFilesSpecified,
}

pub type Result<T> = std::result::Result<T, CatboardError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_file_not_found_error_display() {
        let err = CatboardError::FileNotFound(PathBuf::from("/path/to/file.txt"));
        assert_eq!(err.to_string(), "File not found: /path/to/file.txt");
    }

    #[test]
    fn test_permission_denied_error_display() {
        let err = CatboardError::PermissionDenied(PathBuf::from("/secret/file.txt"));
        assert_eq!(err.to_string(), "Permission denied: /secret/file.txt");
    }

    #[test]
    fn test_binary_file_error_display() {
        let err = CatboardError::BinaryFile(PathBuf::from("image.png"));
        assert_eq!(err.to_string(), "Cannot read binary file: image.png");
    }

    #[test]
    fn test_clipboard_error_display() {
        let err = CatboardError::ClipboardError("No display available".to_string());
        assert_eq!(err.to_string(), "Clipboard error: No display available");
    }

    #[test]
    fn test_no_files_specified_error_display() {
        let err = CatboardError::NoFilesSpecified;
        assert_eq!(err.to_string(), "No files specified");
    }

    #[test]
    fn test_io_error_display() {
        let io_err = std::io::Error::new(std::io::ErrorKind::Other, "disk full");
        let err = CatboardError::IoError {
            path: PathBuf::from("data.txt"),
            source: io_err,
        };
        assert_eq!(err.to_string(), "Failed to read file 'data.txt': disk full");
    }
}
