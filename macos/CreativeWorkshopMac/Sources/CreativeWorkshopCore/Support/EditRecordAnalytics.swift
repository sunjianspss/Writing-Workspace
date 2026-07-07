import Foundation

package enum EditRecordAnalytics {
    package static func monthlySummary(records: [EditRecord], cumulativeLightEditRate: Double, today: Date = Date()) -> String {
        guard !records.isEmpty else { return "" }

        let currentMonth = monthPrefix(for: today)
        let previousMonth = monthPrefix(for: Calendar.current.date(byAdding: .month, value: -1, to: today) ?? today)
        let current = stats(for: records.filter { ($0.created_at ?? "").hasPrefix(currentMonth) })
        let previous = stats(for: records.filter { ($0.created_at ?? "").hasPrefix(previousMonth) })

        guard current.total > 0 else {
            return "本月暂无发布编辑记录；累计轻改率 \(percent(cumulativeLightEditRate))。"
        }
        guard previous.total > 0 else {
            return "本月零改率 \(percent(current.zeroEditRate))，轻改率 \(percent(current.lightEditRate))；上月暂无可比记录。"
        }
        return "本月零改率 \(percent(current.zeroEditRate))（较上月 \(signedPercent(current.zeroEditRate - previous.zeroEditRate))），轻改率 \(percent(current.lightEditRate))（较上月 \(signedPercent(current.lightEditRate - previous.lightEditRate))）。"
    }

    package static func stats(for records: [EditRecord]) -> EditRecordStats {
        guard !records.isEmpty else {
            return EditRecordStats(total: 0, zeroEditRate: 0, lightEditRate: 0, averageEditRatio: 0)
        }
        let zeroCount = records.filter { $0.edit_ratio <= 0.01 }.count
        let lightCount = records.filter { $0.edit_ratio <= 0.10 }.count
        let average = records.map(\.edit_ratio).reduce(0, +) / Double(records.count)
        return EditRecordStats(
            total: records.count,
            zeroEditRate: Double(zeroCount) / Double(records.count),
            lightEditRate: Double(lightCount) / Double(records.count),
            averageEditRatio: average
        )
    }

    private static func monthPrefix(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func signedPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f%%", value * 100))"
    }
}
