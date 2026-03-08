use catboard::tree::{TreeOptions, TreeResult};
use catboard::{copy_to_clipboard, read_stdin, CatboardError};
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::process::ExitCode;

/// Copy file contents to the system clipboard
///
/// A cross-platform utility to quickly copy text file contents to your
/// clipboard, with macOS Finder integration support.
#[derive(Parser, Debug)]
#[command(name = "catboard")]
#[command(version, about = "Copy file contents to clipboard")]
#[command(subcommand_negates_reqs = true)]
#[command(args_conflicts_with_subcommands = true)]
struct Cli {
    /// Files to copy to clipboard (use '-' for stdin)
    ///
    /// Multiple files will be concatenated with newlines.
    #[arg(required = true)]
    files: Vec<PathBuf>,

    /// Verbose output
    #[arg(short, long, global = true)]
    verbose: bool,

    /// Quiet mode - suppress all output except errors
    #[arg(short, long, global = true)]
    quiet: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Walk directories and output contents as markdown for LLM context
    Tree(TreeArgs),
}

fn parse_size(s: &str) -> Result<usize, String> {
    let s = s.trim();
    if s.is_empty() {
        return Err("size cannot be empty".to_string());
    }
    let s_upper = s.to_uppercase();
    let (num_str, multiplier) = if let Some(prefix) = s_upper.strip_suffix("GB") {
        (prefix, 1024 * 1024 * 1024)
    } else if let Some(prefix) = s_upper.strip_suffix("MB") {
        (prefix, 1024 * 1024)
    } else if let Some(prefix) = s_upper.strip_suffix("KB") {
        (prefix, 1024)
    } else if let Some(prefix) = s_upper.strip_suffix('B') {
        (prefix, 1)
    } else {
        (s_upper.as_str(), 1)
    };
    let num: usize = num_str
        .trim()
        .parse()
        .map_err(|_| format!("invalid number in size: {}", s))?;
    if num == 0 {
        return Err("size must be greater than zero".to_string());
    }
    num.checked_mul(multiplier)
        .ok_or_else(|| format!("size too large: {}", s))
}

#[derive(clap::Args, Debug)]
#[command(after_help = "\
Examples:
  catboard tree src/                     # Output to stdout
  catboard tree --copy src/ lib/         # Copy multiple dirs to clipboard
  catboard tree --hidden .               # Include hidden files
  catboard tree --max-total-size 5MB .   # Larger output limit")]
struct TreeArgs {
    /// Directories to walk
    #[arg(required = true)]
    dirs: Vec<PathBuf>,

    /// Copy to clipboard instead of stdout
    #[arg(long)]
    copy: bool,

    /// Include hidden files
    #[arg(long)]
    hidden: bool,

    /// Maximum size per file (e.g., 256KB, 1MB)
    #[arg(long, default_value = "256KB", value_parser = parse_size)]
    max_file_size: usize,

    /// Maximum total output size (e.g., 1MB, 10MB)
    #[arg(long, default_value = "1MB", value_parser = parse_size)]
    max_total_size: usize,

    /// Don't respect .gitignore rules
    #[arg(long)]
    no_gitignore: bool,
}

fn run_copy(files: Vec<PathBuf>, verbose: bool, quiet: bool) -> Result<(), CatboardError> {
    let mut contents = Vec::new();

    for path in &files {
        let path_str = path.to_string_lossy();

        if path_str == "-" {
            if verbose {
                eprintln!("Reading from stdin...");
            }
            let content = read_stdin()?;
            contents.push(content);
        } else {
            if verbose {
                eprintln!("Reading file: {}", path.display());
            }
            let content = catboard::read_file_contents(path)?;
            contents.push(content);
        }
    }

    if contents.is_empty() {
        return Err(CatboardError::NoFilesSpecified);
    }

    let combined = contents.join("\n");
    let len = combined.len();

    copy_to_clipboard(&combined)?;

    if !quiet {
        if files.len() == 1 {
            let file_desc = if files[0].to_string_lossy() == "-" {
                "stdin".to_string()
            } else {
                files[0].display().to_string()
            };
            eprintln!("Copied {} bytes from {} to clipboard", len, file_desc);
        } else {
            eprintln!(
                "Copied {} bytes from {} files to clipboard",
                len,
                files.len()
            );
        }
    }

    Ok(())
}

