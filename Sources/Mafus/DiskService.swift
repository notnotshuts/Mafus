import Foundation

enum DiskService {
    static func list() throws -> [USBDrive] {
        let result = try runCommand("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"])
        guard result.code == 0 else { throw MafusError.message(result.error) }
        guard let root = try PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any],
              let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        return try disks.compactMap { disk in
            guard let id = disk["DeviceIdentifier"] as? String else { return nil }
            let infoResult = try runCommand("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(id)"])
            guard infoResult.code == 0,
                  let info = try PropertyListSerialization.propertyList(from: infoResult.data, format: nil) as? [String: Any],
                  (info["WholeDisk"] as? Bool == true || info["Whole"] as? Bool == true), info["Internal"] as? Bool == false,
                  info["BusProtocol"] as? String == "USB",
                  (info["RemovableMedia"] as? Bool == true || info["Ejectable"] as? Bool == true),
                  let size = info["TotalSize"] as? Int64, size > 0 else { return nil }
            let attachment = DeviceRegistry.attachmentID(id)
            guard attachment != 0 else { return nil }
            return USBDrive(id: id, name: info["MediaName"] as? String ?? L("USB-накопитель"), size: size, attachmentID: attachment)
        }
    }
}
