import Foundation
import CommonConverterSwift
import OOXMLSwift

public struct TeXToDOCXConverter: DocumentConverter {
    public static let sourceFormat = "tex"

    public init() {}

    public func convert<W: StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let document = try convertToDocument(input: input, options: options)
        try output.write(renderDocumentXML(document))
    }

    public func convertToFile(
        input: URL,
        output: URL,
        options: ConversionOptions = .default
    ) throws {
        let document = try convertToDocument(input: input, options: options)
        try DocxWriter.write(document, to: output)
    }

    public func convertToDocument(
        input: URL,
        options: ConversionOptions = .default
    ) throws -> WordDocument {
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ConversionError.fileNotFound(input.path)
        }

        let source = try String(contentsOf: input, encoding: .utf8)
        let expanded = try expandInputs(source: source, baseURL: input.deletingLastPathComponent())

        var builder = TeXWordBuilder(source: expanded, sourceURL: input, options: options)
        return builder.build()
    }

    /// Recursively expand \input{...} directives
    private func expandInputs(source: String, baseURL: URL) throws -> String {
        let pattern = #"\\input\{([^}]+)\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        var result = source

        // Iterate until no more \input found (handles nested includes)
        var iterations = 0
        while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              iterations < 100 {
            iterations += 1

            let fullRange = Range(match.range, in: result)!
            let pathRange = Range(match.range(at: 1), in: result)!
            var path = String(result[pathRange])

            // Add .tex extension if missing
            if !path.hasSuffix(".tex") {
                path += ".tex"
            }

            let fileURL = baseURL.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                result.replaceSubrange(fullRange, with: content)
            } else {
                // Remove the \input directive if file not found
                result.replaceSubrange(fullRange, with: "% [missing: \(path)]")
            }
        }

        return result
    }

    private func renderDocumentXML(_ document: WordDocument) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>
        """

        for child in document.body.children {
            switch child {
            case .paragraph(let paragraph):
                xml += paragraph.toXML()
            case .table(let table):
                xml += table.toXML()
            }
        }

        xml += "</w:body></w:document>"
        return xml
    }
}