fn run_tree(args: TreeArgs, verbose: bool, quiet: bool) -> Result<(), CatboardError> {
    let options = TreeOptions {
        max_file_size: args.max_file_size,
        max_total_size: args.max_total_size,
        include_hidden: args.hidden,
        respect_gitignore: !args.no_gitignore,
    };

    let result: TreeResult = catboard::tree::generate_tree(&args.dirs, &options)?;

    if args.copy {
        copy_to_clipboard(&result.output)?;
        if !quiet {
            eprintln!(
                "Copied tree output to clipboard ({} files, {})",
                result.files_included,
                catboard::tree::format_size(result.total_bytes)
            );
        }
    } else {
        print!("{}", result.output);
    }

    if verbose {
        eprintln!(
            "{} files included, {} skipped, {} total",
            result.files_included,
            result.files_skipped,
            catboard::tree::format_size(result.total_bytes)
        );
    }

    if result.truncated && !quiet {
        eprintln!(
            "Warning: output was truncated (exceeded {} limit)",
            catboard::tree::format_size(options.max_total_size)
        );
    }

    Ok(())
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    let result = match cli.command {
        Some(Commands::Tree(args)) => run_tree(args, cli.verbose, cli.quiet),
        None => run_copy(cli.files, cli.verbose, cli.quiet),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Error: {}", e);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_args_parsing_single_file() {
        let cli = Cli::parse_from(["catboard", "file.txt"]);
        assert_eq!(cli.files.len(), 1);
        assert_eq!(cli.files[0], PathBuf::from("file.txt"));
        assert!(!cli.verbose);
        assert!(!cli.quiet);
        assert!(cli.command.is_none());
    }

    #[test]
    fn test_args_parsing_multiple_files() {
        let cli = Cli::parse_from(["catboard", "file1.txt", "file2.txt", "file3.txt"]);
        assert_eq!(cli.files.len(), 3);
    }

    #[test]
    fn test_args_parsing_verbose() {
        let cli = Cli::parse_from(["catboard", "-v", "file.txt"]);
        assert!(cli.verbose);
    }

    #[test]
    fn test_args_parsing_quiet() {
        let cli = Cli::parse_from(["catboard", "-q", "file.txt"]);
        assert!(cli.quiet);
    }

    #[test]
    fn test_args_parsing_stdin() {
        let cli = Cli::parse_from(["catboard", "-"]);
        assert_eq!(cli.files[0], PathBuf::from("-"));
    }

    #[test]
    fn test_args_parsing_long_flags() {
        let cli = Cli::parse_from(["catboard", "--verbose", "--quiet", "file.txt"]);
        assert!(cli.verbose);
        assert!(cli.quiet);
    }

    #[test]
    fn test_run_file_not_found() {
        let result = run_copy(vec![PathBuf::from("/nonexistent/file.txt")], false, true);
        assert!(matches!(result, Err(CatboardError::FileNotFound(_))));
    }

    // parse_size tests
    #[test]
    fn test_parse_size_bytes() {
        assert_eq!(parse_size("100B").unwrap(), 100);
    }

    #[test]
    fn test_parse_size_kilobytes() {
        assert_eq!(parse_size("256KB").unwrap(), 256 * 1024);
    }

    #[test]
    fn test_parse_size_megabytes() {
        assert_eq!(parse_size("1MB").unwrap(), 1024 * 1024);
    }

    #[test]
    fn test_parse_size_gigabytes() {
        assert_eq!(parse_size("2GB").unwrap(), 2 * 1024 * 1024 * 1024);
    }

    #[test]
    fn test_parse_size_plain_number() {
        assert_eq!(parse_size("1024").unwrap(), 1024);
    }

    #[test]
    fn test_parse_size_case_insensitive() {
        assert_eq!(parse_size("256kb").unwrap(), 256 * 1024);
        assert_eq!(parse_size("1mb").unwrap(), 1024 * 1024);
    }

    #[test]
    fn test_parse_size_empty() {
        assert!(parse_size("").is_err());
    }

    #[test]
    fn test_parse_size_zero() {
        assert!(parse_size("0KB").is_err());
    }

    #[test]
    fn test_parse_size_invalid() {
        assert!(parse_size("abc").is_err());
    }

    // tree subcommand parsing tests
    #[test]
    fn test_tree_subcommand_basic() {
        let cli = Cli::parse_from(["catboard", "tree", "src/"]);
        assert!(cli.command.is_some());
        if let Some(Commands::Tree(args)) = cli.command {
            assert_eq!(args.dirs, vec![PathBuf::from("src/")]);
            assert!(!args.copy);
            assert!(!args.hidden);
            assert!(!args.no_gitignore);
            assert_eq!(args.max_file_size, 256 * 1024);
            assert_eq!(args.max_total_size, 1024 * 1024);
        }
    }

    #[test]
    fn test_tree_subcommand_with_flags() {
        let cli = Cli::parse_from([
            "catboard",
            "tree",
            "--copy",
            "--hidden",
            "--no-gitignore",
            "--max-file-size",
            "512KB",
            "--max-total-size",
            "5MB",
            "src/",
            "lib/",
        ]);
        if let Some(Commands::Tree(args)) = cli.command {
            assert!(args.copy);
            assert!(args.hidden);
            assert!(args.no_gitignore);
            assert_eq!(args.max_file_size, 512 * 1024);
            assert_eq!(args.max_total_size, 5 * 1024 * 1024);
            assert_eq!(args.dirs.len(), 2);
        }
    }

    #[test]
    fn test_verbose_with_tree_subcommand() {
        let cli = Cli::parse_from(["catboard", "tree", "-v", "src/"]);
        assert!(cli.verbose);
        assert!(cli.command.is_some());
    }
}
