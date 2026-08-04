// scripts/e2e/axdriver.swift
//
// Reliable accessibility-driven UI driver for Simpleton E2E testing. Compiles with the Command
// Line Tools (no Xcode). Element-addressed (not coordinate-addressed), so it's immune to window
// moves/resize/Retina scaling and the focus-stealing that plagues System Events scripting.
//
// Build:  swiftc -O -o /tmp/axdriver scripts/e2e/axdriver.swift
// Usage:
//   axdriver tree <pid> [maxDepth]        # dump the AX tree (role #identifier "title" =value)
//   axdriver raise <pid>                  # raise the app's front window + activate
//   axdriver windowid <pid>               # print the front window's CGWindowID
//   axdriver shot <pid> <out.png>         # raise + screenshot the window (occlusion-independent)
//   axdriver press <pid> <identifier>     # find a control by AXIdentifier and press it
//   axdriver presstitle <pid> <title>     # find a control by AXTitle and press it
//   axdriver type <pid> <text>            # type Unicode text into the focused element
//   axdriver key  <pid> <virtualKeyCode>  # send a key (36=return, 53=esc, 48=tab)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}
func role(_ e: AXUIElement) -> String { (attr(e, kAXRoleAttribute as String) as? String) ?? "?" }
func ident(_ e: AXUIElement) -> String { (attr(e, kAXIdentifierAttribute as String) as? String) ?? "" }
func title(_ e: AXUIElement) -> String { (attr(e, kAXTitleAttribute as String) as? String) ?? "" }
func valueStr(_ e: AXUIElement) -> String { (attr(e, kAXValueAttribute as String) as? String) ?? "" }

func dumpTree(_ e: AXUIElement, _ depth: Int, _ maxDepth: Int) {
    let r = role(e), id = ident(e), t = title(e), v = valueStr(e)
    var line = String(repeating: "  ", count: depth) + r
    if !id.isEmpty { line += " #\(id)" }
    if !t.isEmpty { line += " \"\(t.prefix(48))\"" }
    if !v.isEmpty, v.count < 48 { line += " =\(v)" }
    print(line)
    if depth < maxDepth { for c in children(e) { dumpTree(c, depth + 1, maxDepth) } }
}

func find(_ e: AXUIElement, id: String, _ depth: Int = 0) -> AXUIElement? {
    if ident(e) == id { return e }
    if depth > 60 { return nil }
    for c in children(e) { if let hit = find(c, id: id, depth + 1) { return hit } }
    return nil
}
func findTitle(_ e: AXUIElement, _ wanted: String, _ depth: Int = 0) -> AXUIElement? {
    if title(e) == wanted { return e }
    if depth > 60 { return nil }
    for c in children(e) { if let hit = findTitle(c, wanted, depth + 1) { return hit } }
    return nil
}

func windowID(pid: pid_t, nameContains: String? = nil) -> CGWindowID? {
    let list =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for w in list
    where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
        if let filter = nameContains, !filter.isEmpty {
            let name = (w[kCGWindowName as String] as? String) ?? ""
            guard name.localizedCaseInsensitiveContains(filter) else { continue }
        }
        if let num = w[kCGWindowNumber as String] as? CGWindowID { return num }
    }
    return nil
}

func raise(pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    if let win = (attr(app, kAXWindowsAttribute as String) as? [AXUIElement])?.first {
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    }
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    usleep(400_000)
}

func err(_ m: String) { FileHandle.standardError.write((m + "\n").data(using: .utf8)!) }

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[2]) else {
    err("usage: axdriver <tree|raise|windowid|shot|press|presstitle|type|key> <pid> [...]")
    exit(64)
}
guard AXIsProcessTrusted() else {
    err("Accessibility permission not granted to the controlling process.")
    exit(2)
}
let app = AXUIElementCreateApplication(pid)

switch args[1] {
case "tree":
    dumpTree(app, 0, args.count > 3 ? (Int(args[3]) ?? 12) : 12)
case "raise":
    raise(pid: pid)
case "windowid":
    if let id = windowID(pid: pid) { print(id) } else { exit(1) }
case "shot":
    guard args.count > 3 else { exit(64) }
    raise(pid: pid)
    let nameFilter = args.count > 4 ? args[4] : nil  // optional: match window by title substring
    guard let id = windowID(pid: pid, nameContains: nameFilter) else {
        err("no on-screen window for pid \(pid)\(nameFilter.map { " matching \($0)" } ?? "")")
        exit(1)
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l\(id)", "-o", "-x", args[3]]
    try? p.run()
    p.waitUntilExit()
    exit(p.terminationStatus == 0 ? 0 : 1)
case "press", "presstitle":
    guard args.count > 3 else { exit(64) }
    let target = args[1] == "press" ? find(app, id: args[3]) : findTitle(app, args[3])
    guard let el = target else { err("element not found: \(args[3])"); exit(1) }
    exit(AXUIElementPerformAction(el, kAXPressAction as CFString) == .success ? 0 : 1)
case "type":
    guard args.count > 3 else { exit(64) }
    raise(pid: pid)
    let src = CGEventSource(stateID: .combinedSessionState)
    for scalar in args[3].unicodeScalars {
        var ch = UniChar(scalar.value)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
        up?.post(tap: .cghidEventTap)
        usleep(6000)
    }
case "key":
    // key <pid> <virtualKeyCode> [modifiers]   e.g. key <pid> 17 cmd   (⌘T)
    guard args.count > 3, let code = UInt16(args[3]) else { exit(64) }
    raise(pid: pid)
    var flags: CGEventFlags = []
    if args.count > 4 {
        for m in args[4].lowercased().split(separator: ",") {
            switch m {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }
    }
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
case "menu":
    // menu <pid> <menuItemTitle>   — fast: searches only the app menu bar, then presses.
    guard args.count > 3 else { exit(64) }
    guard let menuBarRef = attr(app, kAXMenuBarAttribute as String) else { err("no menu bar"); exit(1) }
    // swift-format-ignore: force-unwrap is safe — kAXMenuBar always yields an AXUIElement.
    let menuBar = menuBarRef as! AXUIElement
    guard let item = findTitle(menuBar, args[3]) else { err("menu item not found: \(args[3])"); exit(1) }
    exit(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? 0 : 1)
default:
    err("unknown command: \(args[1])")
    exit(64)
}
