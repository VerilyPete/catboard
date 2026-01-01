import Foundation
import Vision
import AppKit

/// Simple OCR CLI using macOS Vision framework
/// Usage: catboard-ocr <image-path>
/// Outputs recognized text to stdout, one line per text block

func printUsage() {
    fputs("Usage: catboard-ocr <image-path>\n", stderr)
    fputs("Extracts text from an image using macOS Vision OCR.\n", stderr)
}

func performOCR(on imageURL: URL) -> Int32 {
    guard let image = NSImage(contentsOf: imageURL) else {
        fputs("Error: Could not load image: \(imageURL.path)\n", stderr)
        return 1
    }

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: Could not convert image to CGImage\n", stderr)
        return 1
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
        try handler.perform([request])
    } catch {
        fputs("Error: OCR failed: \(error.localizedDescription)\n", stderr)
        return 1
    }

    guard let observations = request.results else {
        // No text found - not an error, just empty
        return 0
    }

    for observation in observations {
        if let candidate = observation.topCandidates(1).first {
            print(candidate.string)
        }
    }

    return 0
}

// Main
guard CommandLine.arguments.count == 2 else {
    printUsage()
    exit(1)
}

let imagePath = CommandLine.arguments[1]

if imagePath == "--help" || imagePath == "-h" {
    printUsage()
    exit(0)
}

let imageURL = URL(fileURLWithPath: imagePath)

guard FileManager.default.fileExists(atPath: imagePath) else {
    fputs("Error: File not found: \(imagePath)\n", stderr)
    exit(1)
}

exit(performOCR(on: imageURL))
