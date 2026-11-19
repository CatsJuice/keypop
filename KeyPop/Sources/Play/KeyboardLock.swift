import AppKit
import ApplicationServices

/// 全局键盘锁：用 CGEventTap 在系统层面吞掉所有键盘事件（包括 Raycast/Spotlight 的全局快捷键、
/// ⌘Tab、⌘Q、⌘,、媒体键等），再转交给 App 自己处理。需要“辅助功能”权限。
final class KeyboardLock {
    struct Event {
        let code: Int
        let isDown: Bool
        let isRepeat: Bool
        let flags: NSEvent.ModifierFlags
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((Event) -> Void)?
    private var lastFlags: CGEventFlags = []

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权提示（并把 App 加进“辅助功能”列表）
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    var isActive: Bool { tap != nil }

    @discardableResult
    func start(_ handler: @escaping (Event) -> Void) -> Bool {
        stop()
        self.handler = handler
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask: CGEventMask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        mask |= 1 << 14   // NX_SYSDEFINED：亮度、音量、播放等媒体键
        let ref = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, ref in
            guard let ref else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyboardLock>.fromOpaque(ref).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: ref) else {
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lastFlags = []
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        handler = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let rep = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            handler?(Event(code: code, isDown: type == .keyDown, isRepeat: rep, flags: Self.flags(event.flags)))
            return nil
        case .flagsChanged:
            // 修饰键按下也算一次按键
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let added = event.flags.rawValue & ~lastFlags.rawValue
            lastFlags = event.flags
            let isDown = added & (CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue |
                                  CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue |
                                  CGEventFlags.maskAlphaShift.rawValue | CGEventFlags.maskSecondaryFn.rawValue) != 0
            handler?(Event(code: code, isDown: isDown, isRepeat: false, flags: Self.flags(event.flags)))
            return nil
        default:
            if type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
                let key = (ns.data1 & 0xFFFF_0000) >> 16
                let down = ((ns.data1 & 0xFF00) >> 8) == 0x0A
                let rep = (ns.data1 & 0x1) != 0
                handler?(Event(code: 1000 + key, isDown: down, isRepeat: rep, flags: []))
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
    }

    static func flags(_ f: CGEventFlags) -> NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if f.contains(.maskControl) { m.insert(.control) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskCommand) { m.insert(.command) }
        if f.contains(.maskShift) { m.insert(.shift) }
        return m
    }
}
