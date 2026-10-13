import Foundation
import DiskArbitration
import IOKit

enum DeviceRegistry {
    static func attachmentID(_ bsdName: String) -> UInt64 {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return 0 }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        var value: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(service, &value) == KERN_SUCCESS ? value : 0
    }
}

final class DeviceWatcher {
    private let session: DASession
    private let changed: () -> Void
    init?(_ changed: @escaping () -> Void) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        self.session = session; self.changed = changed
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, deviceChanged, context)
        DARegisterDiskDisappearedCallback(session, nil, deviceChanged, context)
        DASessionSetDispatchQueue(session, DispatchQueue.main)
    }
    fileprivate func notify() { changed() }
    deinit {
        DAUnregisterCallback(session, unsafeBitCast(deviceChanged, to: UnsafeMutableRawPointer.self), Unmanaged.passUnretained(self).toOpaque())
        DASessionSetDispatchQueue(session, nil)
    }
}

private let deviceChanged: DADiskAppearedCallback = { _, context in
    guard let context else { return }
    Unmanaged<DeviceWatcher>.fromOpaque(context).takeUnretainedValue().notify()
}
