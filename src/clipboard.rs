use crate::error::{CatboardError, Result};

/// Trait for clipboard operations, allowing for mocking in tests
pub trait Clipboard {
    fn set_text(&mut self, text: &str) -> Result<()>;
    fn get_text(&mut self) -> Result<String>;
}

/// System clipboard implementation using arboard
pub struct SystemClipboard {
    clipboard: arboard::Clipboard,
}

impl SystemClipboard {
    pub fn new() -> Result<Self> {
        let clipboard =
            arboard::Clipboard::new().map_err(|e| CatboardError::ClipboardError(e.to_string()))?;
        Ok(Self { clipboard })
    }
}

impl Clipboard for SystemClipboard {
    fn set_text(&mut self, text: &str) -> Result<()> {
        self.clipboard
            .set_text(text)
            .map_err(|e| CatboardError::ClipboardError(e.to_string()))
    }

    fn get_text(&mut self) -> Result<String> {
        self.clipboard
            .get_text()
            .map_err(|e| CatboardError::ClipboardError(e.to_string()))
    }
}

/// Copy text to the system clipboard
pub fn copy_to_clipboard(text: &str) -> Result<()> {
    let mut clipboard = SystemClipboard::new()?;
    clipboard.set_text(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    /// Mock clipboard for testing
    struct MockClipboard {
        content: RefCell<String>,
        should_fail: bool,
    }

    impl MockClipboard {
        fn new() -> Self {
            Self {
                content: RefCell::new(String::new()),
                should_fail: false,
            }
        }

        fn with_failure() -> Self {
            Self {
                content: RefCell::new(String::new()),
                should_fail: true,
            }
        }
    }

    impl Clipboard for MockClipboard {
        fn set_text(&mut self, text: &str) -> Result<()> {
            if self.should_fail {
                return Err(CatboardError::ClipboardError(
                    "Mock clipboard failure".to_string(),
                ));
            }
            *self.content.borrow_mut() = text.to_string();
            Ok(())
        }

        fn get_text(&mut self) -> Result<String> {
            if self.should_fail {
                return Err(CatboardError::ClipboardError(
                    "Mock clipboard failure".to_string(),
                ));
            }
            Ok(self.content.borrow().clone())
        }
    }

    #[test]
    fn test_mock_clipboard_set_and_get() {
        let mut clipboard = MockClipboard::new();

        clipboard.set_text("Hello, clipboard!").unwrap();
        let result = clipboard.get_text().unwrap();

        assert_eq!(result, "Hello, clipboard!");
    }

    #[test]
    fn test_mock_clipboard_empty() {
        let mut clipboard = MockClipboard::new();
        let result = clipboard.get_text().unwrap();
        assert_eq!(result, "");
    }

    #[test]
    fn test_mock_clipboard_unicode() {
        let mut clipboard = MockClipboard::new();
        let unicode_text = "\u{1F600} Emoji and \u{4E2D}\u{6587}!";

        clipboard.set_text(unicode_text).unwrap();
        let result = clipboard.get_text().unwrap();

        assert_eq!(result, unicode_text);
    }

    #[test]
    fn test_mock_clipboard_multiline() {
        let mut clipboard = MockClipboard::new();
        let multiline = "Line 1\nLine 2\nLine 3";

        clipboard.set_text(multiline).unwrap();
        let result = clipboard.get_text().unwrap();

        assert_eq!(result, multiline);
    }

    #[test]
    fn test_mock_clipboard_failure() {
        let mut clipboard = MockClipboard::with_failure();

        let result = clipboard.set_text("test");
        assert!(matches!(result, Err(CatboardError::ClipboardError(_))));

        let result = clipboard.get_text();
        assert!(matches!(result, Err(CatboardError::ClipboardError(_))));
    }

    #[test]
    fn test_mock_clipboard_overwrite() {
        let mut clipboard = MockClipboard::new();

        clipboard.set_text("First").unwrap();
        clipboard.set_text("Second").unwrap();

        let result = clipboard.get_text().unwrap();
        assert_eq!(result, "Second");
    }

    #[test]
    fn test_mock_clipboard_large_content() {
        let mut clipboard = MockClipboard::new();
        let large_text = "X".repeat(100_000);

        clipboard.set_text(&large_text).unwrap();
        let result = clipboard.get_text().unwrap();

        assert_eq!(result.len(), 100_000);
    }

    // Note: System clipboard tests are skipped in CI environments
    // because they require a display server (X11/Wayland on Linux)
    #[test]
    #[ignore = "Requires display server - run manually with --ignored"]
    fn test_system_clipboard_integration() {
        let result = copy_to_clipboard("Integration test content");
        // This may fail in headless environments
        if result.is_ok() {
            let mut clipboard = SystemClipboard::new().unwrap();
            let content = clipboard.get_text().unwrap();
            assert_eq!(content, "Integration test content");
        }
    }
}
