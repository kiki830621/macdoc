import Foundation
import CommonConverterSwift
import OOXMLSwift

// MARK: - Colors (matching commands.tex definitions)
private enum TeXColor {
    static let titlePink = "CC0066"
    static let keywordBlue = "002060"
    static let timecodeGray = "808080"
    static let summaryBorder = "999999"
    static let summaryBackground = "F5F5F5"
    static let sectionBg = "333333"
    static let sectionFg = "FFFFFF"
    static let subsectionBrown = "663300"
    static let subsubsectionBlue = "003399"
}

struct TeXWordBuilder {
    private let source: String
    private let sourceURL: URL
    private let options: ConversionOptions
    private var document = WordDocument()
    private var lines: [String] = []
    private var cursor = 0

    init(source: String, sourceURL: URL, options: ConversionOptions) {
        self.source = source
        self.sourceURL = sourceURL
        self.options = options
    }

    mutating func build() -> WordDocument {
        // Strip preamble (everything before \begin{document})
        let body = extractDocumentBody(source)
        lines = body.components(separatedBy: .newlines)
        cursor = 0

        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("%") {
                cursor += 1
                continue
            }

            // Skip LaTeX commands we don't render
            if isSkippableLine(line) {
                cursor += 1
                continue
            }

            // \篇名{行1}{行2}
            if let (line1, line2) = matchPianMing(line) {
                emitPianMing(line1: line1, line2: line2)
                cursor += 1
                continue
            }

            // \摘要{內容}
            if let content = matchZhaiYao(line) {
                emitZhaiYao(content)
                cursor += 1
                continue
            }

            // \section{...}
            if let title = matchCommand("section", in: line) {
                emitSection(title)
                cursor += 1
                continue
            }

            // \subsection{...}
            if let title = matchCommand("subsection", in: line) {
                emitSubsection(title)
                cursor += 1
                continue
            }

            // \subsubsection{...}
            if let title = matchCommand("subsubsection", in: line) {
                emitSubsubsection(title)
                cursor += 1
                continue
            }

            // Regular paragraph text
            emitParagraph(line)
            cursor += 1
        }

        if document.body.children.isEmpty {
            document.appendParagraph(Paragraph())
        }

