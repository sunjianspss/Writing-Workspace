import Foundation

package enum TextDiffKind: String, Hashable {
    case equal
    case added
    case removed
}

package struct TextDiffLine: Identifiable, Hashable {
    package let id: Int
    package let kind: TextDiffKind
    package let text: String
}

package struct TextDiffSummary: Hashable {
    package let added: Int
    package let removed: Int
    package let unchanged: Int

    package var isEmpty: Bool {
        added == 0 && removed == 0
    }
}

package enum TextDiff {
    package static func characterSummary(before: String, after: String) -> TextDiffSummary {
        let oldChars = Array(before)
        let newChars = Array(after)
        if oldChars.count * newChars.count <= 36_000_000 {
            let unchanged = lcsLength(oldChars, newChars)
            return TextDiffSummary(
                added: max(0, newChars.count - unchanged),
                removed: max(0, oldChars.count - unchanged),
                unchanged: unchanged
            )
        }
        return fastCharacterSummary(before: oldChars, after: newChars)
    }

    package static func lines(before: String, after: String) -> [TextDiffLine] {
        let oldLines = normalizedLines(before)
        let newLines = normalizedLines(after)
        let table = lcsTable(oldLines, newLines)
        var output: [(TextDiffKind, String)] = []
        var oldIndex = oldLines.count
        var newIndex = newLines.count

        while oldIndex > 0 || newIndex > 0 {
            if oldIndex > 0,
               newIndex > 0,
               oldLines[oldIndex - 1] == newLines[newIndex - 1] {
                output.append((.equal, oldLines[oldIndex - 1]))
                oldIndex -= 1
                newIndex -= 1
            } else if newIndex > 0,
                      (oldIndex == 0 || table[oldIndex][newIndex - 1] >= table[oldIndex - 1][newIndex]) {
                output.append((.added, newLines[newIndex - 1]))
                newIndex -= 1
            } else if oldIndex > 0 {
                output.append((.removed, oldLines[oldIndex - 1]))
                oldIndex -= 1
            }
        }

        return output.reversed().enumerated().map { offset, item in
            TextDiffLine(id: offset, kind: item.0, text: item.1)
        }
    }

    package static func summary(before: String, after: String) -> TextDiffSummary {
        let lines = lines(before: before, after: after)
        return TextDiffSummary(
            added: lines.filter { $0.kind == .added }.count,
            removed: lines.filter { $0.kind == .removed }.count,
            unchanged: lines.filter { $0.kind == .equal }.count
        )
    }

    private static func normalizedLines(_ text: String) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        return lines.isEmpty ? [""] : lines
    }

    private static func lcsTable(_ oldLines: [String], _ newLines: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1
        )
        guard !oldLines.isEmpty, !newLines.isEmpty else {
            return table
        }
        for oldIndex in 1...oldLines.count {
            for newIndex in 1...newLines.count {
                if oldLines[oldIndex - 1] == newLines[newIndex - 1] {
                    table[oldIndex][newIndex] = table[oldIndex - 1][newIndex - 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(
                        table[oldIndex - 1][newIndex],
                        table[oldIndex][newIndex - 1]
                    )
                }
            }
        }
        return table
    }

    private static func lcsLength<T: Equatable>(_ oldValues: [T], _ newValues: [T]) -> Int {
        guard !oldValues.isEmpty, !newValues.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: newValues.count + 1)
        var current = previous
        for oldIndex in 1...oldValues.count {
            current[0] = 0
            for newIndex in 1...newValues.count {
                if oldValues[oldIndex - 1] == newValues[newIndex - 1] {
                    current[newIndex] = previous[newIndex - 1] + 1
                } else {
                    current[newIndex] = max(previous[newIndex], current[newIndex - 1])
                }
            }
            swap(&previous, &current)
        }
        return previous[newValues.count]
    }

    private static func fastCharacterSummary(before oldChars: [Character], after newChars: [Character]) -> TextDiffSummary {
        var prefix = 0
        let minCount = min(oldChars.count, newChars.count)
        while prefix < minCount, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        var oldSuffix = oldChars.count - 1
        var newSuffix = newChars.count - 1
        var suffix = 0
        while oldSuffix >= prefix,
              newSuffix >= prefix,
              oldChars[oldSuffix] == newChars[newSuffix] {
            suffix += 1
            oldSuffix -= 1
            newSuffix -= 1
        }

        let unchanged = prefix + suffix
        return TextDiffSummary(
            added: max(0, newChars.count - unchanged),
            removed: max(0, oldChars.count - unchanged),
            unchanged: unchanged
        )
    }
}
