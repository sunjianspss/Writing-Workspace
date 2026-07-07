import Foundation

package extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }

    /// 把空字符串（去除首尾空白后）规整为 nil，方便用 `??` 串接兜底值。
    var nilIfEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return self
    }
}
