use crate::error::{CatboardError, Result};
use crate::file::is_binary_file;
use ignore::WalkBuilder;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub struct TreeOptions {
    pub max_file_size: usize,
    pub max_total_size: usize,
    pub include_hidden: bool,
    pub respect_gitignore: bool,
}

impl Default for TreeOptions {
    fn default() -> Self {
        Self {
            max_file_size: 256 * 1024,
            max_total_size: 1024 * 1024,
            include_hidden: false,
            respect_gitignore: true,
        }
    }
}

pub struct TreeResult {
    pub output: String,
    pub files_included: usize,
    pub files_skipped: usize,
    pub total_bytes: usize,
    pub truncated: bool,
}

pub fn detect_language(path: &Path) -> Option<&'static str> {
    let filename = path.file_name()?.to_str()?;

    if filename == "Dockerfile" || filename.starts_with("Dockerfile.") {
        return Some("dockerfile");
    }

    match filename {
        "Makefile" => return Some("makefile"),
        "CMakeLists.txt" => return Some("cmake"),
        "Cargo.lock" | "poetry.lock" => return Some("toml"),
        ".env" => return Some("dotenv"),
        _ => {}
    }

    match path.extension()?.to_str()? {
        "rs" => Some("rust"),
        "py" => Some("python"),
        "js" => Some("javascript"),
        "ts" => Some("typescript"),
        "tsx" => Some("tsx"),
        "jsx" => Some("jsx"),
        "go" => Some("go"),
        "java" => Some("java"),
        "swift" => Some("swift"),
        "c" | "h" => Some("c"),
        "cpp" | "cc" | "cxx" | "hpp" => Some("cpp"),
        "m" => Some("objectivec"),
        "mm" => Some("cpp"),
        "rb" => Some("ruby"),
        "sh" | "bash" | "zsh" => Some("bash"),
        "fish" => Some("fish"),
        "ps1" => Some("powershell"),
        "bat" | "cmd" => Some("batch"),
        "yml" | "yaml" => Some("yaml"),
        "json" => Some("json"),
        "toml" => Some("toml"),
        "ini" | "cfg" => Some("ini"),
        "md" => Some("markdown"),
        "html" | "htm" => Some("html"),
        "css" => Some("css"),
        "scss" => Some("scss"),
        "sql" => Some("sql"),
        "xml" => Some("xml"),
        "kt" => Some("kotlin"),
        "ex" | "exs" => Some("elixir"),
        "erl" => Some("erlang"),
        "hs" => Some("haskell"),
        "lua" => Some("lua"),
        "r" | "R" => Some("r"),
        "pl" => Some("perl"),
        "php" => Some("php"),
        "cs" => Some("csharp"),
        "fs" => Some("fsharp"),
        "scala" => Some("scala"),
        "clj" => Some("clojure"),
        "dart" => Some("dart"),
        "zig" => Some("zig"),
        "v" => Some("v"),
        "nim" => Some("nim"),
        "nix" => Some("nix"),
        "tf" => Some("hcl"),
        "proto" => Some("protobuf"),
        "graphql" | "gql" => Some("graphql"),
        "vue" => Some("vue"),
        "svelte" => Some("svelte"),
        "astro" => Some("astro"),
        "prisma" => Some("prisma"),
        "env" => Some("dotenv"),
        _ => None,
    }
}

const NOISE_DIRS: &[&str] = &[
    ".git",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    "target",
    "build",
    "dist",
    ".next",
    ".nuxt",
    ".cache",
    ".tox",
    ".mypy_cache",
    ".pytest_cache",
    ".eggs",
    ".gradle",
    ".idea",
    ".vscode",
    "Pods",
    ".svn",
    ".hg",
    ".terraform",
    ".serverless",
    ".parcel-cache",
    ".turbo",
];

pub fn is_noise_directory(name: &str) -> bool {
    NOISE_DIRS.contains(&name) || name.ends_with(".egg-info")
}

const NOISE_FILES: &[&str] = &[".DS_Store", "Thumbs.db", "desktop.ini"];

pub fn is_noise_file(name: &str) -> bool {
    NOISE_FILES.contains(&name)
}

