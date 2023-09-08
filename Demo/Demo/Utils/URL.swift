import Foundation

extension URL {
    // don't use this for navigation -- only deduplication
    var historyKey: String {
        guard var comps = URLComponents(string: absoluteString.lowercased()) else { return absoluteString }
        if comps.scheme == "https" {
            comps.scheme = "http"
        }
        comps.fragment = nil

        var hostParts = (comps.host ?? "").split(separator: ".")
        if hostParts.first == "www" {
            hostParts.removeFirst()
        }
        comps.host = hostParts.joined(separator: ".")

        comps.queryItems = comps.queryItems?.filter { !shouldDropQueryItemForHistoryKey($0.name, val: $0.value) }
        var str = comps.url?.absoluteString ?? absoluteString
        if str.hasSuffix("/") {
            str.removeLast()
        }
        return str
    }
}

private func shouldDropQueryItemForHistoryKey(_ name: String, val: String?) -> Bool {
    if (val ?? "") == "" {
        return true
    }
    if name.hasPrefix("utm_") {
        return true
    }
    return false
}
