use catboard::{copy_to_clipboard, read_stdin, CatboardError};
use clap::Parser;
use std::path::PathBuf;
use std::process::ExitCode;

/// Copy file contents to the system clipboard
///
/// A cross-platform utility to quickly copy text file contents to your
/// clipboard, with macOS Finder integration support.
#[derive(Parser, Debug)]
#[command(name = "catboard")]
#[command(version, about, long_about = None)]
struct Args {
    /// Files to copy to clipboard (use '-' for stdin)
    ///
    /// Multiple files will be concatenated with newlines.
    #[arg(required = true)]
    files: Vec<PathBuf>,

    /// Verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Quiet mode - suppress all output except errors
    #[arg(short, long)]
    quiet: bool,
}

fn run(args: Args) -> Result<(), CatboardError> {
    let mut contents = Vec::new();

    for path in &args.files {
        let path_str = path.to_string_lossy();

        if path_str == "-" {
            // Read from stdin
            if args.verbose {
                eprintln!("Reading from stdin...");
            }
            let content = read_stdin()?;
            contents.push(content);
        } else {
            // Read from file
            if args.verbose {
                eprintln!("Reading file: {}", path.display());
            }
            let content = catboard::read_file_contents(path)?;
            contents.push(content);
        }
    }

    if contents.is_empty() {
        return Err(CatboardError::NoFilesSpecified);
    }

    // Join all contents with newlines
    let combined = contents.join("\n");
    let len = combined.len();

    copy_to_clipboard(&combined)?;

    if !args.quiet {
        if args.files.len() == 1 {
            let file_desc = if args.files[0].to_string_lossy() == "-" {
                "stdin".to_string()
            } else {
                args.files[0].display().to_string()
            };
            eprintln!("Copied {} bytes from {} to clipboard", len, file_desc);
        } else {
            eprintln!(
                "Copied {} bytes from {} files to clipboard",
                len,
                args.files.len()
            );
        }
    }

    Ok(())
}

fn main() -> ExitCode {
    let args = Args::parse();

    match run(args) {
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
        let args = Args::parse_from(["catboard", "file.txt"]);
        assert_eq!(args.files.len(), 1);
        assert_eq!(args.files[0], PathBuf::from("file.txt"));
        assert!(!args.verbose);
        assert!(!args.quiet);
    }

    #[test]
    fn test_args_parsing_multiple_files() {
        let args = Args::parse_from(["catboard", "file1.txt", "file2.txt", "file3.txt"]);
        assert_eq!(args.files.len(), 3);
    }

    #[test]
    fn test_args_parsing_verbose() {
        let args = Args::parse_from(["catboard", "-v", "file.txt"]);
        assert!(args.verbose);
    }

    #[test]
    fn test_args_parsing_quiet() {
        let args = Args::parse_from(["catboard", "-q", "file.txt"]);
        assert!(args.quiet);
    }

    #[test]
    fn test_args_parsing_stdin() {
        let args = Args::parse_from(["catboard", "-"]);
        assert_eq!(args.files[0], PathBuf::from("-"));
    }

    #[test]
    fn test_args_parsing_long_flags() {
        let args = Args::parse_from(["catboard", "--verbose", "--quiet", "file.txt"]);
        assert!(args.verbose);
        assert!(args.quiet);
    }

    #[test]
    fn test_run_file_not_found() {
        let args = Args {
            files: vec![PathBuf::from("/nonexistent/file.txt")],
            verbose: false,
            quiet: true,
        };
        let result = run(args);
        assert!(matches!(result, Err(CatboardError::FileNotFound(_))));
    }
}
