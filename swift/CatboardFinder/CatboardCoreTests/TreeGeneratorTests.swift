import XCTest
@testable import CatboardCore

final class TreeGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catboard-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Single File Directory

    func testSingleFileDirectory() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "hello world".write(to: dir.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertEqual(result.filesIncluded, 1)
        XCTAssertEqual(result.filesSkipped, 0)
        XCTAssertFalse(result.truncated)
        XCTAssertTrue(result.output.contains("hello.txt"))
        XCTAssertTrue(result.output.contains("hello world"))
    }

    // MARK: - Nested Directories

    func testNestedDirectories() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let subdir = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "fn one() {}".write(to: dir.appendingPathComponent("one.rs"), atomically: true, encoding: .utf8)
        try "fn two() {}".write(to: subdir.appendingPathComponent("two.rs"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertEqual(result.filesIncluded, 2)
        XCTAssertTrue(result.output.contains("fn one()"))
        XCTAssertTrue(result.output.contains("fn two()"))
        XCTAssertTrue(result.output.contains("sub/"))
    }

    // MARK: - Binary File Skipped

    func testBinaryFileSkipped() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "text content".write(to: dir.appendingPathComponent("text.txt"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: dir.appendingPathComponent("binary.bin"))

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertEqual(result.filesIncluded, 1)
        XCTAssertEqual(result.filesSkipped, 1)
        XCTAssertTrue(result.output.contains("Skipped"))
        XCTAssertTrue(result.output.contains("binary"))
    }

    // MARK: - Empty Directory

    func testEmptyDirectory() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertEqual(result.filesIncluded, 0)
        XCTAssertTrue(result.output.contains("## Structure"))
        XCTAssertTrue(result.output.contains("0 files included"))
    }

    // MARK: - Max File Size Exceeded

    func testMaxFileSizeExceeded() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "tiny".write(to: dir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: 1000).write(to: dir.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)

        let options = TreeOptions(maxFileSize: 100)
        let result = try TreeGenerator.generate(directories: [dir], options: options)
        XCTAssertEqual(result.filesIncluded, 1)
        XCTAssertEqual(result.filesSkipped, 1)
        XCTAssertTrue(result.output.contains("Skipped"))
        XCTAssertTrue(result.output.contains("exceeds"))
    }

    // MARK: - Max Total Size Exceeded

    func testMaxTotalSizeExceeded() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try String(repeating: "a", count: 600).write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "b", count: 600).write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let options = TreeOptions(maxTotalSize: 800)
        let result = try TreeGenerator.generate(directories: [dir], options: options)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.output.contains("Truncated"))
    }

    // MARK: - Noise Directories Skipped

    func testNoiseDirectoriesSkipped() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let nodeModules = dir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "{}".write(to: nodeModules.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "console.log('hi')".write(to: dir.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)

        let options = TreeOptions(respectGitignore: false)
        let result = try TreeGenerator.generate(directories: [dir], options: options)
        XCTAssertTrue(result.output.contains("app.js"))
        XCTAssertFalse(result.output.contains("node_modules"))
    }

    // MARK: - Gitignore Respected

    func testGitignoreRespected() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Init git repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        try "ignored.txt\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "secret".write(to: dir.appendingPathComponent("ignored.txt"), atomically: true, encoding: .utf8)
        try "public".write(to: dir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertTrue(result.output.contains("public"))
        XCTAssertFalse(result.output.contains("secret"))
    }

    // MARK: - Language Detection

    func testLanguageDetection() {
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "main.rs")), "rust")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "app.py")), "python")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "index.js")), "javascript")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "main.ts")), "typescript")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "App.tsx")), "tsx")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "App.swift")), "swift")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "main.go")), "go")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "config.yml")), "yaml")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "config.yaml")), "yaml")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "Dockerfile")), "dockerfile")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "Dockerfile.prod")), "dockerfile")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "Makefile")), "makefile")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "CMakeLists.txt")), "cmake")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "Cargo.lock")), "toml")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: "poetry.lock")), "toml")
        XCTAssertEqual(TreeGenerator.detectLanguage(URL(fileURLWithPath: ".env")), "dotenv")
        XCTAssertNil(TreeGenerator.detectLanguage(URL(fileURLWithPath: "data.xyz")))
        XCTAssertNil(TreeGenerator.detectLanguage(URL(fileURLWithPath: "README")))
    }

    // MARK: - Nested Code Fences

    func testNestedCodeFences() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "# Example\n```rust\nfn main() {}\n```\n".write(
            to: dir.appendingPathComponent("readme.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertTrue(result.output.contains("````"))
    }

    // MARK: - Filename With Backticks

    func testFilenameWithBackticks() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "code".write(to: dir.appendingPathComponent("file`name.rs"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertTrue(result.output.contains("file\\`name.rs"))
    }

    // MARK: - Stats Line

    func testStatsLine() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "world!".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertEqual(result.filesIncluded, 2)
        XCTAssertEqual(result.filesSkipped, 0)
        XCTAssertEqual(result.totalBytes, 11)
        XCTAssertTrue(result.output.contains("2 files included, 0 skipped, 11B total"))
    }

    // MARK: - Truncation Behavior

    func testTruncationBehavior() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try String(repeating: "a", count: 500).write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "b", count: 500).write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "c", count: 500).write(to: dir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let options = TreeOptions(maxTotalSize: 800)
        let result = try TreeGenerator.generate(directories: [dir], options: options)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.filesIncluded, 1)
        XCTAssertTrue(result.filesSkipped >= 1)
    }

    // MARK: - Unicode Filenames

    func testUnicodeFilenames() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}\u{4E16}\u{754C}".write(
            to: dir.appendingPathComponent("\u{65E5}\u{672C}\u{8A9E}.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertTrue(result.output.contains("\u{65E5}\u{672C}\u{8A9E}.txt"))
        XCTAssertTrue(result.output.contains("\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}\u{4E16}\u{754C}"))
    }

    // MARK: - Format Size

    func testFormatSize() {
        XCTAssertEqual(TreeGenerator.formatSize(42), "42B")
        XCTAssertEqual(TreeGenerator.formatSize(4096), "4.0KB")
        XCTAssertEqual(TreeGenerator.formatSize(2 * 1024 * 1024), "2.0MB")
        XCTAssertEqual(TreeGenerator.formatSize(1536), "1.5KB")
    }

    // MARK: - Format Size Boundaries (Fix 15)

    func testFormatSizeBoundaries() {
        XCTAssertEqual(TreeGenerator.formatSize(0), "0B")
        XCTAssertEqual(TreeGenerator.formatSize(1023), "1023B")
        XCTAssertEqual(TreeGenerator.formatSize(1024), "1.0KB")
        XCTAssertEqual(TreeGenerator.formatSize(1048575), "1024.0KB")
        XCTAssertEqual(TreeGenerator.formatSize(1048576), "1.0MB")
    }

    // MARK: - Total Bytes Counts Decoded String (Fix 4)

    func testTotalBytesCountsDecodedString() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // UTF-8 BOM (3 bytes) followed by ASCII content "hello" (5 bytes)
        // Raw data = 8 bytes, decoded string = "hello" (5 bytes, BOM stripped by String(data:encoding:))
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let content = "hello"
        var data = Data(bom)
        data.append(contentsOf: content.utf8)

        try data.write(to: dir.appendingPathComponent("bom.txt"))

        let result = try TreeGenerator.generate(directories: [dir])
        // The decoded string includes the BOM character U+FEFF, so utf8.count = 3 + 5 = 8
        // Actually, String(data:encoding:.utf8) preserves the BOM as U+FEFF character
        // Let's verify what the actual decoded string's utf8.count is
        let decoded = String(data: data, encoding: .utf8)!
        XCTAssertEqual(result.totalBytes, decoded.utf8.count)
    }

    // MARK: - Permission Denied File Skipped (Fix 10)

    func testPermissionDeniedFileSkipped() throws {
        // Skip when running as root — chmod 000 has no effect for root
        guard getuid() != 0 else { return }

        let dir = try makeTempDir()
        let restrictedFile = dir.appendingPathComponent("restricted.txt")
        try "secret".write(to: restrictedFile, atomically: true, encoding: .utf8)

        // Remove all permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restrictedFile.path)

        // Restore permissions before cleanup so removeItem can succeed
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: restrictedFile.path)
            cleanup(dir)
        }

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertEqual(result.filesSkipped, 1)
        XCTAssertTrue(result.output.contains("Skipped"))
        XCTAssertTrue(result.output.contains("restricted.txt"))
    }

    // MARK: - Symlink Tests (Fix 11)

    func testSymlinkFileNotFollowed() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let targetFile = dir.appendingPathComponent("target.txt")
        try "target content".write(to: targetFile, atomically: true, encoding: .utf8)

        let symlinkFile = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: targetFile)

        let options = TreeOptions(respectGitignore: false)
        let result = try TreeGenerator.generate(directories: [dir], options: options)

        // Symlink should appear in tree listing
        XCTAssertTrue(result.output.contains("link.txt"))
        // Symlink should generate a skip note, not a content section
        XCTAssertTrue(result.output.contains("Skipped: link.txt (symlink)"))
        // Target file content should still be included (it's a real file)
        XCTAssertTrue(result.output.contains("target content"))
        XCTAssertEqual(result.filesIncluded, 1)
        XCTAssertEqual(result.filesSkipped, 1)
    }

    func testSymlinkDirectoryNotFollowed() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let targetDir = dir.appendingPathComponent("realdir")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try "inside target".write(to: targetDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)

        let symlinkDir = dir.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: targetDir)

        let options = TreeOptions(respectGitignore: false)
        let result = try TreeGenerator.generate(directories: [dir], options: options)

        // Symlinked directory should appear in tree listing
        XCTAssertTrue(result.output.contains("linkdir"))
        // Files inside the symlinked directory should NOT appear
        XCTAssertFalse(result.output.contains("linkdir/inner.txt"))
        // But files in the real directory should appear
        XCTAssertTrue(result.output.contains("realdir/"))
        XCTAssertTrue(result.output.contains("inside target"))
    }

    func testBrokenSymlinkSkipped() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let brokenLink = dir.appendingPathComponent("broken.txt")
        let nonexistent = dir.appendingPathComponent("nonexistent.txt")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: nonexistent)

        let options = TreeOptions(respectGitignore: false)
        let result = try TreeGenerator.generate(directories: [dir], options: options)
        // Should not crash — broken symlinks should be handled gracefully
        XCTAssertTrue(result.output.contains("## Structure"))
        // Broken symlink should appear in tree listing but not as a file content section
        XCTAssertTrue(result.output.contains("broken.txt"))
        XCTAssertFalse(result.output.contains("## broken.txt"))
    }

    // MARK: - Hidden File Tests (Fix 13)

    func testHiddenFilesExcludedByDefault() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "visible".write(to: dir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: dir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertTrue(result.output.contains("visible.txt"))
        XCTAssertFalse(result.output.contains(".hidden"))
    }

    func testHiddenFilesIncluded() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try "visible".write(to: dir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: dir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let options = TreeOptions(includeHidden: true, respectGitignore: false)
        let result = try TreeGenerator.generate(directories: [dir], options: options)
        XCTAssertTrue(result.output.contains("visible.txt"))
        XCTAssertTrue(result.output.contains(".hidden"))
    }

    // MARK: - Gitignore Negation (Fix 16)

    func testGitignoreNegationPattern() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Init git repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        try "*.log\n!important.log\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "debug stuff".write(to: dir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "important stuff".write(to: dir.appendingPathComponent("important.log"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir])
        XCTAssertTrue(result.output.contains("important.log"))
        XCTAssertTrue(result.output.contains("important stuff"))
        XCTAssertFalse(result.output.contains("debug stuff"))
    }

    // MARK: - Multiple Directories (Fix 17)

    func testMultipleDirectories() throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        defer {
            cleanup(dir1)
            cleanup(dir2)
        }

        try "content one".write(to: dir1.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try "content two".write(to: dir2.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)

        let result = try TreeGenerator.generate(directories: [dir1, dir2])

        // Both directories' files should appear
        XCTAssertTrue(result.output.contains("content one"))
        XCTAssertTrue(result.output.contains("content two"))

        // Both directory headers should be present
        XCTAssertTrue(result.output.contains("# Directory: \(dir1.lastPathComponent)/"))
        XCTAssertTrue(result.output.contains("# Directory: \(dir2.lastPathComponent)/"))

        XCTAssertEqual(result.filesIncluded, 2)
    }

    // MARK: - Noise Function Unit Tests (Fix 10)

    func testIsNoiseDirectoryRecognizesStandardDirs() {
        XCTAssertTrue(TreeGenerator.isNoiseDirectory(".git"))
        XCTAssertTrue(TreeGenerator.isNoiseDirectory("node_modules"))
        XCTAssertTrue(TreeGenerator.isNoiseDirectory("__pycache__"))
        XCTAssertTrue(TreeGenerator.isNoiseDirectory("target"))
        XCTAssertTrue(TreeGenerator.isNoiseDirectory("mypackage.egg-info"))
    }

    func testIsNoiseDirectoryAllowsNormalDirs() {
        XCTAssertFalse(TreeGenerator.isNoiseDirectory("src"))
        XCTAssertFalse(TreeGenerator.isNoiseDirectory("lib"))
        XCTAssertFalse(TreeGenerator.isNoiseDirectory("docs"))
    }

    func testIsNoiseFileRecognizesStandardFiles() {
        XCTAssertTrue(TreeGenerator.isNoiseFile(".DS_Store"))
        XCTAssertTrue(TreeGenerator.isNoiseFile("Thumbs.db"))
        XCTAssertTrue(TreeGenerator.isNoiseFile("desktop.ini"))
    }

    func testIsNoiseFileAllowsNormalFiles() {
        XCTAssertFalse(TreeGenerator.isNoiseFile("readme.md"))
        XCTAssertFalse(TreeGenerator.isNoiseFile("main.swift"))
    }
}
