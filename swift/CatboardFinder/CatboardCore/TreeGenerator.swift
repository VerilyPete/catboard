import Foundation
import os.log

// MARK: - Types

public struct TreeOptions: Sendable {
    public let maxFileSize: Int
    public let maxTotalSize: Int
    public let includeHidden: Bool
    public let respectGitignore: Bool

    public init(
        maxFileSize: Int = 256 * 1024,
        maxTotalSize: Int = 1024 * 1024,
        includeHidden: Bool = false,
        respectGitignore: Bool = true
    ) {
        self.maxFileSize = maxFileSize
        self.maxTotalSize = maxTotalSize
        self.includeHidden = includeHidden
        self.respectGitignore = respectGitignore
    }
}

public struct TreeResult: Sendable {
    public let output: String
    public let filesIncluded: Int
    public let filesSkipped: Int
    public let totalBytes: Int
    public let truncated: Bool
}

// MARK: - TreeGenerator

public struct TreeGenerator {

    // MARK: - Language Detection

    public static func detectLanguage(_ url: URL) -> String? {
        let filename = url.lastPathComponent

        if filename == "Dockerfile" || filename.hasPrefix("Dockerfile.") {
            return "dockerfile"
        }

        switch filename {
        case "Makefile": return "makefile"
        case "CMakeLists.txt": return "cmake"
        case "Cargo.lock", "poetry.lock": return "toml"
        case ".env": return "dotenv"
        default: break
        }

        let ext = url.pathExtension
        switch ext {
        case "rs": return "rust"
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "tsx"
        case "jsx": return "jsx"
        case "go": return "go"
        case "java": return "java"
        case "swift": return "swift"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "m": return "objectivec"
        case "mm": return "cpp"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "bash"
        case "fish": return "fish"
        case "ps1": return "powershell"
        case "bat", "cmd": return "batch"
        case "yml", "yaml": return "yaml"
        case "json": return "json"
        case "toml": return "toml"
        case "ini", "cfg": return "ini"
        case "md": return "markdown"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss": return "scss"
        case "sql": return "sql"
        case "xml": return "xml"
        case "kt": return "kotlin"
        case "ex", "exs": return "elixir"
        case "erl": return "erlang"
        case "hs": return "haskell"
        case "lua": return "lua"
        case "r", "R": return "r"
        case "pl": return "perl"
        case "php": return "php"
        case "cs": return "csharp"
        case "fs": return "fsharp"
        case "scala": return "scala"
        case "clj": return "clojure"
        case "dart": return "dart"
        case "zig": return "zig"
        case "v": return "v"
        case "nim": return "nim"
        case "nix": return "nix"
        case "tf": return "hcl"
        case "proto": return "protobuf"
        case "graphql", "gql": return "graphql"
        case "vue": return "vue"
        case "svelte": return "svelte"
        case "astro": return "astro"
        case "prisma": return "prisma"
        case "env": return "dotenv"
        default: return nil
        }
    }

    // MARK: - Noise Filtering

    private static let noiseDirs: Set<String> = [
        ".git", "node_modules", "__pycache__", ".venv", "venv",
        "target", "build", "dist", ".next", ".nuxt", ".cache",
        ".tox", ".mypy_cache", ".pytest_cache", ".eggs", ".gradle",
        ".idea", ".vscode", "Pods", ".svn", ".hg", ".terraform",
        ".serverless", ".parcel-cache", ".turbo"
    ]

    private static let noiseFiles: Set<String> = [
        ".DS_Store", "Thumbs.db", "desktop.ini"
    ]

    static func isNoiseDirectory(_ name: String) -> Bool {
        noiseDirs.contains(name) || name.hasSuffix(".egg-info")
    }

    static func isNoiseFile(_ name: String) -> Bool {
        noiseFiles.contains(name)
    }

    // MARK: - Size Formatting

