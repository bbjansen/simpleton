// window-id.swift — list on-screen window IDs for an app, so screenshots can target
// a specific window by CoreGraphics ID (screencapture -l<id>), which captures the
// window's bitmap regardless of z-order/occlusion. Robust for unbundled apps that
// don't reliably come to the front.
//
// Usage:  swift scripts/e2e/window-id.swift <AppOwnerName>
// Output (tab-separated): windowNumber  layer  WxH  ownerName  windowName
// Sorted by area descending (largest first) so the main window is line 1.
import CoreGraphics
import Foundation

let appName = CommandLine.arguments.dropFirst().first ?? ""
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write("failed to read window list\n".data(using: .utf8)!)
    exit(1)
}

struct Win { let num: Int; let layer: Int; let w: Int; let h: Int; let owner: String; let name: String }
var wins: [Win] = []
for entry in list {
    let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
    if !appName.isEmpty && owner != appName { continue }
    let num = entry[kCGWindowNumber as String] as? Int ?? -1
    let layer = entry[kCGWindowLayer as String] as? Int ?? 0
    let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let w = Int(bounds["Width"] ?? 0), h = Int(bounds["Height"] ?? 0)
    let name = entry[kCGWindowName as String] as? String ?? ""
    wins.append(Win(num: num, layer: layer, w: w, h: h, owner: owner, name: name))
}
wins.sort { ($0.w * $0.h) > ($1.w * $1.h) }
for x in wins {
    print("\(x.num)\t\(x.layer)\t\(x.w)x\(x.h)\t\(x.owner)\t\(x.name)")
}
