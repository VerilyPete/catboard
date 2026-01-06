import os.log

public extension OSLog {
    private static let subsystem = "com.verilypete.catboard.finder"

    static let fileReader = OSLog(subsystem: subsystem, category: "FileReader")
    static let pdf = OSLog(subsystem: subsystem, category: "PDF")
    static let ocr = OSLog(subsystem: subsystem, category: "OCR")
    static let clipboard = OSLog(subsystem: subsystem, category: "Clipboard")
    static let ui = OSLog(subsystem: subsystem, category: "UI")
}
