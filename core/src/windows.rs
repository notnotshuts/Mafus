use super::*;
use std::{
    collections::HashSet,
    os::unix::fs::DirBuilderExt,
    time::{SystemTime, UNIX_EPOCH},
};
const FAT_MAX: u64 = 0xffff_ffff;

pub struct Workspace {
    pub path: PathBuf,
}
impl Workspace {
    pub fn new() -> Result<Self> {
        static SERIAL: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let serial = SERIAL.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let parent = if cfg!(test) {
            env::temp_dir()
        } else {
            PathBuf::from("/var/tmp")
        };
        let path = parent.join(format!(
            "mafus-work-{}-{nonce}-{serial}",
            std::process::id()
        ));
        fs::DirBuilder::new().mode(0o700).create(&path)?;
        Ok(Self { path })
    }
}
impl Drop for Workspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

pub struct MountedImage {
    workspace: Workspace,
    pub root: PathBuf,
    device: String,
}
impl MountedImage {
    pub fn open(image: &Path) -> Result<Self> {
        let workspace = Workspace::new()?;
        let root = workspace.path.join("image");
        fs::create_dir(&root)?;
        let output = Command::new("/usr/bin/hdiutil")
            .args(["attach", "-readonly", "-nobrowse", "-plist", "-mountpoint"])
            .arg(&root)
            .arg(image)
            .output()?;
        if !output.status.success() {
            return Err(format!(
                "Cannot mount ISO: {}",
                String::from_utf8_lossy(&output.stderr)
            )
            .into());
        }
        let canonical_root = fs::canonicalize(&root)?;
        let mut mounted = Self {
            workspace,
            root: canonical_root.clone(),
            device: root.to_string_lossy().into_owned(),
        };
        let parsed = Value::from_reader_xml(output.stdout.as_slice())?;
        let entities = parsed
            .as_dictionary()
            .and_then(|d| d.get("system-entities"))
            .and_then(Value::as_array)
            .ok_or("ISO mount metadata missing")?;
        let device = entities
            .iter()
            .filter_map(Value::as_dictionary)
            .find(|d| d.get("mount-point").and_then(Value::as_string) == canonical_root.to_str())
            .and_then(|d| d.get("dev-entry"))
            .and_then(Value::as_string)
            .ok_or("ISO mount point missing")?
            .to_owned();
        mounted.device = device;
        Ok(mounted)
    }
    pub fn is_windows(&self) -> bool {
        child(&self.root, "sources")
            .and_then(|p| child(&p, "boot.wim"))
            .is_some()
            && child(&self.root, "setup.exe").is_some()
    }
}
impl Drop for MountedImage {
    fn drop(&mut self) {
        // Never remove a workspace while a filesystem is still mounted there.
        if !Command::new("/usr/bin/hdiutil")
            .args(["detach", &self.device])
            .output()
            .is_ok_and(|out| out.status.success())
        {
            let path = std::mem::take(&mut self.workspace.path);
            // Keep the empty mount directory for manual cleanup if detaching fails.
            self.workspace.path = PathBuf::new();
            eprintln!("ISO could not be detached; retained {}", path.display());
        }
    }
}
fn child(root: &Path, name: &str) -> Option<PathBuf> {
    fs::read_dir(root)
        .ok()?
        .filter_map(|e| e.ok())
        .find(|e| e.file_name().to_string_lossy().eq_ignore_ascii_case(name))
        .map(|e| e.path())
}
#[derive(Clone, Debug)]
pub struct Entry {
    pub source: PathBuf,
    pub relative: PathBuf,
    pub size: u64,
}
fn walk(
    root: &Path,
    folder: &Path,
    entries: &mut Vec<Entry>,
    seen: &mut HashSet<String>,
) -> Result<()> {
    let mut children: Vec<_> = fs::read_dir(folder)?.collect::<std::result::Result<_, _>>()?;
    children.sort_by_key(|entry| entry.file_name());
    for entry in children {
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            return Err("ISO contains symlinks; unsupported Windows media".into());
        }
        let relative = path.strip_prefix(root)?.to_path_buf();
        let name = relative
            .to_str()
            .ok_or("Non-UTF8 filename in Windows image")?;
        if !seen.insert(name.to_lowercase()) {
            return Err("Windows image contains FAT32 filename collisions".into());
        }
        if relative.components().any(|c| {
            c.as_os_str()
                .to_string_lossy()
                .chars()
                .any(|ch| "<>:\"\\|?*".contains(ch))
        }) {
            return Err("Windows image contains a filename unsupported by FAT32".into());
        }
        if metadata.is_dir() {
            walk(root, &path, entries, seen)?;
        } else if metadata.is_file() {
            entries.push(Entry {
                source: path,
                relative,
                size: metadata.len(),
            });
        } else {
            return Err("Unsupported file in Windows image".into());
        }
    }
    Ok(())
}
fn collect(root: &Path) -> Result<Vec<Entry>> {
    let mut entries = Vec::new();
    walk(root, root, &mut entries, &mut HashSet::new())?;
    Ok(entries)
}
pub fn tool() -> Result<PathBuf> {
    let path = env::current_exe()?
        .parent()
        .ok_or("Missing app directory")?
        .join("wimlib-imagex");
    if !path.is_file() {
        return Err("Bundled wimlib-imagex is missing. Rebuild Mafus.app.".into());
    }
    Ok(path)
}
pub struct Plan {
    pub files: Vec<Entry>,
    pub total: u64,
    _workspace: Workspace,
}
impl Plan {
    pub fn prepare(
        image: &MountedImage,
        progress: &mut Progress,
        split_large: bool,
        bios_only: bool,
    ) -> Result<Self> {
        if !image.is_windows() {
            return Err("This is not a Windows installation ISO".into());
        }
        if !bios_only {
            let efi = child(&image.root, "efi")
                .and_then(|p| child(&p, "boot"))
                .ok_or("Windows ISO has no UEFI boot directory")?;
            if ["bootx64.efi", "bootaa64.efi", "bootia32.efi"]
                .iter()
                .all(|name| child(&efi, name).is_none())
            {
                return Err(
                    "Windows ISO is missing its UEFI bootloader; select BIOS-only for BIOS media"
                        .into(),
                );
            }
        }
        let mut files = collect(&image.root)?;
        let start = Instant::now();
        progress.update("prepare", 0, 0, start)?;
        let sources_root = child(&image.root, "sources").ok_or("Missing sources directory")?;
        // Validate Windows payloads before touching the USB, including small WIM/ESD files.
        for name in ["boot.wim", "install.wim", "install.esd", "install.swm"] {
            if let Some(payload) = child(&sources_root, name) {
                let mut command = Command::new(tool()?);
                command.arg("verify").arg(payload);
                if name == "install.swm" {
                    command.arg(format!(
                        "--ref={}",
                        sources_root.join("install*.swm").display()
                    ));
                }
                let output = command.output()?;
                if !output.status.success() {
                    return Err(format!(
                        "Invalid Windows payload {name}: {}",
                        String::from_utf8_lossy(&output.stderr)
                    )
                    .into());
                }
                progress.update("prepare", 0, 0, start)?;
            }
        }
        let sources = child(&image.root, "sources").ok_or("Missing sources directory")?;
        if child(&sources, "install.wim").is_none()
            && child(&sources, "install.esd").is_none()
            && child(&sources, "install.swm").is_none()
        {
            return Err("Windows installation payload is missing".into());
        }
        let workspace = Workspace::new()?;
        let start = Instant::now();
        progress.update("prepare", 0, 0, start)?;
        let large: Vec<_> = files
            .iter()
            .filter(|e| split_large && e.size > FAT_MAX)
            .cloned()
            .collect();
        for entry in large {
            let normalized = entry.relative.to_string_lossy().to_lowercase();
            if normalized != "sources/install.wim" && normalized != "sources/install.esd" {
                return Err(
                    format!("{} exceeds the FAT32 file limit", entry.relative.display()).into(),
                );
            }
            let split_input = if normalized.ends_with(".esd") {
                let converted = workspace.path.join("converted.wim");
                let output = Command::new(tool()?)
                    .arg("export")
                    .arg(&entry.source)
                    .arg("all")
                    .arg(&converted)
                    .args(["--compress=LZX", "--check"])
                    .output()?;
                if !output.status.success() {
                    return Err(format!(
                        "ESD conversion failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    )
                    .into());
                }
                converted
            } else {
                entry.source.clone()
            };
            let split_dir = workspace.path.join("split");
            fs::create_dir(&split_dir)?;
            let output = Command::new(tool()?)
                .arg("split")
                .arg(split_input)
                .arg(split_dir.join("install.swm"))
                .args(["3800", "--check"])
                .output()?;
            if !output.status.success() {
                return Err(format!(
                    "WIM split failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                )
                .into());
            }
            let output = Command::new(tool()?)
                .arg("verify")
                .arg(split_dir.join("install.swm"))
                .arg(format!(
                    "--ref={}",
                    split_dir.join("install*.swm").display()
                ))
                .output()?;
            if !output.status.success() {
                return Err(format!(
                    "Split WIM verification failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                )
                .into());
            }
            files.retain(|e| e.relative != entry.relative);
            for mut split in collect(&split_dir)? {
                if split.size > FAT_MAX {
                    return Err(
                        "A split WIM resource exceeds 4 GiB; this ISO cannot be put on FAT32"
                            .into(),
                    );
                }
                split.relative = PathBuf::from("sources").join(split.relative);
                if files.iter().any(|e| {
                    e.relative
                        .to_string_lossy()
                        .eq_ignore_ascii_case(&split.relative.to_string_lossy())
                }) {
                    return Err("Split WIM would overwrite an existing ISO file".into());
                }
                files.push(split);
            }
        }
        let total = files.iter().try_fold(0u64, |sum, entry| {
            sum.checked_add(entry.size).ok_or("Image size overflow")
        })?;
        Ok(Self {
            files,
            total,
            _workspace: workspace,
        })
    }
    pub fn required_capacity(&self) -> u64 {
        self.total
            .saturating_add(self.files.len() as u64 * 65536)
            .saturating_add(64 * 1024 * 1024)
    }
}
pub fn target_partition(options: &Options) -> Result<String> {
    let output = Command::new("/usr/sbin/diskutil")
        .args(["list", "-plist", &options.device])
        .output()?;
    if !output.status.success() {
        return Err("Cannot list new USB partitions".into());
    }
    let parsed = Value::from_reader_xml(output.stdout.as_slice())?;
    let disks = parsed
        .as_dictionary()
        .and_then(|d| d.get("AllDisksAndPartitions"))
        .and_then(Value::as_array)
        .ok_or("Missing USB partition metadata")?;
    let id = disks
        .iter()
        .filter_map(Value::as_dictionary)
        .flat_map(|d| {
            d.get("Partitions")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
        })
        .filter_map(Value::as_dictionary)
        .find(|d| text(d, "VolumeName") == options.label)
        .map(|d| text(d, "DeviceIdentifier").to_owned())
        .ok_or("New partition not found")?;
    let metadata = info(&format!("/dev/{id}"))?;
    if text(&metadata, "ParentWholeDisk") != options.device.trim_start_matches("/dev/")
        || boolean(&metadata, "Internal")
    {
        return Err("Partition belongs to an unexpected disk".into());
    }
    Ok(format!("/dev/{id}"))
}
fn target_mount(options: &Options) -> Result<PathBuf> {
    let partition = target_partition(options)?;
    let metadata = info(&partition)?;
    let mount = text(&metadata, "MountPoint");
    if !mount.starts_with("/Volumes/") || !Path::new(mount).is_dir() {
        return Err("USB was not mounted".into());
    }
    Ok(mount.into())
}

pub fn write_windows(
    options: &Options,
    image: &MountedImage,
    progress: &mut Progress,
) -> Result<()> {
    if options.boot_target != "uefi" && options.filesystem != "NTFS" {
        return Err("BIOS/CSM Windows requires NTFS and MBR".into());
    }
    // Mounting, conversion, splitting, capacity checks all finish before erasing.
    let mut plan = Plan::prepare(
        image,
        progress,
        options.filesystem != "NTFS",
        options.boot_target == "bios",
    )?;
    if let Some(answer) = &options.answer {
        require_internal_source(answer)?;
        if answer.metadata()?.len() > 1024 * 1024 {
            return Err("Answer file is too large".into());
        }
        let mut data = fs::read(answer)?;
        let architecture = if child(&image.root, "efi")
            .and_then(|p| child(&p, "boot"))
            .and_then(|p| child(&p, "bootaa64.efi"))
            .is_some()
        {
            "arm64"
        } else if child(&image.root, "efi")
            .and_then(|p| child(&p, "boot"))
            .and_then(|p| child(&p, "bootx64.efi"))
            .is_some()
        {
            "amd64"
        } else {
            let boot = child(&image.root, "sources")
                .and_then(|p| child(&p, "boot.wim"))
                .ok_or("Missing boot WIM")?;
            let output = Command::new(tool()?)
                .arg("info")
                .arg(boot)
                .arg("--xml")
                .output()?;
            if !output.status.success() {
                return Err("Cannot detect Windows architecture".into());
            }
            let xml = decode_answer(&output.stdout)?;
            wim_architecture(&xml)?
        };
        let text = decode_answer(&data)?;
        let text = text.replace(
            "processorArchitecture=\"MAFUS_ARCH\"",
            &format!("processorArchitecture=\"{architecture}\""),
        );
        validate_answer(&text)?;
        data = text.into_bytes();
        let relative = PathBuf::from("autounattend.xml");
        if plan.files.iter().any(|e| {
            e.relative
                .to_string_lossy()
                .eq_ignore_ascii_case("autounattend.xml")
        }) {
            return Err(
                "The ISO already contains autounattend.xml; refusing to overwrite it".into(),
            );
        }
        let staged = plan._workspace.path.join("autounattend.xml");
        fs::write(&staged, &data)?;
        plan.total += data.len() as u64;
        plan.files.push(Entry {
            source: staged,
            relative,
            size: data.len() as u64,
        });
    }
    if let Some(directory) = &options.customizations {
        require_internal_source(directory)?;
        for name in ["Mafus-Specialize.ps1", "Mafus-FirstLogon.ps1"] {
            let original = directory.join(name);
            if !original.exists() {
                continue;
            }
            let metadata = fs::symlink_metadata(&original)?;
            if !metadata.is_file() || metadata.len() > 128 * 1024 {
                return Err("Invalid customization script".into());
            }
            let relative = PathBuf::from("sources/$OEM$/$$/Setup/Scripts").join(name);
            if plan.files.iter().any(|entry| {
                entry
                    .relative
                    .to_string_lossy()
                    .eq_ignore_ascii_case(&relative.to_string_lossy())
            }) {
                return Err("ISO already contains a Mafus customization script".into());
            }
            let staged = plan._workspace.path.join(name);
            fs::copy(original, &staged)?;
            plan.total += metadata.len();
            plan.files.push(Entry {
                source: staged,
                relative,
                size: metadata.len(),
            });
        }
    }
    if options.filesystem == "NTFS" {
        return super::ntfs::write_windows(
            options,
            &plan.files,
            plan.required_capacity(),
            progress,
        );
    }
    let scheme_reserve = if options.scheme == "GPT" {
        200 * 1024 * 1024
    } else {
        0
    };
    if plan.required_capacity().saturating_add(scheme_reserve) > options.size {
        return Err(
            "USB capacity is insufficient for extracted Windows files and FAT32 overhead".into(),
        );
    }
    let identity = validate(options)?;
    let start = Instant::now();
    progress.update("format", 0, 0, start)?;
    if validate(options)? != identity {
        return Err("USB changed before formatting".into());
    }
    if options.filesystem != "FAT32" {
        return Err("Windows UEFI requires FAT32 in this version".into());
    }
    tools::format(options, progress)?;
    if validate(options)? != identity {
        return Err("USB changed after formatting".into());
    }
    let mount = target_mount(options)?;
    copy_files(&plan.files, &mount, plan.total, progress)?;
    if options.verify {
        verify_files(&plan.files, &mount, plan.total, progress)?;
    }
    let output = Command::new("/usr/sbin/diskutil")
        .args(["unmountDisk", &options.device])
        .output()?;
    if !output.status.success() {
        return Err("Files copied, but USB could not be safely unmounted".into());
    }
    Ok(())
}
fn copy_files(files: &[Entry], mount: &Path, total: u64, progress: &mut Progress) -> Result<()> {
    let start = Instant::now();
    let mut done = 0;
    for entry in files {
        let target = mount.join(&entry.relative);
        fs::create_dir_all(target.parent().ok_or("Invalid destination")?)?;
        let mut input = File::open(&entry.source)?;
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .custom_flags(0x100)
            .open(&target)?;
        copy_image(&mut input, &mut output, entry.size, |count| {
            progress.update("copy", done + count, total, start)
        })?;
        done += entry.size;
    }
    Ok(())
}
fn verify_files(files: &[Entry], mount: &Path, total: u64, progress: &mut Progress) -> Result<()> {
    let start = Instant::now();
    let mut done = 0;
    for entry in files {
        let mut input = File::open(&entry.source)?;
        let mut actual = File::open(mount.join(&entry.relative))?;
        if actual.metadata()?.len() != entry.size {
            return Err("Copied Windows file has incorrect size".into());
        }
        disable_cache(&actual)?;
        verify_image(&mut input, &mut actual, entry.size, |count| {
            progress.update("verify", done + count, total, start)
        })?;
        done += entry.size;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_symlinks_and_case_collisions() -> Result<()> {
        let temp = Workspace::new()?;
        fs::write(temp.path.join("file"), b"test")?;
        std::os::unix::fs::symlink("file", temp.path.join("link"))?;
        assert!(collect(&temp.path).is_err());
        fs::remove_file(temp.path.join("link"))?;
        // Case collisions are checked on all hosts, even with a case-insensitive filesystem.
        let mut entries = Vec::new();
        let mut seen = HashSet::new();
        seen.insert("file".to_owned());
        assert!(walk(&temp.path, &temp.path, &mut entries, &mut seen).is_err());
        Ok(())
    }
    #[test]
    fn windows_copy_verifies_nested_files() -> Result<()> {
        let temp = Workspace::new()?;
        let source = temp.path.join("source");
        let dest = temp.path.join("dest");
        fs::create_dir_all(source.join("efi/boot"))?;
        fs::create_dir(&dest)?;
        fs::write(source.join("efi/boot/bootx64.efi"), b"efi fixture")?;
        fs::write(source.join("setup.exe"), b"setup fixture")?;
        let files = collect(&source)?;
        let total = files.iter().map(|e| e.size).sum();
        let log = env::temp_dir().join(format!(
            "mafus-test-{}.progress",
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let mut progress = Progress::new(&log)?;
        copy_files(&files, &dest, total, &mut progress)?;
        verify_files(&files, &dest, total, &mut progress)?;
        fs::write(dest.join("setup.exe"), b"bad fixture!!")?;
        assert!(verify_files(&files, &dest, total, &mut progress).is_err());
        Ok(())
    }
}

pub fn describe(image: &Path) -> Result<()> {
    let mounted = MountedImage::open(image)?;
    if !mounted.is_windows() {
        return Err("Not a Windows installation ISO".into());
    }
    let sources = child(&mounted.root, "sources").ok_or("Missing sources")?;
    let payload = child(&sources, "install.wim")
        .or_else(|| child(&sources, "install.esd"))
        .ok_or("WIM/ESD payload missing")?;
    let output = Command::new(tool()?).arg("info").arg(payload).output()?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
    }
    println!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}

fn wim_architecture(xml: &str) -> Result<&'static str> {
    if xml.contains("<ARCH>12</ARCH>") {
        Ok("arm64")
    } else if xml.contains("<ARCH>9</ARCH>") {
        Ok("amd64")
    } else if xml.contains("<ARCH>0</ARCH>") {
        Ok("x86")
    } else {
        Err("Unsupported Windows WIM architecture".into())
    }
}
fn decode_answer(data: &[u8]) -> Result<String> {
    let mut text = if data.starts_with(&[0xff, 0xfe]) || data.starts_with(&[0xfe, 0xff]) {
        if data.len() % 2 != 0 {
            return Err("Invalid UTF-16 answer file".into());
        }
        let little = data.starts_with(&[0xff, 0xfe]);
        let units: Vec<u16> = data[2..]
            .chunks_exact(2)
            .map(|b| {
                if little {
                    u16::from_le_bytes([b[0], b[1]])
                } else {
                    u16::from_be_bytes([b[0], b[1]])
                }
            })
            .collect();
        String::from_utf16(&units)?
    } else {
        String::from_utf8(
            data.strip_prefix(&[0xef, 0xbb, 0xbf])
                .unwrap_or(data)
                .to_vec(),
        )?
    };
    for encoding in ["utf-16", "UTF-16", "UTF-16LE", "UTF-16BE"] {
        text = text
            .replace(&format!("encoding=\"{encoding}\""), "encoding=\"utf-8\"")
            .replace(&format!("encoding='{encoding}'"), "encoding='utf-8'");
    }
    Ok(text)
}
fn validate_answer(text: &str) -> Result<()> {
    use quick_xml::{events::Event, Reader};
    if text
        .chars()
        .any(|ch| (ch as u32) < 32 && !['\t', '\n', '\r'].contains(&ch))
    {
        return Err("Answer file contains invalid XML control characters".into());
    }
    let mut reader = Reader::from_str(text);
    let mut roots = 0u32;
    let mut depth = 0u32;
    loop {
        match reader.read_event()? {
            Event::Start(element) | Event::Empty(element) if depth == 0 => {
                roots += 1;
                if roots != 1 || element.name().as_ref() != "unattend" {
                    return Err("Answer file root must be unattend".into());
                }
                let mut namespace = false;
                for attribute in element.attributes() {
                    let attribute = attribute?;
                    if attribute.key.as_ref() == "xmlns"
                        && attribute.normalized_value(quick_xml::XmlVersion::Implicit1_0)?
                            == "urn:schemas-microsoft-com:unattend"
                    {
                        namespace = true;
                    }
                }
                if !namespace {
                    return Err("Windows answer namespace is missing".into());
                }
                // Empty roots are valid XML but have no settings; reject them for deployment.
                if text.contains("<unattend/>") {
                    return Err("Answer file is empty".into());
                }
                depth = 1;
            }
            Event::Start(element) => {
                for attribute in element.attributes() {
                    attribute?;
                }
                depth += 1;
            }
            Event::Empty(element) => {
                for attribute in element.attributes() {
                    attribute?;
                }
            }
            Event::Text(value) if depth == 0 => {
                if !value.as_ref().trim().is_empty() {
                    return Err("Text outside answer XML root".into());
                }
            }
            Event::CData(_) if depth == 0 => return Err("CDATA outside answer XML root".into()),
            Event::End(_) => depth = depth.checked_sub(1).ok_or("Malformed answer file")?,
            Event::DocType(_) => {
                return Err("DOCTYPE is unsupported in Windows answer files".into())
            }
            Event::Eof => break,
            _ => (),
        }
    }
    if roots != 1 || depth != 0 {
        return Err("Incomplete answer file".into());
    }
    Ok(())
}
#[cfg(test)]
mod answer_tests {
    use super::*;
    #[test]
    fn handles_utf16_and_rejects_broken_xml() -> Result<()> {
        let original = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><unattend xmlns=\"urn:schemas-microsoft-com:unattend\"><settings pass=\"oobeSystem\"/></unattend>";
        let mut bytes = vec![0xff, 0xfe];
        for unit in original.encode_utf16() {
            bytes.extend_from_slice(&unit.to_le_bytes());
        }
        let decoded = decode_answer(&bytes)?;
        assert!(decoded.contains("encoding=\"utf-8\""));
        validate_answer(&decoded)?;
        assert!(validate_answer(
            "<unattend xmlns=\"urn:schemas-microsoft-com:unattend\"><settings></unattend>"
        )
        .is_err());
        assert!(validate_answer("<unattend/>").is_err());
        Ok(())
    }
}

#[cfg(test)]
mod architecture_tests {
    use super::*;
    #[test]
    fn bios_wim_architecture_is_not_assumed_x86() -> Result<()> {
        assert_eq!(wim_architecture("<WIM><ARCH>9</ARCH></WIM>")?, "amd64");
        assert_eq!(wim_architecture("<WIM><ARCH>0</ARCH></WIM>")?, "x86");
        assert_eq!(wim_architecture("<WIM><ARCH>12</ARCH></WIM>")?, "arm64");
        assert!(wim_architecture("<WIM/>").is_err());
        Ok(())
    }
}
