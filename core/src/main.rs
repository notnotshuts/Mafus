mod archive;
mod image;
mod layout;
mod ntfs;
mod persistence;
mod tools;
mod windows;
use plist::{Dictionary, Value};
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    os::unix::{fs::FileTypeExt, fs::OpenOptionsExt},
    path::{Path, PathBuf},
    process::Command,
    time::Instant,
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const CHUNK: usize = 4 * 1024 * 1024;

fn bundled_resource(name: &str) -> Result<PathBuf> {
    #[cfg(not(test))]
    let path = env::current_exe()?
        .parent()
        .ok_or("App directory missing")?
        .parent()
        .ok_or("Contents missing")?
        .join("Resources")
        .join(name);
    #[cfg(test)]
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("vendor")
        .join(name);
    if !path.is_file() {
        return Err(format!("Missing bundled resource {name}").into());
    }
    Ok(path)
}
fn bundled_tool(name: &str) -> Result<PathBuf> {
    #[cfg(not(test))]
    let path = env::current_exe()?
        .parent()
        .ok_or("App directory missing")?
        .join(name);
    #[cfg(test)]
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join(".build/tools")
        .join(name);
    if !path.is_file() {
        return Err(format!("Missing bundled tool {name}").into());
    }
    Ok(path)
}
struct Options {
    image: PathBuf,
    device: String,
    size: u64,
    name: String,
    progress: PathBuf,
    verify: bool,
    mode: String,
    attachment: u64,
    scheme: String,
    label: String,
    filesystem: String,
    cluster: u64,
    output: Option<PathBuf>,
    owner: u32,
    passes: u32,
    answer: Option<PathBuf>,
    customizations: Option<PathBuf>,
    boot_target: String,
    persistence_gib: u64,
}
fn arg(args: &[String], key: &str) -> Result<String> {
    let at = args
        .iter()
        .position(|a| a == key)
        .ok_or(format!("Missing {key}"))?;
    let value = args.get(at + 1).ok_or(format!("Missing value for {key}"))?;
    if value.starts_with("--") {
        return Err(format!("Missing value for {key}").into());
    }
    Ok(value.clone())
}
fn valid_device(device: &str) -> bool {
    device
        .strip_prefix("/dev/disk")
        .is_some_and(|suffix| !suffix.is_empty() && suffix.bytes().all(|b| b.is_ascii_digit()))
}
fn info(device: &str) -> Result<Dictionary> {
    let output = Command::new("/usr/sbin/diskutil")
        .args(["info", "-plist", device])
        .output()?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
    }
    Value::from_reader_xml(output.stdout.as_slice())?
        .into_dictionary()
        .ok_or("Invalid disk metadata".into())
}
fn boolean(map: &Dictionary, key: &str) -> bool {
    map.get(key).and_then(Value::as_boolean) == Some(true)
}
fn text<'a>(map: &'a Dictionary, key: &str) -> &'a str {
    map.get(key).and_then(Value::as_string).unwrap_or("")
}
fn validate(options: &Options) -> Result<String> {
    if !valid_device(&options.device) {
        return Err("Only a whole /dev/diskN device is allowed".into());
    }
    if attachment_id(&options.device)? != options.attachment {
        return Err("The USB attachment changed. Select the drive and confirm again.".into());
    }
    let map = info(&options.device)?;
    validate_metadata(&map, options.size, &options.name)
}
fn attachment_id(device: &str) -> Result<u64> {
    use std::ffi::{c_void, CString};
    #[link(name = "IOKit", kind = "framework")]
    unsafe extern "C" {
        fn IOBSDNameMatching(port: u32, options: u32, name: *const i8) -> *mut c_void;
        fn IOServiceGetMatchingService(port: u32, dictionary: *mut c_void) -> u32;
        fn IORegistryEntryGetRegistryEntryID(service: u32, value: *mut u64) -> i32;
        fn IOObjectRelease(service: u32) -> i32;
    }
    let name = CString::new(device.trim_start_matches("/dev/"))?;
    let matching = unsafe { IOBSDNameMatching(0, 0, name.as_ptr()) };
    if matching.is_null() {
        return Err("USB matching dictionary unavailable".into());
    }
    let service = unsafe { IOServiceGetMatchingService(0, matching) };
    if service == 0 {
        return Err("USB attachment unavailable".into());
    }
    let mut value = 0;
    let result = unsafe { IORegistryEntryGetRegistryEntryID(service, &mut value) };
    unsafe {
        IOObjectRelease(service);
    }
    if result != 0 || value == 0 {
        return Err("USB attachment identity unavailable".into());
    }
    Ok(value)
}
fn validate_metadata(map: &Dictionary, expected_size: u64, expected_name: &str) -> Result<String> {
    if !(boolean(&map, "WholeDisk") || boolean(&map, "Whole"))
        || map.get("Internal").and_then(Value::as_boolean) != Some(false)
        || text(&map, "BusProtocol") != "USB"
        || (!boolean(&map, "RemovableMedia") && !boolean(&map, "Ejectable"))
    {
        return Err("Refusing to write: target is not an external physical USB disk".into());
    }
    let size = map
        .get("TotalSize")
        .and_then(Value::as_unsigned_integer)
        .ok_or("Disk size unavailable")?;
    if size != expected_size || text(&map, "MediaName") != expected_name {
        return Err("The selected disk changed. Refresh the list and try again.".into());
    }
    // Compare the I/O registry path again after unmounting, before opening the device.
    let identity = text(&map, "DeviceTreePath");
    if identity.is_empty() {
        return Err("Cannot establish the USB device identity".into());
    }
    Ok(identity.to_owned())
}
fn require_internal_source(image: &Path) -> Result<()> {
    let output = Command::new("/bin/df").arg("-P").arg(image).output()?;
    if !output.status.success() {
        return Err("Cannot identify the source filesystem".into());
    }
    let listing = String::from_utf8(output.stdout)?;
    let source = listing
        .lines()
        .last()
        .and_then(|line| line.split_whitespace().next())
        .ok_or("Source filesystem unavailable")?;
    if !source.starts_with("/dev/") || !boolean(&info(source)?, "Internal") {
        return Err("Keep the image on the internal Mac disk before writing a USB drive".into());
    }
    Ok(())
}
struct Progress {
    file: File,
    path: PathBuf,
    cancel: PathBuf,
    last_report: Instant,
    last_phase: String,
}
impl Progress {
    fn new(path: &Path) -> Result<Self> {
        let filename = path
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or("Invalid progress path")?;
        let allowed_parent = if cfg!(test) {
            env::temp_dir()
        } else {
            PathBuf::from("/var/tmp")
        };
        if path.parent() != Some(allowed_parent.as_path())
            || !filename.starts_with("mafus-")
            || !filename.ends_with(".progress")
            || !filename
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'.')
        {
            return Err("Invalid progress path".into());
        }
        // O_NOFOLLOW on macOS; create_new also prevents pre-existing files or symlinks.
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o644)
            .custom_flags(0x100)
            .open(path)?;
        Ok(Self {
            file,
            path: path.to_owned(),
            cancel: path.with_extension("cancel"),
            last_report: Instant::now(),
            last_phase: String::new(),
        })
    }
    fn update(&mut self, phase: &str, done: u64, total: u64, start: Instant) -> io::Result<()> {
        if self.cancel.is_file() {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "Operation cancelled; USB may be incomplete",
            ));
        }
        if self.last_phase == phase && done != total && self.last_report.elapsed().as_millis() < 150
        {
            return Ok(());
        }
        self.last_report = Instant::now();
        self.last_phase = phase.to_owned();
        // Append complete records. Readers ignore a trailing incomplete record.
        writeln!(
            self.file,
            "{phase}\t{done}\t{total}\t{:.0}",
            done as f64 / start.elapsed().as_secs_f64().max(0.001)
        )?;
        self.file.flush()
    }
}
impl Drop for Progress {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
        let _ = fs::remove_file(&self.cancel);
    }
}
fn copy_image(
    source: &mut File,
    destination: &mut File,
    total: u64,
    mut report: impl FnMut(u64) -> io::Result<()>,
) -> Result<()> {
    let mut buffer = vec![0; CHUNK];
    let mut done = 0;
    while done < total {
        let count = (total - done).min(CHUNK as u64) as usize;
        source.read_exact(&mut buffer[..count])?;
        destination.write_all(&buffer[..count])?;
        done += count as u64;
        report(done)?;
    }
    destination.sync_all()?;
    Ok(())
}
fn verify_image(
    source: &mut File,
    destination: &mut File,
    total: u64,
    mut report: impl FnMut(u64) -> io::Result<()>,
) -> Result<()> {
    source.seek(SeekFrom::Start(0))?;
    destination.seek(SeekFrom::Start(0))?;
    let mut expected = vec![0; CHUNK];
    let mut actual = vec![0; CHUNK];
    let mut done = 0;
    while done < total {
        let count = (total - done).min(CHUNK as u64) as usize;
        source.read_exact(&mut expected[..count])?;
        destination.read_exact(&mut actual[..count])?;
        if expected[..count] != actual[..count] {
            return Err(format!("Verification failed near byte {done}").into());
        }
        done += count as u64;
        report(done)?;
    }
    Ok(())
}
fn copy_raw_image(
    source: &mut File,
    destination: &mut File,
    total: u64,
    sector: usize,
    verify: bool,
    mut report: impl FnMut(u64) -> io::Result<()>,
) -> Result<()> {
    if !sector.is_power_of_two() || !(512..=65536).contains(&sector) {
        return Err("Unsupported device sector size".into());
    }
    if verify {
        source.seek(SeekFrom::Start(0))?;
        destination.seek(SeekFrom::Start(0))?;
    }
    let mut buffer = vec![0u8; CHUNK];
    let mut actual = vec![0u8; CHUNK];
    let mut done = 0;
    while done < total {
        let count = (total - done).min(CHUNK as u64) as usize;
        let aligned = count.div_ceil(sector) * sector;
        source.read_exact(&mut buffer[..count])?;
        buffer[count..aligned].fill(0);
        if verify {
            destination.read_exact(&mut actual[..aligned])?;
            if buffer[..aligned] != actual[..aligned] {
                return Err(format!("Verification failed near byte {done}").into());
            }
        } else {
            destination.write_all(&buffer[..aligned])?;
        }
        done += count as u64;
        report(done)?;
    }
    if !verify {
        destination.sync_all()?;
    }
    Ok(())
}
fn disable_cache(file: &File) -> Result<()> {
    unsafe extern "C" {
        fn fcntl(fd: i32, cmd: i32, ...) -> i32;
    }
    use std::os::fd::AsRawFd;
    // F_NOCACHE on macOS; read-back must not reuse cached writes.
    if unsafe { fcntl(file.as_raw_fd(), 48, 1i32) } == -1 {
        return Err(io::Error::last_os_error().into());
    }
    Ok(())
}
fn inspect(image: &Path) -> Result<()> {
    if image
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("zip"))
    {
        println!("auto");
        return Ok(());
    }
    if image
        .extension()
        .and_then(|s| s.to_str())
        .is_some_and(|s| ["gz", "bz2", "xz", "zst"].contains(&s.to_ascii_lowercase().as_str()))
    {
        let inner = image
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        if inner.ends_with(".img") {
            println!("linux");
            return Ok(());
        }
        if inner.ends_with(".iso") {
            println!("auto");
            return Ok(());
        }
        return Err("Compressed image must retain .iso or .img in its filename".into());
    }
    let prepared = image::prepare(image, 128 * 1024 * 1024 * 1024)?;
    let image = &prepared.path;
    if image
        .extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("img") || ext.eq_ignore_ascii_case("vhd"))
    {
        println!("linux");
        return Ok(());
    }
    let mounted = windows::MountedImage::open(image)?;
    println!(
        "{}",
        if mounted.is_windows() {
            "windows"
        } else {
            "linux"
        }
    );
    Ok(())
}
fn write(options: Options) -> Result<()> {
    if Command::new("/usr/bin/id").arg("-u").output()?.stdout != b"0\n" {
        return Err("Administrator privileges required".into());
    }
    let original = fs::canonicalize(&options.image)?;
    let original_metadata = original.metadata()?;
    require_internal_source(&original)?;
    validate(&options)?;
    let mut progress = Progress::new(&options.progress)?;
    progress.update("prepare", 0, 0, Instant::now())?;
    let expansion_start = Instant::now();
    let prepared = image::prepare_reporting(&original, options.size, |done| {
        progress.update("decompress", done, 0, expansion_start)
    })?;
    let image = prepared.path.clone();
    let ext = image
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if ext != "iso" && ext != "img" && ext != "vhd" {
        return Err("Only uncompressed ISO / IMG files are supported".into());
    }
    if options.persistence_gib > 0 {
        if options.mode == "windows" || ext != "iso" {
            return Err("Persistence requires a supported Linux live ISO".into());
        }
        let sector = info(&options.device)?
            .get("DeviceBlockSize")
            .and_then(Value::as_unsigned_integer)
            .ok_or("No sector geometry")?;
        if sector != 512 {
            return Err("Persistence requires 512-byte logical sectors".into());
        }
        let (mut prepared, _workspace) =
            persistence::prepare(&image, options.size, options.persistence_gib, &mut progress)?;
        let identity = validate(&options)?;
        flash_prepared(
            &options,
            &mut prepared,
            options.size,
            512,
            &identity,
            &mut progress,
        )?;
        if original.metadata()?.modified()? != original_metadata.modified()? {
            return Err("Source changed during preparation".into());
        }
        println!("Linux persistence USB completed.");
        return Ok(());
    }
    let mut source = File::open(&image)?;
    let metadata = source.metadata()?;
    let total = image::payload_size(&mut source, &ext)?;
    if !metadata.is_file() || total == 0 || total % 512 != 0 || total > options.size {
        return Err("Invalid image size or insufficient USB capacity".into());
    }
    if options.mode == "dos" {
        if ext != "img" {
            return Err("DOS mode requires a bootable IMG or ZIP containing one IMG".into());
        }
        image::validate_dos(&mut source, total)?;
    }
    require_internal_source(&image)?;
    let identity = validate(&options)?;
    let sector = info(&options.device)?
        .get("DeviceBlockSize")
        .and_then(Value::as_unsigned_integer)
        .ok_or("Device sector size unavailable")? as usize;
    if !sector.is_power_of_two()
        || !(512..=65536).contains(&sector)
        || total.div_ceil(sector as u64) * sector as u64 > options.size
    {
        return Err("Image does not fit the device sector geometry".into());
    }
    if options.mode != "linux" && ext == "iso" {
        let mounted = windows::MountedImage::open(&image)?;
        if options.mode == "windows" || mounted.is_windows() {
            windows::write_windows(&options, &mounted, &mut progress)?;
            if source.metadata()?.len() != metadata.len()
                || source.metadata()?.modified()? != metadata.modified()?
                || original.metadata()?.modified()? != original_metadata.modified()?
            {
                return Err("Source image changed during writing".into());
            }
            println!("Windows UEFI USB completed successfully.");
            return Ok(());
        }
    } else if options.mode == "windows" {
        return Err("Windows mode requires an installation ISO".into());
    }

    flash_prepared(
        &options,
        &mut source,
        total,
        sector,
        &identity,
        &mut progress,
    )?;
    if source.metadata()?.len() != metadata.len()
        || source.metadata()?.modified()? != metadata.modified()?
        || original.metadata()?.modified()? != original_metadata.modified()?
    {
        return Err("The source image changed during writing; USB data cannot be trusted".into());
    }
    println!("Write completed successfully. Disk remains unmounted.");
    Ok(())
}
fn flash_prepared(
    options: &Options,
    source: &mut File,
    total: u64,
    sector: usize,
    identity: &String,
    progress: &mut Progress,
) -> Result<()> {
    let output = Command::new("/usr/sbin/diskutil")
        .args(["unmountDisk", &options.device])
        .output()?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
    }
    if validate(options)? != *identity {
        return Err("USB device changed during preparation".into());
    }
    let raw = options.device.replacen("/dev/disk", "/dev/rdisk", 1);
    let mut destination = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(0x100)
        .open(raw)?;
    if !destination.metadata()?.file_type().is_char_device() {
        return Err("Target is not a raw disk device".into());
    }
    disable_cache(&destination)?;
    let start = Instant::now();
    progress.update("write", 0, total, start)?;
    copy_raw_image(source, &mut destination, total, sector, false, |done| {
        progress.update("write", done, total, start)
    })?;
    if options.verify {
        disable_cache(&destination)?;
        let start = Instant::now();
        progress.update("verify", 0, total, start)?;
        copy_raw_image(source, &mut destination, total, sector, true, |done| {
            progress.update("verify", done, total, start)
        })?;
    }

    Ok(())
}

