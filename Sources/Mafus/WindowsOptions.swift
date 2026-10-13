import Foundation

struct WindowsOptions {
    var bypassHardware = false
    var localAccount = false
    var username = "User"
    var password = ""
    var privacy = false
    var disableEncryption = false
    var removeTeams = false
    var removeOutlook = false
    var disableCopilot = false
    var disableOneDrive = false
    var qualityOfLife = false
    var applySkuPolicy = false
    var locale = ""
    var timeZone = ""
    var customAnswer: URL?
    var enabled: Bool { bypassHardware || localAccount || privacy || disableEncryption || !locale.isEmpty || !timeZone.isEmpty || removeTeams || removeOutlook || disableCopilot || disableOneDrive || qualityOfLife || applySkuPolicy }
    func answer() throws -> String {
        if localAccount && (username.isEmpty || username.count > 20 || username.contains(where: { "/\\[]:;|=,+*?<>@\"".contains($0) })) { throw MafusError.message("Некорректное имя локального пользователя Windows.") }
        func component(_ name: String, _ body: String) -> String {
            "<component name=\"\(name)\" processorArchitecture=\"MAFUS_ARCH\" publicKeyToken=\"31bf3856ad364e35\" language=\"neutral\" versionScope=\"nonSxS\">\(body)</component>"
        }
        var pe = ""
        if bypassHardware {
            let checks = ["TPM", "SecureBoot", "RAM", "CPU"]
            let commands = checks.enumerated().map { index, check in
                let command = "reg add HKLM\\SYSTEM\\Setup\\LabConfig /v Bypass\(check)Check /t REG_DWORD /d 1 /f"
                return "<RunSynchronousCommand wcm:action=\"add\"><Order>\(index + 1)</Order><Path>\(xmlEscape(command))</Path></RunSynchronousCommand>"
            }.joined()
            pe = component("Microsoft-Windows-Setup", "<RunSynchronous>\(commands)</RunSynchronous>")
        }
        var shell = ""
        var oobe = ""
        if localAccount {
            oobe += "<HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>"
            shell += "<UserAccounts><LocalAccounts><LocalAccount wcm:action=\"add\"><Name>\(xmlEscape(username))</Name><DisplayName>\(xmlEscape(username))</DisplayName><Group>Administrators</Group><Password><Value>\(xmlEscape(password))</Value><PlainText>true</PlainText></Password></LocalAccount></LocalAccounts></UserAccounts>"
        }
        if privacy { oobe += "<ProtectYourPC>3</ProtectYourPC>" }
        if !oobe.isEmpty { shell += "<OOBE>\(oobe)</OOBE>" }
        if !timeZone.isEmpty { shell += "<TimeZone>\(xmlEscape(timeZone))</TimeZone>" }
        var specialize = ""
        let machineScript = customizationScript(user: false)
        if !machineScript.isEmpty {
            let path = xmlEscape(Self.scriptCommand("Mafus-Specialize.ps1"))
            specialize += component("Microsoft-Windows-Deployment", "<RunSynchronous><RunSynchronousCommand wcm:action=\"add\"><Order>1</Order><Path>\(path)</Path></RunSynchronousCommand></RunSynchronous>")
        }
        let userScript = customizationScript(user: true)
        if !userScript.isEmpty {
            let command = xmlEscape(Self.scriptCommand("Mafus-FirstLogon.ps1"))
            shell += "<FirstLogonCommands><SynchronousCommand wcm:action=\"add\"><Order>1</Order><Description>Mafus customization</Description><CommandLine>\(command)</CommandLine><RequiresUserInput>false</RequiresUserInput></SynchronousCommand></FirstLogonCommands>"
        }
        if disableEncryption { specialize += component("Microsoft-Windows-SecureStartup-FilterDriver", "<PreventDeviceEncryption>true</PreventDeviceEncryption>") }
        var oobeComponents = shell.isEmpty ? "" : component("Microsoft-Windows-Shell-Setup", shell)
        if !locale.isEmpty {
            let value = xmlEscape(locale)
            oobeComponents += component("Microsoft-Windows-International-Core", "<InputLocale>\(value)</InputLocale><SystemLocale>\(value)</SystemLocale><UILanguage>\(value)</UILanguage><UserLocale>\(value)</UserLocale>")
        }
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?><unattend xmlns=\"urn:schemas-microsoft-com:unattend\" xmlns:wcm=\"http://schemas.microsoft.com/WMIConfig/2002/State\"><settings pass=\"windowsPE\">\(pe)</settings><settings pass=\"specialize\">\(specialize)</settings><settings pass=\"oobeSystem\">\(oobeComponents)</settings></unattend>"
    }
    static func scriptCommand(_ name: String) -> String {
        "cmd.exe /c powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%WINDIR%\\Setup\\Scripts\\\(name)\""
    }
    var scriptFiles: [(String, String)] {
        [("Mafus-Specialize.ps1", customizationScript(user: false)), ("Mafus-FirstLogon.ps1", customizationScript(user: true))].filter { !$0.1.isEmpty }
    }
    static func powerShellCommand(_ script: String) -> String {
        let bytes = script.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }
        return "powershell.exe -NoProfile -NonInteractive -EncodedCommand " + Data(bytes).base64EncodedString()
    }
    func customizationScript(user: Bool) -> String {
        var commands: [String] = []
        func policy(_ key: String, _ name: String, _ value: Int) {
            commands.append("New-Item -Path '\(key)' -Force | Out-Null; New-ItemProperty -Path '\(key)' -Name '\(name)' -Value \(value) -PropertyType DWord -Force | Out-Null")
        }
        if !user {
            for (enabled, pattern) in [(removeTeams, "*Teams*"), (removeOutlook, "*Outlook*"), (disableCopilot, "*Copilot*")] where enabled {
                commands.append("Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like '\(pattern)'} | Remove-AppxProvisionedPackage -Online | Out-Null")
            }
            if disableOneDrive { policy("HKLM:\\Software\\Policies\\Microsoft\\Windows\\OneDrive", "DisableFileSyncNGSC", 1) }
            if disableCopilot { policy("HKLM:\\Software\\Policies\\Microsoft\\Windows\\WindowsCopilot", "TurnOffWindowsCopilot", 1) }
            if removeTeams { policy("HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Communications", "ConfigureChatAutoInstall", 0) }
            if qualityOfLife {
                policy("HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power", "HiberbootEnabled", 0)
                policy("HKLM:\\Software\\Policies\\Microsoft\\Windows\\CloudContent", "DisableWindowsConsumerFeatures", 1)
                policy("HKLM:\\Software\\Policies\\Microsoft\\Dsh", "AllowNewsAndInterests", 0)
            }
        } else {
            for (enabled, pattern) in [(removeTeams, "*Teams*"), (removeOutlook, "*Outlook*"), (disableCopilot, "*Copilot*")] where enabled {
                commands.append("Get-AppxPackage -AllUsers '\(pattern)' | Remove-AppxPackage -AllUsers")
            }
            if disableOneDrive {
                commands.append("Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue; foreach($p in @('System32','SysWOW64')) { $exe=Join-Path $env:WINDIR ($p+'\\OneDriveSetup.exe'); if(Test-Path $exe) { Start-Process $exe -ArgumentList '/uninstall' -Wait } }")
            }
            if disableCopilot { policy("HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "ShowCopilotButton", 0) }
            if qualityOfLife {
                policy("HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "SystemPaneSuggestionsEnabled", 0)
                policy("HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search", "BingSearchEnabled", 0)
            }
            if applySkuPolicy {
                commands.append("$src=Join-Path $env:WINDIR 'System32\\SecureBootUpdates\\SkuSiPolicy.p7b'; if(!(Test-Path $src)) { throw 'Installed Windows has no SkuSiPolicy.p7b' }; $letter=('Z','Y','X','W','V','U','T','S') | Where-Object {!(Test-Path ($_+':\\'))} | Select-Object -First 1; if(!$letter) { throw 'No free ESP mount letter' }; $vol=$letter+':'; & mountvol.exe $vol /S; if($LASTEXITCODE -ne 0) { throw 'Cannot mount installed ESP' }; try { $dir=$vol+'\\EFI\\Microsoft\\Boot'; if(!(Test-Path $dir)) { throw 'Windows ESP directory missing' }; Copy-Item $src (Join-Path $dir 'SkuSiPolicy.p7b') -Force -ErrorAction Stop; if((Get-FileHash $src).Hash -ne (Get-FileHash (Join-Path $dir 'SkuSiPolicy.p7b')).Hash) { throw 'ESP policy verification failed' } } finally { & mountvol.exe $vol /D }")
            }
        }
        guard !commands.isEmpty else { return "" }
        return "$ErrorActionPreference='Continue'; Start-Transcript -Path ($env:WINDIR+'\\Temp\\Mafus-\(user ? "first-logon" : "specialize").log') -Append; try { " + commands.joined(separator: "; ") + " } finally { Stop-Transcript }"
    }

}
func xmlEscape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
}
