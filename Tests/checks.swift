import Foundation
@main struct Checks {
    static func main() throws {
        Localization.shared.language = "ru"
        precondition(L("Missing {0} / {1}", "{1}", "value") == "Missing {1} / value", "Localization modified substituted user input")
        Localization.shared.language = "system"
        precondition(Localization.languages.count > 20)
        let literal = "a'$(printf injected)\\\" space\nline"
        let result = try runCommand("/bin/sh", ["-c", "printf '%s' " + shellQuote(literal)])
        precondition(result.code == 0 && String(decoding: result.data, as: UTF8.self) == literal, "Shell quoting changed input")
        let status = WriteProgress(line: "verify\t512\t1024\t256")
        precondition(status?.fraction == 0.5 && status?.phase == "verify")
        precondition(WriteProgress(line: "broken") == nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.img")
        try Data(repeating: 42, count: 512).write(to: url)
        let validImage = try ImageFile(url: url)
        precondition(validImage.size == 512)
        try Data(repeating: 42, count: 513).write(to: url)
        do { _ = try ImageFile(url: url); fatalError("Unaligned image accepted") } catch {}
        var windows = WindowsOptions(); windows.localAccount = true; windows.password = "<&\"'"
        let xml = try windows.answer()
        precondition(xml.contains("&lt;&amp;&quot;&apos;"))
        precondition(!xml.contains("WillWipeDisk"))
        let checksURL = dir.appendingPathComponent("hash.txt"); try Data("abc".utf8).write(to: checksURL)
        let hashes = try ImageHashes.calculate(checksURL)
        precondition(hashes.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        precondition(WriteProgress(line: "write\t1\t2\tnan") == nil)
        let links = CatalogResolver.links(in: "<a href='ubuntu-26.04.1-desktop-amd64.iso'>ISO</a><a href='ubuntu-26.04.2-desktop-amd64.iso'>ISO</a><a href='evil.iso'>wrong</a>", relativeTo: URL(string: "https://releases.ubuntu.com/26.04/")!)
        precondition(CatalogResolver.newestISO(links, matching: "ubuntu-.*-desktop-amd64\\.iso$")?.lastPathComponent == "ubuntu-26.04.2-desktop-amd64.iso")
        let hash = String(repeating: "a", count: 64)
        precondition(CatalogResolver.sha256(in: hash + "  *test.iso", filename: "test.iso") == hash)
        precondition(CatalogResolver.sha256(in: hash + "  test.iso.bad", filename: "test.iso") == nil)
        var customized = WindowsOptions()
        customized.removeTeams = true; customized.removeOutlook = true; customized.disableCopilot = true; customized.disableOneDrive = true; customized.qualityOfLife = true; customized.applySkuPolicy = true
        let customizedXML = try customized.answer()
        precondition(customized.enabled && customized.scriptFiles.count == 2)
        precondition(customizedXML.contains("FirstLogonCommands") && customizedXML.contains("Microsoft-Windows-Deployment"))
        precondition(!customizedXML.contains("EncodedCommand"))
        let firstLogon = customized.customizationScript(user: true)
        precondition(firstLogon.contains("System32\\SecureBootUpdates\\SkuSiPolicy.p7b") && firstLogon.contains("finally { & mountvol.exe $vol /D }"))
        precondition(customized.customizationScript(user: false).contains("Remove-AppxProvisionedPackage"))
        precondition(WindowsOptions.scriptCommand("Mafus-FirstLogon.ps1").count < 1024)
        if CommandLine.arguments.count == 2 {
            let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (name, script) in customized.scriptFiles { try Data(script.utf8).write(to: output.appendingPathComponent(name)) }
            try Data(customizedXML.utf8).write(to: output.appendingPathComponent("autounattend.xml"))
        }
        print("Swift checks passed: shell quoting, progress parsing, image validation")
    }
}