        return document
    }

    // MARK: - Document body extraction

    private func extractDocumentBody(_ source: String) -> String {
        guard let beginRange = source.range(of: "\\begin{document}") else {
            return source
        }
        let afterBegin = source[beginRange.upperBound...]

        if let endRange = afterBegin.range(of: "\\end{document}") {
            return String(afterBegin[..<endRange.lowerBound])
        }
        return String(afterBegin)
    }

    // MARK: - Command matchers

    private func matchPianMing(_ line: String) -> (String, String)? {
        let pattern = #"\\篇名\{([^}]*)\}\{([^}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r1 = Range(match.range(at: 1), in: line),
              let r2 = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (String(line[r1]), String(line[r2]))
    }

    private func matchZhaiYao(_ line: String) -> String? {
        matchCommand("摘要", in: line)
    }

    private func matchCommand(_ name: String, in line: String) -> String? {
        let pattern = "\\\\\(NSRegularExpression.escapedPattern(for: name))\\{([^}]*)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
    }

    private func isSkippableLine(_ line: String) -> Bool {
        let skippable = [
            "\\maketitle", "\\tableofcontents", "\\clearpage", "\\cleardoublepage",
            "\\newpage", "\\thispagestyle", "\\addcontentsline", "\\vspace",
            "\\begin{titlepage}", "\\end{titlepage}", "\\begin{center}", "\\end{center}",
            "\\begin{flushleft}", "\\end{flushleft}",
        ]
        for prefix in skippable {
            if line.hasPrefix(prefix) { return true }
        }
        // Skip \vspace*, \setlength, etc.
        if line.hasPrefix("\\vspace") || line.hasPrefix("\\setlength") { return true }
        return false
    }

    // MARK: - Emitters

    private mutating func emitPianMing(line1: String, line2: String) {
        // Page break before
        var breakPara = Paragraph()
        breakPara.properties.pageBreakBefore = true
        document.appendParagraph(breakPara)

        // Title line 1
        let run1 = Run(text: line1, properties: RunProperties(
            bold: true,
            fontSize: 48,       // 24pt
            color: TeXColor.titlePink
        ))
        var para1 = Paragraph(runs: [run1])
        para1.properties.alignment = .center
        para1.properties.spacing = Spacing(before: 4000, after: 240)
        document.appendParagraph(para1)

        // Title line 2
        let run2 = Run(text: line2, properties: RunProperties(
            bold: true,
            fontSize: 48,
            color: TeXColor.titlePink
        ))
        var para2 = Paragraph(runs: [run2])
        para2.properties.alignment = .center
        para2.properties.spacing = Spacing(before: 0, after: 4000)
        document.appendParagraph(para2)
    }

    private mutating func emitZhaiYao(_ content: String) {
        let diamondRun = Run(text: "◆", properties: RunProperties(fontSize: 28))
        let textRun = Run(text: content, properties: RunProperties(fontSize: 28))

        var para = Paragraph(runs: [diamondRun, textRun])
        para.properties.border = ParagraphBorder.all(
            ParagraphBorderStyle(type: .single, color: TeXColor.summaryBorder, size: 4)
        )
        para.properties.shading = CellShading.solid(TeXColor.summaryBackground)
        para.properties.spacing = Spacing(before: 120, after: 120)
        para.properties.indentation = Indentation(left: 120, right: 120)
        document.appendParagraph(para)
    }

    private mutating func emitSection(_ title: String) {
        let run = Run(text: title, properties: RunProperties(
            bold: true,
            fontSize: 32,       // 16pt
            color: TeXColor.sectionFg
        ))
        var para = Paragraph(runs: [run])
        para.properties.style = "Heading2"
        para.properties.shading = CellShading.solid(TeXColor.sectionBg)
        para.properties.spacing = Spacing(before: 360, after: 120)
        document.appendParagraph(para)
    }

    private mutating func emitSubsection(_ title: String) {
        let run = Run(text: title, properties: RunProperties(
            bold: true,
            fontSize: 32,       // 16pt
            color: TeXColor.subsectionBrown
        ))
        var para = Paragraph(runs: [run])
        para.properties.style = "Heading3"
        para.properties.spacing = Spacing(before: 240, after: 120)
        document.appendParagraph(para)
    }

    private mutating func emitSubsubsection(_ title: String) {
        let displayTitle = "【\(title)】"
        let run = Run(text: displayTitle, properties: RunProperties(
            bold: true,
            fontSize: 28,       // 14pt
            color: TeXColor.subsubsectionBlue
        ))
        var para = Paragraph(runs: [run])
        para.properties.style = "Heading4"
        para.properties.spacing = Spacing(before: 240, after: 120)
        document.appendParagraph(para)
    }

    private mutating func emitParagraph(_ line: String) {
        let runs = parseInlineCommands(line)
        guard !runs.isEmpty else { return }
        var para = Paragraph(runs: runs)
        para.properties.spacing = Spacing(before: 0, after: 60)
        document.appendParagraph(para)
    }

    // MARK: - Inline command parser

    /// Parse a line and convert \kw{}, \tc{}, \textbf{} etc. into styled runs
    func parseInlineCommands(_ text: String) -> [Run] {
        var runs: [Run] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Find the next backslash command
            guard let backslashIndex = remaining.firstIndex(of: "\\") else {
                // No more commands — emit rest as plain text
                let plain = cleanLaTeX(String(remaining))
                if !plain.isEmpty {
                    runs.append(Run(text: plain))
                }
                break
            }

            // Emit text before the command
            if backslashIndex > remaining.startIndex {
                let before = cleanLaTeX(String(remaining[remaining.startIndex..<backslashIndex]))
                if !before.isEmpty {
                    runs.append(Run(text: before))
                }
            }

            // Try to match known inline commands
            let fromBackslash = String(remaining[backslashIndex...])

            if let (content, len) = extractBraceContent("\\kw", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(
                    bold: true,
                    color: TeXColor.keywordBlue
                )))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\tc", from: fromBackslash) {
                runs.append(Run(text: "(\(content))", properties: RunProperties(
                    color: TeXColor.timecodeGray
                )))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\textbf", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(bold: true)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\emph", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(italic: true)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\textit", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(italic: true)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else {
                // Unknown command — skip past the backslash + command name
                let afterBackslash = remaining.index(after: backslashIndex)
                if afterBackslash < remaining.endIndex {
                    // Skip command name (letters only)
                    var end = afterBackslash
                    while end < remaining.endIndex && remaining[end].isLetter {
                        end = remaining.index(after: end)
                    }
                    // If followed by {}, skip the braces and include content
                    if end < remaining.endIndex && remaining[end] == "{" {
                        if let (content, len) = extractBraceContentRaw(from: String(remaining[backslashIndex...])) {
                            let plain = cleanLaTeX(content)
                            if !plain.isEmpty {
                                runs.append(Run(text: plain))
                            }
                            remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
                        } else {
                            remaining = remaining[end...]
                        }
                    } else {
                        // Command without braces (e.g., \par, \\) — skip it
                        remaining = remaining[end...]
                    }
                } else {
                    break
                }
            }
        }

        return runs
    }

    /// Extract content from \command{content}, returns (content, total consumed length)
    private func extractBraceContent(_ command: String, from text: String) -> (String, Int)? {
        guard text.hasPrefix(command) else { return nil }
        let afterCommand = text.dropFirst(command.count)
        guard afterCommand.first == "{" else { return nil }

        var depth = 0
        var contentStart: String.Index?
        for i in afterCommand.indices {
            if afterCommand[i] == "{" {
                if depth == 0 { contentStart = afterCommand.index(after: i) }
                depth += 1
            } else if afterCommand[i] == "}" {
                depth -= 1
                if depth == 0, let start = contentStart {
                    let content = String(afterCommand[start..<i])
                    let totalLen = command.count + afterCommand.distance(from: afterCommand.startIndex, to: afterCommand.index(after: i))
                    return (content, totalLen)
                }
            }
        }
        return nil
    }

    /// Extract content from any \command{content}
    private func extractBraceContentRaw(from text: String) -> (String, Int)? {
        guard let openBrace = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        for i in text[openBrace...].indices {
            if text[i] == "{" { depth += 1 }
            else if text[i] == "}" {
                depth -= 1
                if depth == 0 {
                    let contentStart = text.index(after: openBrace)
                    let content = String(text[contentStart..<i])
                    let totalLen = text.distance(from: text.startIndex, to: text.index(after: i))
                    return (content, totalLen)
                }
            }
        }
        return nil
    }

    /// Remove leftover LaTeX artifacts
    private func cleanLaTeX(_ text: String) -> String {
        text
            .replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "\\,", with: " ")
            .replacingOccurrences(of: "\\;", with: " ")
            .replacingOccurrences(of: "\\!", with: "")
            .replacingOccurrences(of: "\\\\", with: "")
            .replacingOccurrences(of: "\\&", with: "&")
            .replacingOccurrences(of: "\\%", with: "%")
            .replacingOccurrences(of: "\\$", with: "$")
            .replacingOccurrences(of: "\\#", with: "#")
            .replacingOccurrences(of: "\\_", with: "_")
            .replacingOccurrences(of: "\\{", with: "{")
            .replacingOccurrences(of: "\\}", with: "}")
            .trimmingCharacters(in: .whitespaces)
    }
}