fn longest_backtick_run(s: &str) -> usize {
    let mut max_run = 0;
    let mut current_run = 0;
    for ch in s.chars() {
        if ch == '`' {
            current_run += 1;
            if current_run > max_run {
                max_run = current_run;
            }
        } else {
            current_run = 0;
        }
    }
    max_run
}

fn escape_backticks_in_name(name: &str) -> String {
    name.replace('`', "\\`")
}

pub fn format_file_section(path: &Path, contents: &str, root_path: &Path) -> String {
    let relative = path.strip_prefix(root_path).unwrap_or(path);
    let display_path = relative.to_string_lossy();
    let escaped_path = escape_backticks_in_name(&display_path);

    let lang = detect_language(path).unwrap_or("");
    let max_backticks = longest_backtick_run(contents);
    let fence_len = if max_backticks >= 3 {
        max_backticks + 1
    } else {
        3
    };
    let fence: String = "`".repeat(fence_len);

    let mut result = format!("## {}\n\n{}{}\n", escaped_path, fence, lang);
    result.push_str(contents);
    if !contents.ends_with('\n') {
        result.push('\n');
    }
    result.push_str(&fence);
    result.push('\n');
    result
}

#[derive(Debug)]
enum TreeEntry {
    File,
    Dir(BTreeMap<String, TreeEntry>),
}

fn insert_path(tree: &mut BTreeMap<String, TreeEntry>, components: &[&str], is_dir: bool) {
    if components.is_empty() {
        return;
    }
    let name = components[0];
    if components.len() == 1 {
        if is_dir {
            tree.entry(name.to_string())
                .or_insert(TreeEntry::Dir(BTreeMap::new()));
        } else {
            tree.entry(name.to_string()).or_insert(TreeEntry::File);
        }
    } else {
        let entry = tree
            .entry(name.to_string())
            .or_insert(TreeEntry::Dir(BTreeMap::new()));
        if let TreeEntry::Dir(ref mut subtree) = entry {
            insert_path(subtree, &components[1..], is_dir);
        }
    }
}

fn render_tree(tree: &BTreeMap<String, TreeEntry>, prefix: &str, output: &mut String) {
    let entries: Vec<_> = tree.iter().collect();
    for (i, (name, entry)) in entries.iter().enumerate() {
        let is_last = i == entries.len() - 1;
        let connector = if is_last { "└── " } else { "├── " };
        let child_prefix = if is_last {
            format!("{}    ", prefix)
        } else {
            format!("{}│   ", prefix)
        };

        match entry {
            TreeEntry::File => {
                output.push_str(&format!("{}{}{}\n", prefix, connector, name));
            }
            TreeEntry::Dir(subtree) => {
                output.push_str(&format!("{}{}{}/\n", prefix, connector, name));
                render_tree(subtree, &child_prefix, output);
            }
        }
    }
}

pub fn build_directory_listing(entries: &[PathBuf], root_path: &Path) -> String {
    let root_name = root_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| root_path.to_string_lossy().to_string());

    let mut tree: BTreeMap<String, TreeEntry> = BTreeMap::new();

    for entry in entries {
        if let Ok(relative) = entry.strip_prefix(root_path) {
            let components: Vec<&str> = relative
                .components()
                .filter_map(|c| c.as_os_str().to_str())
                .collect();
            if !components.is_empty() {
                let is_dir = entry.is_dir();
                insert_path(&mut tree, &components, is_dir);
            }
        }
    }

    let mut output = format!("{}/\n", root_name);
    render_tree(&tree, "", &mut output);
    output
}

pub fn format_size(bytes: usize) -> String {
    if bytes >= 1024 * 1024 {
        format!("{:.1}MB", bytes as f64 / (1024.0 * 1024.0))
    } else if bytes >= 1024 {
        format!("{:.1}KB", bytes as f64 / 1024.0)
    } else {
        format!("{}B", bytes)
    }
}

pub fn format_stats_line(included: usize, skipped: usize, total_bytes: usize) -> String {
    format!(
        "---\n*{} files included, {} skipped, {} total*",
        included,
        skipped,
        format_size(total_bytes)
    )
}

