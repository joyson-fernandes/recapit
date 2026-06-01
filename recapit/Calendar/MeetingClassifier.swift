import Foundation

struct ClassifyResult {
    let isMeeting: Bool
    let detectedURL: URL?
}

enum MeetingClassifier {
    private static let urlPattern = #"(?i)https?://[^\s]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|whereby\.com|webex\.com|gotomeet|join\.me|hangouts\.google\.com)[^\s]*"#

    static func classify(title: String?, notes: String?, location: String?, url: URL?, attendeeCount: Int) -> ClassifyResult {
        let haystack = [notes ?? "", location ?? "", url?.absoluteString ?? "", title ?? ""].joined(separator: " ")
        if let detected = firstMatch(in: haystack) {
            return ClassifyResult(isMeeting: true, detectedURL: detected)
        }
        if attendeeCount >= 2 {
            return ClassifyResult(isMeeting: true, detectedURL: nil)
        }
        return ClassifyResult(isMeeting: false, detectedURL: nil)
    }

    private static func firstMatch(in s: String) -> URL? {
        guard let re = try? NSRegularExpression(pattern: urlPattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range),
              let r = Range(m.range, in: s) else { return nil }
        return URL(string: String(s[r]))
    }
}
