import AppKit
import Carbon

final class GlobalHotKey {
    var onPress: (() -> Void)?
    var onCapturePress: (() -> Void)?
    private var historyHotKey: EventHotKeyRef?
    private var captureHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() -> OSStatus {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                owner.onPress?()
            } else if hotKeyID.id == 2 {
                owner.onCapturePress?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return installed }

        let historyIdentifier = EventHotKeyID(signature: 0x434C4950, id: 1)
        let res1 = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(optionKey | cmdKey), historyIdentifier,
                                       GetApplicationEventTarget(), 0, &historyHotKey)

        let captureIdentifier = EventHotKeyID(signature: 0x434C4950, id: 2)
        _ = RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(optionKey | cmdKey), captureIdentifier,
                                GetApplicationEventTarget(), 0, &captureHotKey)

        return res1
    }

    deinit {
        if let historyHotKey { UnregisterEventHotKey(historyHotKey) }
        if let captureHotKey { UnregisterEventHotKey(captureHotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
