import Foundation
import AppKit

extension NSPasteboard.PasteboardType {
    static let webArchive = NSPasteboard.PasteboardType("com.apple.webarchive")
}

enum PBHTML {
    static func main() {
        let arguments = CommandLine.arguments
        let pasteboard = NSPasteboard.general

        do {
            if arguments.count == 1 {
                analyze(pasteboard)
                return
            }

            let subcommand = arguments[1].lowercased()
            
            // Handle 'analyze' separately as it doesn't strictly need a name
            if subcommand == "analyze" {
                analyze(pasteboard)
                return
            }

            guard arguments.count >= 3 else {
                printUsage()
                return
            }

            let name = arguments[2]

            switch subcommand {
            case "paste":
                try paste(pasteboard, name: name)
            case "copy":
                try copy(pasteboard, name: name)
            default:
                print("Unknown subcommand: \(subcommand)")
                printUsage()
            }
        } catch {
            printError(error.localizedDescription)
        }
    }

    private static func analyze(_ pasteboard: NSPasteboard) {
        guard let types = pasteboard.types, !types.isEmpty else {
            print("Clipboard is empty.")
            return
        }

        print("\nClipboard Analysis (\(types.count) types):")
        
        let typeColWidth = 45
        let sizeColWidth = 12
        
        let header = "\(pad("DATA TYPE", toWidth: typeColWidth)) | \(pad("SIZE", toWidth: sizeColWidth, alignRight: true)) | METADATA"
        let separator = String(repeating: "-", count: typeColWidth) + "-+-" + String(repeating: "-", count: sizeColWidth) + "-+-" + String(repeating: "-", count: 20)
        
        print("\u{001B}[1;34m" + header + "\u{001B}[0m")
        print(separator)

        for type in types {
            let typeName = type.rawValue
            let dataLength = pasteboard.data(forType: type)?.count ?? 0
            
            var metadata = ""
            if type == .webArchive {
                metadata = "Binary Plist (WebArchive)"
            } else if type == .html {
                metadata = "HTML Content"
            } else if let stringValue = pasteboard.string(forType: type) {
                metadata = "String (len: \(stringValue.count))"
            }
            
            let displayType = typeName.count > typeColWidth ? String(typeName.prefix(typeColWidth - 3)) + "..." : typeName
            let row = "\(pad(displayType, toWidth: typeColWidth)) | \(pad(formatBytes(dataLength), toWidth: sizeColWidth, alignRight: true)) | \(metadata)"
            
            if type == .html || type == .webArchive {
                print("\u{001B}[1;32m" + row + "\u{001B}[0m")
            } else {
                print(row)
            }
        }
        print(separator + "\n")
    }

    private static func paste(_ pasteboard: NSPasteboard, name: String) throws {
        if let data = pasteboard.data(forType: .webArchive), name != "--" {
            try extractWebArchive(data, baseName: name)
        } else {
            let content: Data?
            if let html = pasteboard.string(forType: .html) {
                content = html.data(using: .utf8)
            } else if let str = pasteboard.string(forType: .string) {
                content = str.data(using: .utf8)
            } else {
                content = pasteboard.data(forType: .html) ?? pasteboard.data(forType: .string)
            }

            guard let finalData = content else {
                throw createError("No readable content in clipboard.")
            }

            if name == "--" {
                FileHandle.standardOutput.write(finalData)
            } else {
                let fileURL = URL(fileURLWithPath: name).appendingPathExtension("html")
                try finalData.write(to: fileURL)
                print("Saved HTML to \(fileURL.lastPathComponent)")
            }
        }
    }

    private static func extractWebArchive(_ data: Data, baseName: String) throws {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let mainResource = plist["WebMainResource"] as? [String: Any],
              let mainData = mainResource["WebResourceData"] as? Data,
              var htmlString = String(data: mainData, encoding: .utf8) else {
            throw createError("Invalid WebArchive data.")
        }

        let subResources = plist["WebSubresources"] as? [[String: Any]] ?? []
        print("Extracting WebArchive '\(baseName)' with \(subResources.count) assets...")

        for (index, res) in subResources.enumerated() {
            guard let resData = res["WebResourceData"] as? Data,
                  let originalURL = res["WebResourceURL"] as? String,
                  let mimeType = res["WebResourceMIMEType"] as? String else { continue }

            let ext = extensionFromData(resData) ?? extensionForMimeType(mimeType)
            let localName = "\(baseName)-\(index + 1).\(ext)"
            
            let assetURL = URL(fileURLWithPath: localName)
            try resData.write(to: assetURL)
            print("  -> Asset saved: \(localName) (\(originalURL))")

            htmlString = htmlString.replacingOccurrences(of: originalURL, with: localName)
            
            let encodedURL = originalURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? originalURL
            if encodedURL != originalURL {
                htmlString = htmlString.replacingOccurrences(of: encodedURL, with: localName)
            }
        }

        let htmlURL = URL(fileURLWithPath: baseName).appendingPathExtension("html")
        guard let outputData = htmlString.data(using: .utf8) else {
            throw createError("Could not encode modified HTML.")
        }
        try outputData.write(to: htmlURL, options: .atomic)
        print("Finished! Main HTML saved as \(htmlURL.lastPathComponent)")
    }