pub fn generate_tree(dirs: &[PathBuf], options: &TreeOptions) -> Result<TreeResult> {
    let mut canonical_dirs: Vec<(PathBuf, PathBuf)> = Vec::new();
    for dir in dirs {
        if !dir.exists() {
            return Err(CatboardError::DirectoryNotFound(dir.clone()));
        }
        if !dir.is_dir() {
            return Err(CatboardError::NotADirectory(dir.clone()));
        }
        let canonical = dir
            .canonicalize()
            .map_err(|_| CatboardError::DirectoryNotFound(dir.clone()))?;
        canonical_dirs.push((dir.clone(), canonical));
    }

    let mut all_entries: Vec<PathBuf> = Vec::new();
    let mut file_sections: Vec<String> = Vec::new();
    let mut skip_notes: Vec<String> = Vec::new();
    let mut files_included: usize = 0;
    let mut files_skipped: usize = 0;
    let mut total_bytes: usize = 0;
    let mut truncated = false;

    for (_dir, canonical_dir) in &canonical_dirs {
        let canonical_dir = canonical_dir.clone();

        let mut builder = WalkBuilder::new(&canonical_dir);
        builder
            .hidden(!options.include_hidden)
            .git_ignore(options.respect_gitignore)
            .git_global(options.respect_gitignore)
            .git_exclude(options.respect_gitignore)
            .follow_links(false)
            .sort_by_file_name(|a, b| a.cmp(b))
            .filter_entry(|entry| {
                if let Some(name) = entry.file_name().to_str() {
                    if entry.file_type().is_some_and(|ft| ft.is_dir()) {
                        return !is_noise_directory(name);
                    }
                    return !is_noise_file(name);
                }
                true
            });

        let walker = builder.build();

        for result in walker {
            let entry = match result {
                Ok(e) => e,
                Err(e) => {
                    skip_notes.push(format!("> Skipped: {}", e));
                    files_skipped += 1;
                    continue;
                }
            };

            let path = entry.path().to_path_buf();

            if path == canonical_dir {
                continue;
            }

            let file_type = match entry.file_type() {
                Some(ft) => ft,
                None => continue,
            };

            all_entries.push(path.clone());

            if !file_type.is_file() {
                continue;
            }

            if truncated {
                files_skipped += 1;
                continue;
            }

            let relative = path.strip_prefix(&canonical_dir).unwrap_or(&path);
            let relative_display = relative.to_string_lossy();

            let metadata = match fs::metadata(&path) {
                Ok(m) => m,
                Err(_) => {
                    skip_notes.push(format!(
                        "> Skipped: {} (permission denied)",
                        relative_display
                    ));
                    files_skipped += 1;
                    continue;
                }
            };

            let file_size = metadata.len() as usize;

            if file_size > options.max_file_size {
                skip_notes.push(format!(
                    "> Skipped: {} ({} exceeds {} limit)",
                    relative_display,
                    format_size(file_size),
                    format_size(options.max_file_size)
                ));
                files_skipped += 1;
                continue;
            }

            match is_binary_file(&path) {
                Ok(true) => {
                    skip_notes.push(format!("> Skipped: {} (binary file)", relative_display));
                    files_skipped += 1;
                    continue;
                }
                Err(_) => {
                    skip_notes.push(format!(
                        "> Skipped: {} (permission denied)",
                        relative_display
                    ));
                    files_skipped += 1;
                    continue;
                }
                Ok(false) => {}
            }

            if total_bytes + file_size > options.max_total_size {
                truncated = true;
                skip_notes.push(format!(
                    "> Truncated: output exceeded {} limit",
                    format_size(options.max_total_size)
                ));
                files_skipped += 1;
                continue;
            }

            let contents = match fs::read_to_string(&path) {
                Ok(c) => c,
                Err(_) => {
                    skip_notes.push(format!("> Skipped: {} (read error)", relative_display));
                    files_skipped += 1;
                    continue;
                }
            };

            total_bytes += contents.len();
            files_included += 1;
            file_sections.push(format_file_section(&path, &contents, &canonical_dir));
        }
    }

    let mut output = String::new();

    for (dir, canonical_dir) in &canonical_dirs {
        let dir_name = dir
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| dir.to_string_lossy().to_string());

        output.push_str(&format!("# Directory: {}/\n\n", dir_name));
        output.push_str("## Structure\n\n```\n");

        let dir_entries: Vec<PathBuf> = all_entries
            .iter()
            .filter(|e| e.starts_with(canonical_dir))
            .cloned()
            .collect();

        output.push_str(&build_directory_listing(&dir_entries, canonical_dir));
        output.push_str("```\n\n");
    }

    for section in &file_sections {
        output.push_str(section);
        output.push('\n');
    }

    for note in &skip_notes {
        output.push_str(note);
        output.push('\n');
    }

    if !output.is_empty() {
        output.push('\n');
    }

    output.push_str(&format_stats_line(
        files_included,
        files_skipped,
        total_bytes,
    ));
    output.push('\n');

    Ok(TreeResult {
        output,
        files_included,
        files_skipped,
        total_bytes,
        truncated,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use std::io::Write;
    use tempfile::TempDir;

    // Step 4: detect_language tests
    #[test]
    fn test_detect_language_rust() {
        assert_eq!(detect_language(Path::new("main.rs")), Some("rust"));
    }

    #[test]
    fn test_detect_language_python() {
        assert_eq!(detect_language(Path::new("script.py")), Some("python"));
    }

    #[test]
    fn test_detect_language_javascript() {
        assert_eq!(detect_language(Path::new("app.js")), Some("javascript"));
    }

    #[test]
    fn test_detect_language_typescript() {
        assert_eq!(detect_language(Path::new("app.ts")), Some("typescript"));
    }

    #[test]
    fn test_detect_language_tsx() {
        assert_eq!(detect_language(Path::new("Component.tsx")), Some("tsx"));
    }

    #[test]
    fn test_detect_language_dockerfile() {
        assert_eq!(detect_language(Path::new("Dockerfile")), Some("dockerfile"));
    }

    #[test]
    fn test_detect_language_dockerfile_variant() {
        assert_eq!(
            detect_language(Path::new("Dockerfile.prod")),
            Some("dockerfile")
        );
    }

    #[test]
    fn test_detect_language_makefile() {
        assert_eq!(detect_language(Path::new("Makefile")), Some("makefile"));
    }

    #[test]
    fn test_detect_language_cmake() {
        assert_eq!(detect_language(Path::new("CMakeLists.txt")), Some("cmake"));
    }

    #[test]
    fn test_detect_language_cargo_lock() {
        assert_eq!(detect_language(Path::new("Cargo.lock")), Some("toml"));
    }

    #[test]
    fn test_detect_language_poetry_lock() {
        assert_eq!(detect_language(Path::new("poetry.lock")), Some("toml"));
    }

    #[test]
    fn test_detect_language_unknown() {
        assert_eq!(detect_language(Path::new("data.xyz")), None);
    }

    #[test]
    fn test_detect_language_no_extension() {
        assert_eq!(detect_language(Path::new("README")), None);
    }

    #[test]
    fn test_detect_language_yaml() {
        assert_eq!(detect_language(Path::new("config.yml")), Some("yaml"));
        assert_eq!(detect_language(Path::new("config.yaml")), Some("yaml"));
    }

    #[test]
    fn test_detect_language_c_header() {
        assert_eq!(detect_language(Path::new("header.h")), Some("c"));
    }

    #[test]
    fn test_detect_language_cpp() {
        assert_eq!(detect_language(Path::new("main.cpp")), Some("cpp"));
        assert_eq!(detect_language(Path::new("main.cc")), Some("cpp"));
        assert_eq!(detect_language(Path::new("main.hpp")), Some("cpp"));
    }

    #[test]
    fn test_detect_language_swift() {
        assert_eq!(detect_language(Path::new("App.swift")), Some("swift"));
    }

    #[test]
    fn test_detect_language_go() {
        assert_eq!(detect_language(Path::new("main.go")), Some("go"));
    }

    #[test]
    fn test_detect_language_env() {
        assert_eq!(detect_language(Path::new(".env")), Some("dotenv"));
    }

    // Step 5: is_noise_directory / is_noise_file tests
    #[test]
    fn test_is_noise_directory_git() {
        assert!(is_noise_directory(".git"));
    }

    #[test]
    fn test_is_noise_directory_node_modules() {
        assert!(is_noise_directory("node_modules"));
    }

    #[test]
    fn test_is_noise_directory_target() {
        assert!(is_noise_directory("target"));
    }

    #[test]
    fn test_is_noise_directory_pycache() {
        assert!(is_noise_directory("__pycache__"));
    }

    #[test]
    fn test_is_noise_directory_egg_info() {
        assert!(is_noise_directory("mypackage.egg-info"));
    }

    #[test]
    fn test_is_not_noise_directory() {
        assert!(!is_noise_directory("src"));
        assert!(!is_noise_directory("lib"));
        assert!(!is_noise_directory("tests"));
    }

    #[test]
    fn test_is_noise_file_ds_store() {
        assert!(is_noise_file(".DS_Store"));
    }

    #[test]
    fn test_is_noise_file_thumbs() {
        assert!(is_noise_file("Thumbs.db"));
    }

    #[test]
    fn test_is_noise_file_desktop_ini() {
        assert!(is_noise_file("desktop.ini"));
    }

    #[test]
    fn test_is_not_noise_file() {
        assert!(!is_noise_file("README.md"));
        assert!(!is_noise_file("main.rs"));
    }

    // Step 6: format_file_section tests
    #[test]
    fn test_format_file_section_basic() {
        let root = Path::new("/project");
        let path = Path::new("/project/src/main.rs");
        let contents = "fn main() {}\n";
        let result = format_file_section(path, contents, root);
        assert!(result.contains("## src/main.rs"));
        assert!(result.contains("```rust"));
        assert!(result.contains("fn main() {}"));
    }

    #[test]
    fn test_format_file_section_unknown_extension() {
        let root = Path::new("/project");
        let path = Path::new("/project/data.xyz");
        let contents = "some data\n";
        let result = format_file_section(path, contents, root);
        assert!(result.contains("## data.xyz"));
        assert!(result.contains("```\n"));
    }

    #[test]
    fn test_format_file_section_triple_backticks_in_content() {
        let root = Path::new("/project");
        let path = Path::new("/project/README.md");
        let contents = "Some text\n```rust\ncode\n```\n";
        let result = format_file_section(path, contents, root);
        assert!(result.contains("````"));
    }

    #[test]
    fn test_format_file_section_backtick_in_filename() {
        let root = Path::new("/project");
        let path = Path::new("/project/file`name.rs");
        let contents = "code\n";
        let result = format_file_section(path, contents, root);
        assert!(result.contains("## file\\`name.rs"));
    }

    // Step 7: build_directory_listing tests
    #[test]
    fn test_build_directory_listing_single_file() {
        let root = Path::new("/project/src");
        let entries = vec![PathBuf::from("/project/src/main.rs")];
        let result = build_directory_listing(&entries, root);
        assert!(result.contains("src/"));
        assert!(result.contains("└── main.rs"));
    }

    #[test]
    fn test_build_directory_listing_nested() {
        let dir = TempDir::new().unwrap();
        let sub = dir.path().join("sub");
        fs::create_dir(&sub).unwrap();
        fs::write(dir.path().join("lib.rs"), "").unwrap();
        fs::write(sub.join("mod.rs"), "").unwrap();

        let entries = vec![
            dir.path().join("lib.rs"),
            dir.path().join("sub"),
            dir.path().join("sub/mod.rs"),
        ];
        let result = build_directory_listing(&entries, dir.path());
        assert!(result.contains("├──"));
        assert!(result.contains("└──"));
        assert!(result.contains("sub/"));
    }

    #[test]
    fn test_build_directory_listing_empty() {
        let root = Path::new("/project/empty");
        let entries: Vec<PathBuf> = vec![];
        let result = build_directory_listing(&entries, root);
        assert!(result.contains("empty/"));
    }

    // Step 8: format_size and format_stats_line tests
    #[test]
    fn test_format_size_bytes() {
        assert_eq!(format_size(42), "42B");
    }

    #[test]
    fn test_format_size_kilobytes() {
        assert_eq!(format_size(4096), "4.0KB");
    }

    #[test]
    fn test_format_size_megabytes() {
        assert_eq!(format_size(2 * 1024 * 1024), "2.0MB");
    }

    #[test]
    fn test_format_size_fractional_kb() {
        assert_eq!(format_size(1536), "1.5KB");
    }

    #[test]
    fn test_format_stats_line() {
        let result = format_stats_line(3, 2, 4096);
        assert_eq!(result, "---\n*3 files included, 2 skipped, 4.0KB total*");
    }

    // Step 9: generate_tree tests
    #[test]
    fn test_generate_tree_single_file() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("hello.txt"), "world").unwrap();
        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 1);
        assert_eq!(result.files_skipped, 0);
        assert!(!result.truncated);
        assert!(result.output.contains("hello.txt"));
        assert!(result.output.contains("world"));
    }

    #[test]
    fn test_generate_tree_nested_directories() {
        let dir = TempDir::new().unwrap();
        fs::create_dir_all(dir.path().join("a/b/c")).unwrap();
        fs::write(dir.path().join("a/one.rs"), "fn one() {}").unwrap();
        fs::write(dir.path().join("a/b/two.rs"), "fn two() {}").unwrap();
        fs::write(dir.path().join("a/b/c/three.rs"), "fn three() {}").unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 3);
        assert!(result.output.contains("fn one()"));
        assert!(result.output.contains("fn two()"));
        assert!(result.output.contains("fn three()"));
    }

    #[test]
    fn test_generate_tree_binary_file_skipped() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("text.txt"), "hello").unwrap();
        let mut bin = File::create(dir.path().join("binary.bin")).unwrap();
        bin.write_all(&[0x00, 0x01, 0x02]).unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 1);
        assert_eq!(result.files_skipped, 1);
        assert!(result.output.contains("Skipped"));
        assert!(result.output.contains("binary"));
    }

    #[test]
    fn test_generate_tree_empty_directory() {
        let dir = TempDir::new().unwrap();
        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 0);
        assert!(result.output.contains("## Structure"));
        assert!(result.output.contains("0 files included"));
    }

    #[test]
    fn test_generate_tree_max_file_size_exceeded() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("small.txt"), "tiny").unwrap();
        fs::write(dir.path().join("big.txt"), "x".repeat(1000)).unwrap();

        let options = TreeOptions {
            max_file_size: 100,
            ..TreeOptions::default()
        };
        let result = generate_tree(&[dir.path().to_path_buf()], &options).unwrap();
        assert_eq!(result.files_included, 1);
        assert_eq!(result.files_skipped, 1);
        assert!(result.output.contains("Skipped"));
        assert!(result.output.contains("exceeds"));
    }

    #[test]
    fn test_generate_tree_max_total_size_exceeded() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("a.txt"), "a".repeat(600)).unwrap();
        fs::write(dir.path().join("b.txt"), "b".repeat(600)).unwrap();

        let options = TreeOptions {
            max_total_size: 800,
            ..TreeOptions::default()
        };
        let result = generate_tree(&[dir.path().to_path_buf()], &options).unwrap();
        assert!(result.truncated);
        assert!(result.output.contains("Truncated"));
    }

    fn init_git_repo(dir: &Path) {
        std::process::Command::new("git")
            .args(["init"])
            .current_dir(dir)
            .output()
            .expect("git init failed");
    }

    #[test]
    fn test_generate_tree_gitignore_respected() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());
        fs::write(dir.path().join(".gitignore"), "ignored.txt\n").unwrap();
        fs::write(dir.path().join("ignored.txt"), "secret").unwrap();
        fs::write(dir.path().join("visible.txt"), "public").unwrap();

        let options = TreeOptions {
            respect_gitignore: true,
            ..TreeOptions::default()
        };
        let result = generate_tree(&[dir.path().to_path_buf()], &options).unwrap();
        assert!(result.output.contains("public"));
        assert!(!result.output.contains("secret"));
    }

    #[test]
    fn test_generate_tree_no_gitignore() {
        let dir = TempDir::new().unwrap();
        init_git_repo(dir.path());
        fs::write(dir.path().join(".gitignore"), "ignored.txt\n").unwrap();
        fs::write(dir.path().join("ignored.txt"), "secret").unwrap();
        fs::write(dir.path().join("visible.txt"), "public").unwrap();

        let options = TreeOptions {
            respect_gitignore: false,
            include_hidden: true,
            ..TreeOptions::default()
        };
        let result = generate_tree(&[dir.path().to_path_buf()], &options).unwrap();
        assert!(result.output.contains("secret"));
        assert!(result.output.contains("public"));
    }

    #[test]
    fn test_generate_tree_noise_dirs_skipped_even_without_gitignore() {
        let dir = TempDir::new().unwrap();
        fs::create_dir_all(dir.path().join("node_modules")).unwrap();
        fs::write(dir.path().join("node_modules/package.json"), "{}").unwrap();
        fs::write(dir.path().join("app.js"), "console.log('hi')").unwrap();

        let options = TreeOptions {
            respect_gitignore: false,
            ..TreeOptions::default()
        };
        let result = generate_tree(&[dir.path().to_path_buf()], &options).unwrap();
        assert!(result.output.contains("app.js"));
        assert!(!result.output.contains("node_modules"));
    }

    #[test]
    fn test_generate_tree_multiple_root_directories() {
        let dir1 = TempDir::new().unwrap();
        let dir2 = TempDir::new().unwrap();
        fs::write(dir1.path().join("one.txt"), "first").unwrap();
        fs::write(dir2.path().join("two.txt"), "second").unwrap();

        let result = generate_tree(
            &[dir1.path().to_path_buf(), dir2.path().to_path_buf()],
            &TreeOptions::default(),
        )
        .unwrap();
        assert_eq!(result.files_included, 2);
        assert!(result.output.contains("first"));
        assert!(result.output.contains("second"));
    }

    #[test]
    fn test_generate_tree_directory_not_found() {
        let result = generate_tree(
            &[PathBuf::from("/nonexistent/path")],
            &TreeOptions::default(),
        );
        assert!(matches!(result, Err(CatboardError::DirectoryNotFound(_))));
    }

    #[test]
    fn test_generate_tree_not_a_directory() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("file.txt");
        fs::write(&file_path, "I am a file").unwrap();

        let result = generate_tree(&[file_path], &TreeOptions::default());
        assert!(matches!(result, Err(CatboardError::NotADirectory(_))));
    }

    #[test]
    fn test_generate_tree_unicode_filenames_and_contents() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("日本語.txt"), "こんにちは世界").unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert!(result.output.contains("日本語.txt"));
        assert!(result.output.contains("こんにちは世界"));
    }

    #[test]
    fn test_generate_tree_files_containing_triple_backticks() {
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("readme.md"),
            "# Example\n```rust\nfn main() {}\n```\n",
        )
        .unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert!(result.output.contains("````"));
    }

    #[test]
    fn test_generate_tree_stats_accuracy() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("a.txt"), "hello").unwrap(); // 5 bytes
        fs::write(dir.path().join("b.txt"), "world!").unwrap(); // 6 bytes

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 2);
        assert_eq!(result.files_skipped, 0);
        assert_eq!(result.total_bytes, 11);
        assert!(result
            .output
            .contains("2 files included, 0 skipped, 11B total"));
    }

    #[test]
    fn test_generate_tree_deeply_nested() {
        let dir = TempDir::new().unwrap();
        let deep = dir.path().join("a/b/c/d/e/f/g/h/i/j");
        fs::create_dir_all(&deep).unwrap();
        fs::write(deep.join("deep.txt"), "found me").unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert!(result.output.contains("found me"));
        assert_eq!(result.files_included, 1);
    }

    #[test]
    fn test_generate_tree_only_binary_files() {
        let dir = TempDir::new().unwrap();
        let mut f = File::create(dir.path().join("img.bin")).unwrap();
        f.write_all(&[0x00, 0x01, 0x02]).unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 0);
        assert_eq!(result.files_skipped, 1);
        assert!(result.output.contains("Skipped"));
    }

    #[test]
    fn test_longest_backtick_run_none() {
        assert_eq!(longest_backtick_run("no backticks here"), 0);
    }

    #[test]
    fn test_longest_backtick_run_triple() {
        assert_eq!(longest_backtick_run("```rust\ncode\n```"), 3);
    }

    #[test]
    fn test_longest_backtick_run_quadruple() {
        assert_eq!(longest_backtick_run("````\n```\n````"), 4);
    }

    // Fix 2: Regression test for double canonicalization
    #[test]
    fn test_generate_tree_relative_path_input() {
        let dir = TempDir::new().unwrap();
        let sub = dir.path().join("sub");
        fs::create_dir(&sub).unwrap();
        fs::write(sub.join("file.txt"), "contents").unwrap();

        let path_with_dotdot = dir.path().join("sub").join("..").join("sub");
        let result = generate_tree(&[path_with_dotdot], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 1);
        assert!(result.output.contains("file.txt"));
        assert!(result.output.contains("contents"));
    }

    #[cfg(unix)]
    #[test]
    fn test_generate_tree_permission_denied() {
        use std::os::unix::fs::PermissionsExt;

        extern "C" {
            fn geteuid() -> u32;
        }
        if unsafe { geteuid() } == 0 {
            return;
        }

        let dir = TempDir::new().unwrap();
        let denied_path = dir.path().join("denied.txt");
        fs::write(&denied_path, "secret").unwrap();
        fs::set_permissions(&denied_path, fs::Permissions::from_mode(0o000)).unwrap();

        // Ensure permissions are restored even if assertions panic
        struct RestorePerms(std::path::PathBuf);
        impl Drop for RestorePerms {
            fn drop(&mut self) {
                let _ = fs::set_permissions(&self.0, fs::Permissions::from_mode(0o644));
            }
        }
        let _guard = RestorePerms(denied_path.clone());

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_skipped, 1);
        assert!(result.output.contains("permission denied"));
    }

    // Fix 11: Symlink tests
    #[cfg(unix)]
    #[test]
    fn test_generate_tree_symlink_file() {
        use std::os::unix::fs::symlink;

        let dir = TempDir::new().unwrap();
        let real_file = dir.path().join("real.txt");
        fs::write(&real_file, "real content").unwrap();
        symlink(&real_file, dir.path().join("link.txt")).unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert!(result.output.contains("link.txt"));
        assert!(
            !result.output.contains("## link.txt"),
            "symlink should not generate a file content section"
        );
    }

    #[cfg(unix)]
    #[test]
    fn test_generate_tree_symlink_directory() {
        use std::os::unix::fs::symlink;

        let dir = TempDir::new().unwrap();
        let real_dir = dir.path().join("real_dir");
        fs::create_dir(&real_dir).unwrap();
        fs::write(real_dir.join("inside.txt"), "inside content").unwrap();
        symlink(&real_dir, dir.path().join("link_dir")).unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        // With follow_links(false), the walker does not follow symlinks.
        // The real_dir/inside.txt is included (it's a real file), but the
        // symlinked directory link_dir should not cause duplicate traversal.
        // Verify that "inside content" appears exactly once (from real_dir only).
        let count = result.output.matches("inside content").count();
        assert_eq!(
            count, 1,
            "inside content should appear exactly once (from real_dir, not from link_dir)"
        );
    }

    #[cfg(unix)]
    #[test]
    fn test_generate_tree_broken_symlink() {
        use std::os::unix::fs::symlink;

        let dir = TempDir::new().unwrap();
        symlink("/nonexistent/target", dir.path().join("broken_link")).unwrap();
        fs::write(dir.path().join("normal.txt"), "normal").unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert_eq!(result.files_included, 1);
        assert!(result.output.contains("normal"));
    }

    // Fix 13: Hidden file unit tests
    #[test]
    fn test_generate_tree_hidden_files_excluded_by_default() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join(".hidden"), "hidden content").unwrap();
        fs::write(dir.path().join("visible.txt"), "visible content").unwrap();

        let result = generate_tree(&[dir.path().to_path_buf()], &TreeOptions::default()).unwrap();
        assert!(result.output.contains("visible content"));
        assert!(
            !result.output.contains("hidden content"),
            "hidden files should be excluded by default"
        );
    }

    #[test]
    fn test_generate_tree_hidden_files_included() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join(".hidden"), "hidden content").unwrap();
        fs::write(dir.path().join("visible.txt"), "visible content").unwrap();

        let options = TreeOptions {
            include_hidden: true,
            ..TreeOptions::default()
        };
        let result = generate_tree(&[dir.path().to_path_buf()], &options).unwrap();
        assert!(result.output.contains("visible content"));
        assert!(
            result.output.contains("hidden content"),
            "hidden files should be included with include_hidden: true"
        );
    }

    // Fix 15: format_size boundary tests
    #[test]
    fn test_format_size_zero() {
        assert_eq!(format_size(0), "0B");
    }

    #[test]
    fn test_format_size_boundary_bytes_to_kb() {
        assert_eq!(format_size(1023), "1023B");
        assert_eq!(format_size(1024), "1.0KB");
    }

    #[test]
    fn test_format_size_boundary_kb_to_mb() {
        assert_eq!(format_size(1048575), "1024.0KB");
        assert_eq!(format_size(1048576), "1.0MB");
    }
}