fn main() {
    let result = (|| -> Result<()> {
        let args: Vec<String> = env::args().collect();
        if args.get(1).map(String::as_str) == Some("inspect") {
            return inspect(Path::new(&arg(&args, "--image")?));
        }
        if args.get(1).map(String::as_str) == Some("windows-info") {
            return windows::describe(Path::new(&arg(&args, "--image")?));
        }
        let operation = args.get(1).map(String::as_str).unwrap_or("");
        if ![
            "write",
            "format",
            "backup",
            "read-test",
            "zero",
            "bad-blocks",
            "preflight",
        ]
        .contains(&operation)
        {
            return Err("Unknown operation".into());
        }
        if operation != "preflight"
            && Command::new("/usr/bin/id").arg("-u").output()?.stdout != b"0\n"
        {
            return Err("Administrator privileges required".into());
        }
        let mode = arg(&args, "--mode").unwrap_or_else(|_| "auto".to_owned());
        if !["auto", "windows", "linux", "dos"].contains(&mode.as_str()) {
            return Err("Unknown write mode".into());
        }
        let scheme = arg(&args, "--scheme").unwrap_or_else(|_| "MBR".into());
        if !["MBR", "GPT"].contains(&scheme.as_str()) {
            return Err("Unsupported partition scheme".into());
        }
        let label = arg(&args, "--label").unwrap_or_else(|_| "MAFUS".into());
        if label.is_empty()
            || label.len() > 11
            || !label
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        {
            return Err("Volume label: use 1–11 Latin letters, digits, - or _".into());
        }
        let filesystem = arg(&args, "--filesystem").unwrap_or_else(|_| "FAT32".into());
        if !["FAT16", "FAT32", "ExFAT", "NTFS"].contains(&filesystem.as_str()) {
            return Err("Unsupported filesystem".into());
        }
        let cluster: u64 = arg(&args, "--cluster")
            .unwrap_or_else(|_| "0".into())
            .parse()?;
        if ![0, 4096, 8192, 16384, 32768].contains(&cluster)
            || (filesystem == "ExFAT" && cluster != 0)
        {
            return Err("Unsupported cluster size".into());
        }
        let passes: u32 = arg(&args, "--passes")
            .unwrap_or_else(|_| "1".into())
            .parse()?;
        if !(1..=4).contains(&passes) {
            return Err("Choose 1–4 passes".into());
        }
        let options = Options {
            image: arg(&args, "--image").unwrap_or_default().into(),
            device: arg(&args, "--device")?,
            size: arg(&args, "--expected-size")?.parse()?,
            name: arg(&args, "--expected-name")?,
            progress: arg(&args, "--progress")?.into(),
            verify: args.iter().any(|a| a == "--verify"),
            mode,
            attachment: arg(&args, "--expected-attachment")?.parse()?,
            scheme,
            label,
            filesystem,
            cluster,
            output: arg(&args, "--output").ok().map(PathBuf::from),
            owner: arg(&args, "--owner-uid")
                .unwrap_or_else(|_| "0".into())
                .parse()?,
            passes,
            answer: arg(&args, "--answer").ok().map(PathBuf::from),
            customizations: arg(&args, "--customizations").ok().map(PathBuf::from),
            boot_target: arg(&args, "--boot-target").unwrap_or_else(|_| "uefi".into()),
            persistence_gib: arg(&args, "--persistence-gib")
                .unwrap_or_else(|_| "0".into())
                .parse()?,
        };
        if !["uefi", "bios", "both"].contains(&options.boot_target.as_str())
            || options.persistence_gib > 128
        {
            return Err("Invalid boot target or persistence size".into());
        }
        if operation != "write" && operation != "preflight" && options.filesystem == "NTFS" {
            return Err("NTFS is available for Windows image preparation only".into());
        }
        if operation == "preflight" {
            validate(&options)?;
            println!("USB preflight passed");
            return Ok(());
        }
        if operation == "write" {
            return write(options);
        }
        validate(&options)?;
        let mut progress = Progress::new(&options.progress)?;
        match operation {
            "format" => tools::format(&options, &mut progress),
            "backup" => tools::backup(&options, &mut progress),
            _ => tools::diagnostic(&options, operation, &mut progress),
        }
    })();
    if let Err(error) = result {
        eprintln!("Mafus: {error}");
        std::process::exit(1);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_whole_disks() {
        assert!(valid_device("/dev/disk12"));
        for bad in [
            "/dev/disk",
            "/dev/disk1s1",
            "/dev/rdisk2",
            "/dev/disk0;reboot",
            "/tmp/disk2",
        ] {
            assert!(!valid_device(bad));
        }
    }
    #[test]
    fn reject_internal_disks_and_partitions() -> Result<()> {
        let mut map = Dictionary::new();
        map.insert("WholeDisk".into(), Value::Boolean(true));
        map.insert("Internal".into(), Value::Boolean(false));
        map.insert("BusProtocol".into(), Value::String("USB".into()));
        map.insert("Ejectable".into(), Value::Boolean(true));
        map.insert("TotalSize".into(), Value::Integer(1024u64.into()));
        map.insert("MediaName".into(), Value::String("USB".into()));
        map.insert("DeviceTreePath".into(), Value::String("USB-path".into()));
        assert!(validate_metadata(&map, 1024, "USB").is_ok());
        map.insert("Internal".into(), Value::Boolean(true));
        assert!(validate_metadata(&map, 1024, "USB").is_err());
        map.insert("Internal".into(), Value::Boolean(false));
        map.insert("WholeDisk".into(), Value::Boolean(false));
        assert!(validate_metadata(&map, 1024, "USB").is_err());
        Ok(())
    }
    #[test]
    fn raw_copy_pads_and_verifies_4k_sectors() -> Result<()> {
        let directory = windows::Workspace::new()?;
        let original = directory.path.join("source.img");
        let copied = directory.path.join("target.img");
        fs::write(&original, vec![42u8; 512])?;
        let mut source = File::open(&original)?;
        let mut target = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&copied)?;
        copy_raw_image(&mut source, &mut target, 512, 4096, false, |_| Ok(()))?;
        assert_eq!(target.metadata()?.len(), 4096);
        copy_raw_image(&mut source, &mut target, 512, 4096, true, |_| Ok(()))?;
        target.seek(SeekFrom::Start(1024))?;
        target.write_all(&[1])?;
        assert!(copy_raw_image(&mut source, &mut target, 512, 4096, true, |_| Ok(())).is_err());
        Ok(())
    }
    #[test]
    fn copy_and_detect_corruption() -> Result<()> {
        let dir = env::temp_dir().join(format!("mafus-test-{}", std::process::id()));
        fs::create_dir(&dir)?;
        let result = (|| -> Result<()> {
            let source_path = dir.join("source.img");
            let target_path = dir.join("target.img");
            fs::write(&source_path, vec![73u8; CHUNK + 512])?;
            let mut source = File::open(source_path)?;
            let mut target = OpenOptions::new()
                .read(true)
                .write(true)
                .create_new(true)
                .open(target_path)?;
            copy_image(&mut source, &mut target, (CHUNK + 512) as u64, |_| Ok(()))?;
            verify_image(&mut source, &mut target, (CHUNK + 512) as u64, |_| Ok(()))?;
            target.seek(SeekFrom::Start(512))?;
            target.write_all(&[0])?;
            assert!(
                verify_image(&mut source, &mut target, (CHUNK + 512) as u64, |_| Ok(())).is_err()
            );
            Ok(())
        })();
        fs::remove_dir_all(dir)?;
        result
    }
}