    public static func formatSize(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
        } else if bytes >= 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes)B"
        }
    }

    // MARK: - Backtick Handling

    static func longestBacktickRun(_ s: String) -> Int {
        var maxRun = 0
        var currentRun = 0
        for ch in s {
            if ch == "`" {
                currentRun += 1
                if currentRun > maxRun {
                    maxRun = currentRun
                }
            } else {
                currentRun = 0
            }
        }
        return maxRun
    }

    static func escapeBackticksInName(_ name: String) -> String {
        name.replacingOccurrences(of: "`", with: "\\`")
    }

    // MARK: - File Section Formatting

    static func formatFileSection(relativePath: String, contents: String, url: URL) -> String {
        let escapedPath = escapeBackticksInName(relativePath)
        let lang = detectLanguage(url) ?? ""
        let maxBackticks = longestBacktickRun(contents)
        let fenceLen = maxBackticks >= 3 ? maxBackticks + 1 : 3
        let fence = String(repeating: "`", count: fenceLen)

        var result = "## \(escapedPath)\n\n\(fence)\(lang)\n"
        result += contents
        if !contents.hasSuffix("\n") {
            result += "\n"
        }
        result += fence
        result += "\n"
        return result
    }

    // MARK: - Directory Tree Building

    private indirect enum TreeEntry {
        case file
        case dir([String: TreeEntry])
    }

    private static func insertPath(_ tree: inout [String: TreeEntry], components: [String], isDir: Bool) {
        guard !components.isEmpty else { return }
        let name = components[0]
        if components.count == 1 {
            if isDir {
                if tree[name] == nil {
                    tree[name] = .dir([:])
                }
            } else {
                if tree[name] == nil {
                    tree[name] = .file
                }
            }
        } else {
            if tree[name] == nil {
                tree[name] = .dir([:])
            }
            if case .dir(var subtree) = tree[name] {
                insertPath(&subtree, components: Array(components.dropFirst()), isDir: isDir)
                tree[name] = .dir(subtree)
            }
        }
    }

    private static func renderTree(_ tree: [String: TreeEntry], prefix: String, output: inout String) {
        let sortedEntries = tree.sorted { $0.key < $1.key }
        for (i, (name, entry)) in sortedEntries.enumerated() {
            let isLast = i == sortedEntries.count - 1
            let connector = isLast ? "\u{2514}\u{2500}\u{2500} " : "\u{251C}\u{2500}\u{2500} "
            let childPrefix = isLast ? "\(prefix)    " : "\(prefix)\u{2502}   "

            switch entry {
            case .file:
                output += "\(prefix)\(connector)\(name)\n"
            case .dir(let subtree):
                output += "\(prefix)\(connector)\(name)/\n"
                renderTree(subtree, prefix: childPrefix, output: &output)
            }
        }
    }

    static func buildDirectoryListing(entries: [(path: String, isDir: Bool)], rootName: String) -> String {
        var tree: [String: TreeEntry] = [:]

        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            insertPath(&tree, components: components, isDir: entry.isDir)
        }

        var output = "\(rootName)/\n"
        renderTree(tree, prefix: "", output: &output)
        return output
    }

    // MARK: - Gitignore Parsing

    struct GitignoreRule {
        let pattern: String
        let isNegation: Bool
        let isDirectoryOnly: Bool
        let compiledRegex: NSRegularExpression?
    }

    static func parseGitignore(contents: String) -> [GitignoreRule] {
        contents.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                return nil
            }

            var pattern = trimmed
            let isNegation = pattern.hasPrefix("!")
            if isNegation {
                pattern = String(pattern.dropFirst())
            }

            let isDirectoryOnly = pattern.hasSuffix("/")
            if isDirectoryOnly {
                pattern = String(pattern.dropLast())
            }

            let compiledRegex: NSRegularExpression?
            if pattern.contains("*") {
                let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"
                compiledRegex = try? NSRegularExpression(pattern: regexPattern)
            } else {
                compiledRegex = nil
            }

            return GitignoreRule(pattern: pattern, isNegation: isNegation, isDirectoryOnly: isDirectoryOnly, compiledRegex: compiledRegex)
        }
    }

    static func matchesGitignorePattern(_ pattern: String, path: String, isDirectory: Bool, compiledRegex: NSRegularExpression? = nil) -> Bool {
        // Handle ** prefix patterns like **/pattern
        if pattern.hasPrefix("**/") {
            let rest = String(pattern.dropFirst(3))
            if matchSimplePattern(rest, path: path) { return true }
            let components = path.split(separator: "/")
            for i in 0..<components.count {
                let suffix = components[i...].joined(separator: "/")
                if matchSimplePattern(rest, path: suffix) { return true }
            }
            return false
        }

        // Handle ** suffix patterns like pattern/**
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return path.hasPrefix(prefix + "/") || path == prefix
        }

        // Handle patterns with path separator — match from root
        if pattern.contains("/") {
            return matchSimplePattern(pattern, path: path, compiledRegex: compiledRegex)
        }

        // No separator — match against just the filename
        let filename = (path as NSString).lastPathComponent
        return matchSimplePattern(pattern, path: filename, compiledRegex: compiledRegex)
    }

    private static func matchSimplePattern(_ pattern: String, path: String, compiledRegex: NSRegularExpression? = nil) -> Bool {
        if pattern == path { return true }

        if pattern.contains("*") {
            let regex: NSRegularExpression?
            if let compiledRegex = compiledRegex {
                regex = compiledRegex
            } else {
                let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"
                regex = try? NSRegularExpression(pattern: regexPattern)
            }
            if let regex = regex,
               regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil {
                return true
            }
        }

        return false
    }

    static func isIgnoredByGitignore(
        relativePath: String,
        isDirectory: Bool,
        rules: [(basePath: String, rules: [GitignoreRule])]
    ) -> Bool {
        var ignored = false
        for (basePath, ruleSet) in rules {
            // Compute path relative to the gitignore's location
            let pathForMatching: String
            if basePath.isEmpty {
                pathForMatching = relativePath
            } else if relativePath.hasPrefix(basePath + "/") {
                pathForMatching = String(relativePath.dropFirst(basePath.count + 1))
            } else {
                continue
            }

            for rule in ruleSet {
                if rule.isDirectoryOnly && !isDirectory {
                    continue
                }
                if matchesGitignorePattern(rule.pattern, path: pathForMatching, isDirectory: isDirectory, compiledRegex: rule.compiledRegex) {
                    ignored = !rule.isNegation
                }
            }
        }
        return ignored
    }

    // MARK: - Gitignore Collection

    private static func collectGitignoreRules(rootURL: URL, fm: FileManager) -> [(basePath: String, rules: [GitignoreRule])] {
        var allRules: [(basePath: String, rules: [GitignoreRule])] = []

        // Root .gitignore
        let rootGitignore = rootURL.appendingPathComponent(".gitignore")
        if let contents = try? String(contentsOf: rootGitignore, encoding: .utf8) {
            allRules.append((basePath: "", rules: parseGitignore(contents: contents)))
        }

        // Walk subdirectories for nested .gitignore files
        if let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            while let itemURL = enumerator.nextObject() as? URL {
                guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else { continue }

                let dirName = itemURL.lastPathComponent
                if isNoiseDirectory(dirName) {
                    enumerator.skipDescendants()
                    continue
                }

                let nestedGitignore = itemURL.appendingPathComponent(".gitignore")
                if let contents = try? String(contentsOf: nestedGitignore, encoding: .utf8) {
                    let relative = itemURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                    allRules.append((basePath: relative, rules: parseGitignore(contents: contents)))
                }
            }
        }

        return allRules
    }

    // MARK: - Main Entry Point

    public static func generate(directories: [URL], options: TreeOptions = TreeOptions()) throws -> TreeResult {
        let fm = FileManager.default

        for dir in directories {
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: dir.path, isDirectory: &isDir) {
                throw CatboardError.fileNotFound(dir)
            }
            if !isDir.boolValue {
                throw CatboardError.extractionFailed(dir, "Not a directory: \(dir.lastPathComponent)")
            }
        }

        // Per-directory collected data
        struct DirectoryData {
            let rootName: String
            var treeEntries: [(path: String, isDir: Bool)] = []
            var fileURLs: [(url: URL, relativePath: String)] = []
            var skipNotes: [String] = []
            var symlinksSkipped: Int = 0
        }

        // Pass 1: Walk all directories collecting entries
        var directoryDataList: [DirectoryData] = []

        for dir in directories {
            // Use realpath to fully resolve symlinks (including /var -> /private/var on macOS)
            let resolvedDir: URL
            if let realPath = realpath(dir.path, nil) {
                resolvedDir = URL(fileURLWithPath: String(cString: realPath))
                free(realPath)
            } else {
                resolvedDir = dir.resolvingSymlinksInPath()
            }
            let rootName = dir.lastPathComponent

            let gitignoreRules: [(basePath: String, rules: [GitignoreRule])]
            if options.respectGitignore {
                gitignoreRules = collectGitignoreRules(rootURL: resolvedDir, fm: fm)
            } else {
                gitignoreRules = []
            }

            var dirData = DirectoryData(rootName: rootName)

            guard let enumerator = fm.enumerator(
                at: resolvedDir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
                options: options.includeHidden ? [] : [.skipsHiddenFiles]
            ) else { continue }

            while let itemURL = enumerator.nextObject() as? URL {
                let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])

                let name = itemURL.lastPathComponent
                let relativePath = itemURL.path.hasPrefix(resolvedDir.path + "/")
                    ? String(itemURL.path.dropFirst(resolvedDir.path.count + 1))
                    : itemURL.path

                let isDirectory = resourceValues?.isDirectory ?? false
                // Use FileManager.attributesOfItem which calls lstat (does not follow symlinks)
                let fileAttributes = try? fm.attributesOfItem(atPath: itemURL.path)
                let isSymlink = (fileAttributes?[.type] as? FileAttributeType) == .typeSymbolicLink

                // Check for symlinks BEFORE adding to tree entries
                if isSymlink {
                    // Add symlink to tree listing as a file (not directory)
                    dirData.treeEntries.append((path: relativePath, isDir: false))
                    dirData.skipNotes.append("> Skipped: \(relativePath) (symlink)")
                    dirData.symlinksSkipped += 1
                    // Prevent traversal into symlinked directories
                    if isDirectory {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                // Skip noise
                if isDirectory {
                    if isNoiseDirectory(name) {
                        enumerator.skipDescendants()
                        continue
                    }
                } else {
                    if isNoiseFile(name) {
                        continue
                    }
                }

                // Skip gitignored
                if options.respectGitignore && !gitignoreRules.isEmpty {
                    if isIgnoredByGitignore(relativePath: relativePath, isDirectory: isDirectory, rules: gitignoreRules) {
                        if isDirectory {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                }

                // Add to tree listing
                dirData.treeEntries.append((path: relativePath, isDir: isDirectory))

                // Only process regular files for content
                if !isDirectory {
                    dirData.fileURLs.append((url: itemURL, relativePath: relativePath))
                }
            }

            dirData.fileURLs.sort { $0.relativePath < $1.relativePath }
            directoryDataList.append(dirData)
        }

        // Pass 2: Process files and assemble output per-directory
        var filesIncluded = 0
        var filesSkipped = 0
        var totalBytes = 0
        var truncated = false
        var outputParts: [String] = []

        for var dirData in directoryDataList {
            filesSkipped += dirData.symlinksSkipped
            var fileSections: [String] = []

            for (fileURL, relativePath) in dirData.fileURLs {
                if truncated {
                    filesSkipped += 1
                    continue
                }

                let attributes: [FileAttributeKey: Any]
                do {
                    attributes = try fm.attributesOfItem(atPath: fileURL.path)
                } catch {
                    dirData.skipNotes.append("> Skipped: \(relativePath) (permission denied)")
                    filesSkipped += 1
                    continue
                }

                let fileSize = (attributes[.size] as? Int) ?? 0

                if fileSize > options.maxFileSize {
                    dirData.skipNotes.append("> Skipped: \(relativePath) (\(formatSize(fileSize)) exceeds \(formatSize(options.maxFileSize)) limit)")
                    filesSkipped += 1
                    continue
                }

                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    dirData.skipNotes.append("> Skipped: \(relativePath) (read error)")
                    filesSkipped += 1
                    continue
                }

                if !data.isEmpty && FileReader.isBinary(data: data) {
                    dirData.skipNotes.append("> Skipped: \(relativePath) (binary file)")
                    filesSkipped += 1
                    continue
                }

                guard let contents = String(data: data, encoding: .utf8) else {
                    dirData.skipNotes.append("> Skipped: \(relativePath) (encoding error)")
                    filesSkipped += 1
                    continue
                }

                // Check total size limit using decoded string byte count
                if totalBytes + contents.utf8.count > options.maxTotalSize {
                    truncated = true
                    dirData.skipNotes.append("> Truncated: output exceeded \(formatSize(options.maxTotalSize)) limit")
                    filesSkipped += 1
                    continue
                }

                totalBytes += contents.utf8.count
                filesIncluded += 1
                fileSections.append(formatFileSection(relativePath: relativePath, contents: contents, url: fileURL))
            }

            // Build output for this directory
            var output = "# Directory: \(dirData.rootName)/\n\n"
            output += "## Structure\n\n```\n"

            let sortedTreeEntries = dirData.treeEntries.sorted { $0.path < $1.path }
            output += buildDirectoryListing(entries: sortedTreeEntries, rootName: dirData.rootName)
            output += "```\n\n"

            for section in fileSections {
                output += section
                output += "\n"
            }

            for note in dirData.skipNotes {
                output += note
                output += "\n"
            }

            if !output.isEmpty {
                output += "\n"
            }

            outputParts.append(output)
        }

        var combinedOutput = outputParts.joined(separator: "\n")
        combinedOutput += "---\n*\(filesIncluded) files included, \(filesSkipped) skipped, \(formatSize(totalBytes)) total*\n"

        return TreeResult(
            output: combinedOutput,
            filesIncluded: filesIncluded,
            filesSkipped: filesSkipped,
            totalBytes: totalBytes,
            truncated: truncated
        )
    }
}