    private static func copy(_ pasteboard: NSPasteboard, name: String) throws {
        if name == "--" {
            let inputData = FileHandle.standardInput.readDataToEndOfFile()
            guard !inputData.isEmpty else { return }
            try setPasteboardContent(pasteboard, htmlData: inputData, webArchiveData: nil)
            print("Successfully copied stdin to clipboard as HTML.")
            return
        }

        let baseName = name.replacingOccurrences(of: ".html", with: "", options: .caseInsensitive)
        let htmlURL = URL(fileURLWithPath: baseName).appendingPathExtension("html")
        
        let htmlData = try Data(contentsOf: htmlURL)
        guard var htmlString = String(data: htmlData, encoding: .utf8) else {
            throw createError("Could not decode HTML as UTF-8.")
        }

        var subResources = [[String: Any]]()
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: ".")
        let assetPrefix = "\(baseName)-"
        
        print("Scanning for assets starting with '\(assetPrefix)'...")

        for file in files {
            if file.hasPrefix(assetPrefix) && file != htmlURL.lastPathComponent {
                if htmlString.contains(file) {
                    let fileData = try Data(contentsOf: URL(fileURLWithPath: file))
                    let cid = "cid:\(UUID().uuidString)"
                    let ext = URL(fileURLWithPath: file).pathExtension
                    let mime = mimeTypeForExtension(ext)
                    
                    let resource: [String: Any] = [
                        "WebResourceData": fileData,
                        "WebResourceMIMEType": mime,
                        "WebResourceURL": cid
                    ]
                    subResources.append(resource)
                    htmlString = htmlString.replacingOccurrences(of: file, with: cid)
                    print("  <- Packaging asset: \(file) as \(cid)")
                }
            }
        }

        guard let finalHtmlData = htmlString.data(using: .utf8) else {
            throw createError("Could not encode final HTML.")
        }

        if subResources.isEmpty {
            try setPasteboardContent(pasteboard, htmlData: finalHtmlData, webArchiveData: nil)
            print("No assets found. Copied as standard HTML.")
        } else {
            let mainResource: [String: Any] = [
                "WebResourceData": finalHtmlData,
                "WebResourceMIMEType": "text/html",
                "WebResourceTextEncodingName": "UTF-8",
                "WebResourceURL": "about:blank"
            ]
            let webArchive: [String: Any] = [
                "WebMainResource": mainResource,
                "WebSubresources": subResources
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: webArchive, format: .binary, options: 0)
            try setPasteboardContent(pasteboard, htmlData: finalHtmlData, webArchiveData: plistData)
            print("Finished! Packaged as WebArchive with \(subResources.count) assets and copied to clipboard.")
        }
    }

    private static func setPasteboardContent(_ pasteboard: NSPasteboard, htmlData: Data, webArchiveData: Data?) throws {
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.html, .string]
        if webArchiveData != nil {
            types.insert(.webArchive, at: 0)
        }
        
        pasteboard.declareTypes(types, owner: nil)
        
        if let waData = webArchiveData {
            pasteboard.setData(waData, forType: .webArchive)
        }
        
        pasteboard.setData(htmlData, forType: .html)
        if let str = String(data: htmlData, encoding: .utf8) {
            pasteboard.setString(str, forType: .string)
        } else {
            throw createError("Could not set string representation for pasteboard.")
        }
    }

    private static func extensionFromData(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(12))
        
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && bytes.dropFirst(8).starts(with: [0x57, 0x45, 0x42, 0x50]) {
            return "webp"
        }
        return nil
    }

    private static func extensionForMimeType(_ mime: String) -> String {
        let map = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp", "text/html": "html", "application/pdf": "pdf"]
        return map[mime.lowercased()] ?? "bin"
    }

    private static func mimeTypeForExtension(_ ext: String) -> String {
        let map = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp", "pdf": "application/pdf", "html": "text/html", "css": "text/css"]
        return map[ext.lowercased()] ?? "application/octet-stream"
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func pad(_ string: String, toWidth width: Int, alignRight: Bool = false) -> String {
        if string.count >= width {
            return String(string.prefix(width))
        }
        let padding = String(repeating: " ", count: width - string.count)
        return alignRight ? (padding + string) : (string + padding)
    }

    private static func createError(_ message: String) -> NSError {
        return NSError(domain: "pbhtml", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func printError(_ message: String) {
        if let data = "Error: \(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private static func printUsage() {
        print("Usage: pbhtml <subcommand> <name>")
        print("  subcommand: analyze | paste | copy")
        print("  name: filename base OR '--' for stdin/stdout")
    }
}

PBHTML.main()
