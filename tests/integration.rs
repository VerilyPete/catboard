use assert_cmd::Command;
use predicates::prelude::*;
use std::fs::File;
use std::io::Write;
use tempfile::TempDir;

fn catboard_cmd() -> Command {
    Command::cargo_bin("catboard").unwrap()
}

#[test]
fn test_help_output() {
    catboard_cmd()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("Copy file contents to clipboard"))
        .stdout(predicate::str::contains("--verbose"))
        .stdout(predicate::str::contains("--quiet"));
}

#[test]
fn test_version_output() {
    catboard_cmd()
        .arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::contains("catboard"));
}

#[test]
fn test_no_arguments_shows_error() {
    catboard_cmd()
        .assert()
        .failure()
        .stderr(predicate::str::contains("required"));
}

#[test]
fn test_file_not_found() {
    catboard_cmd()
        .arg("/nonexistent/file/path.txt")
        .assert()
        .failure()
        .stderr(predicate::str::contains("File not found"));
}

#[test]
fn test_binary_file_rejected() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("binary.bin");

    let mut file = File::create(&file_path).unwrap();
    file.write_all(&[0x00, 0x01, 0x02, 0x03]).unwrap();

    catboard_cmd()
        .arg(file_path)
        .assert()
        .failure()
        .stderr(predicate::str::contains("Cannot read binary file"));
}

#[test]
fn test_verbose_flag() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("test.txt");

    let mut file = File::create(&file_path).unwrap();
    file.write_all(b"test content").unwrap();

    // Note: This test may fail in headless CI due to clipboard access
    // The verbose flag should still be parsed correctly
    let result = catboard_cmd().arg("-v").arg(&file_path).assert();

    // Either it succeeds with clipboard access, or fails with clipboard error
    // But it should not fail with "unknown flag" or similar
    let output = result.get_output();
    let stderr = String::from_utf8_lossy(&output.stderr);

    // Verify it's not a parsing error
    assert!(!stderr.contains("error: unexpected argument"));
}

#[test]
fn test_quiet_flag() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("test.txt");

    let mut file = File::create(&file_path).unwrap();
    file.write_all(b"test content").unwrap();

    let result = catboard_cmd().arg("-q").arg(&file_path).assert();

    let output = result.get_output();
    let stderr = String::from_utf8_lossy(&output.stderr);

    // Verify it's not a parsing error
    assert!(!stderr.contains("error: unexpected argument"));
}

#[test]
fn test_multiple_files_argument() {
    let dir = TempDir::new().unwrap();
    let file1 = dir.path().join("file1.txt");
    let file2 = dir.path().join("file2.txt");

    let mut f1 = File::create(&file1).unwrap();
    f1.write_all(b"content 1").unwrap();

    let mut f2 = File::create(&file2).unwrap();
    f2.write_all(b"content 2").unwrap();

    let result = catboard_cmd().arg(&file1).arg(&file2).assert();

    let output = result.get_output();
    let stderr = String::from_utf8_lossy(&output.stderr);

    // Verify it's not a parsing error
    assert!(!stderr.contains("error: unexpected argument"));
}

#[test]
fn test_stdin_dash_argument() {
    // Test that '-' is accepted as stdin indicator
    // Note: We can't easily test actual stdin in integration tests
    let result = catboard_cmd()
        .arg("-")
        .write_stdin("hello from stdin")
        .assert();

    let output = result.get_output();
    let stderr = String::from_utf8_lossy(&output.stderr);

    // Should not be an argument parsing error
    assert!(!stderr.contains("error: unexpected argument"));
}

// These tests require clipboard access and may be skipped in CI
#[test]
#[ignore = "Requires clipboard access"]
fn test_copy_text_file_to_clipboard() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("hello.txt");

    let mut file = File::create(&file_path).unwrap();
    file.write_all(b"Hello, clipboard!").unwrap();

    catboard_cmd()
        .arg(&file_path)
        .assert()
        .success()
        .stderr(predicate::str::contains("Copied"));
}

#[test]
#[ignore = "Requires clipboard access"]
fn test_copy_unicode_file_to_clipboard() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("unicode.txt");

    let mut file = File::create(&file_path).unwrap();
    file.write_all("Emoji: \u{1F600} Chinese: \u{4E2D}\u{6587}".as_bytes())
        .unwrap();

    catboard_cmd()
        .arg(&file_path)
        .assert()
        .success()
        .stderr(predicate::str::contains("Copied"));
}

#[test]
#[ignore = "Requires clipboard access"]
fn test_quiet_mode_no_output_on_success() {
    let dir = TempDir::new().unwrap();
    let file_path = dir.path().join("quiet.txt");

    let mut file = File::create(&file_path).unwrap();
    file.write_all(b"quiet test").unwrap();

    catboard_cmd()
        .arg("-q")
        .arg(&file_path)
        .assert()
        .success()
        .stderr(predicate::str::is_empty());
}
