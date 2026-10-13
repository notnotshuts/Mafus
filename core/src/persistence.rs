use super::*;
pub(crate) fn run(
    command: &mut Command,
    workspace: &windows::Workspace,
    progress: &mut Progress,
) -> Result<()> {
    let log = workspace.path.join("prepare.log");
    let out = File::create(&log)?;
    let mut child = command.stdout(out.try_clone()?).stderr(out).spawn()?;
    loop {
        if let Err(error) = progress.update("prepare", 0, 0, Instant::now()) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error.into());
        }
        if let Some(status) = child.try_wait()? {
            if !status.success() {
                return Err(
                    format!("Image preparation failed: {}", fs::read_to_string(&log)?).into(),
                );
            }
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(150));
    }
    Ok(())
}
pub fn patch_config(text: &str, debian: bool) -> (String, usize) {
    let mut count = 0;
    let mut lines = Vec::new();
    for line in text.lines() {
        let trimmed = line.trim_start();
        let kernel = trimmed.starts_with("linux ")
            || trimmed.starts_with("linuxefi ")
            || trimmed.starts_with("append ")
            || trimmed.starts_with("APPEND ");
        if kernel
            && (line.contains(if debian { "boot=live" } else { "boot=casper" })
                || line.contains(if debian {
                    "/live/vmlinuz"
                } else {
                    "/casper/vmlinuz"
                }))
            && !line
                .split_whitespace()
                .any(|word| ["nopersistence", "nopersistent"].contains(&word))
        {
            let flag = if debian { "persistence" } else { "persistent" };
            let mut modified = line.to_owned();
            if !line.split_whitespace().any(|w| w == flag) {
                if let Some(position) = line.find(" ---") {
                    modified.insert_str(position, &format!(" {flag}"));
                } else {
                    modified.push_str(&format!(" {flag}"));
                }
            }
            count += 1;
            lines.push(modified);
        } else {
            lines.push(line.to_owned());
        }
    }
    (lines.join("\n") + "\n", count)
}
fn configs(root: &Path, base: &Path, output: &mut Vec<PathBuf>) -> Result<()> {
    if !base.exists() {
        return Ok(());
    }
    for item in fs::read_dir(base)? {
        let path = item?.path();
        let meta = fs::symlink_metadata(&path)?;
        if meta.is_dir() {
            configs(root, &path, output)?;
        } else if meta.is_file()
            && path
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("cfg"))
        {
            if meta.len() > 1024 * 1024 {
                return Err("Boot config is too large".into());
            }
            output.push(path.strip_prefix(root)?.to_owned());
        }
    }
    Ok(())
}
pub fn prepare(
    original: &Path,
    size_on_usb: u64,
    persistence_gib: u64,
    progress: &mut Progress,
) -> Result<(File, windows::Workspace)> {
    if !(1..=128).contains(&persistence_gib) {
        return Err("Persistence size must be 1–128 GiB".into());
    }
    let mounted = windows::MountedImage::open(original)?;
    let info = fs::read_to_string(mounted.root.join(".disk/info"))
        .unwrap_or_default()
        .to_lowercase();
    let debian = info.contains("debian") && mounted.root.join("live").is_dir();
    let casper =
        (info.contains("ubuntu") || info.contains("linux mint") || info.contains("linuxmint"))
            && mounted.root.join("casper").is_dir();
    if !debian && !casper {
        return Err(
            "Persistence supports Ubuntu Desktop, Linux Mint and Debian Live ISO only".into(),
        );
    }
    let size = persistence_gib * 1024 * 1024 * 1024;
    if original
        .metadata()?
        .len()
        .saturating_add(size)
        .saturating_add(64 * 1024 * 1024)
        > size_on_usb
    {
        return Err("USB has no room for this persistence size".into());
    }
    let workspace = windows::Workspace::new()?;
    let root = workspace.path.join("overlay-root");
    fs::create_dir(&root)?;
    if debian {
        fs::write(root.join("persistence.conf"), b"/ union\n")?;
    }
    let overlay = workspace.path.join("persistence.ext4");
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&overlay)?;
    file.set_len(size)?;
    drop(file);
    let mut mkfs = Command::new(bundled_tool("mke2fs")?);
    mkfs.env("MKE2FS_CONFIG", bundled_resource("mke2fs.conf")?)
        .args([
            "-q",
            "-F",
            "-t",
            "ext4",
            "-b",
            "4096",
            "-m",
            "0",
            "-L",
            if debian { "persistence" } else { "writable" },
            "-E",
            "lazy_itable_init=0,lazy_journal_init=0",
            "-d",
        ])
        .arg(&root)
        .arg(&overlay);
    run(&mut mkfs, &workspace, progress)?;
    let mut config_paths = Vec::new();
    for dir in ["boot/grub", "isolinux", "syslinux", "EFI/BOOT"] {
        configs(&mounted.root, &mounted.root.join(dir), &mut config_paths)?;
    }
    let output = workspace.path.join("persistent.iso");
    let mut iso = Command::new(bundled_tool("xorriso")?);
    iso.args(["-abort_on", "FAILURE", "-indev"])
        .arg(original)
        .arg("-outdev")
        .arg(&output)
        .args(["-boot_image", "any", "replay"]);
    let mut matches = 0;
    for (index, relative) in config_paths.iter().enumerate() {
        let text = fs::read_to_string(mounted.root.join(relative))?;
        let (patched, count) = patch_config(&text, debian);
        if count == 0 {
            continue;
        }
        matches += count;
        let config = workspace.path.join(format!("config-{index}.cfg"));
        fs::write(&config, patched)?;
        iso.arg("-map")
            .arg(config)
            .arg(format!("/{}", relative.display()));
    }
    if matches == 0 {
        return Err(
            "No supported live boot entries found; refusing ineffective persistence".into(),
        );
    }
    iso.args([
        "-boot_image",
        "any",
        "appended_part_as=gpt",
        "-append_partition",
        "4",
        "0x83",
    ])
    .arg(&overlay)
    .args(["-commit", "-end"]);
    run(&mut iso, &workspace, progress)?;
    let mut result = OpenOptions::new().read(true).write(true).open(&output)?;
    layout::relocate_gpt(&mut result, size_on_usb)?;
    result.seek(SeekFrom::Start(0))?;
    Ok((result, workspace))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn boot_flags_only_on_live_entries() {
        let config="menuentry 'Live' {\n linux /casper/vmlinuz boot=casper quiet ---\n}\nlinux /rescue quiet\nappend boot=casper nopersistent\n";
        let (patched, count) = patch_config(config, false);
        assert_eq!(count, 1);
        assert!(patched.contains("quiet persistent ---"));
        assert!(patched.contains("linux /rescue quiet"));
        let (modern, count) = patch_config("linux /casper/vmlinuz quiet ---\n", false);
        assert_eq!(count, 1);
        assert!(modern.contains("quiet persistent ---"));
        let (patched, count) = patch_config("append boot=live components\n", true);
        assert_eq!(count, 1);
        assert!(patched.contains("components persistence"));
    }
}

#[cfg(test)]
mod integration {
    use super::*;
    #[test]
    #[ignore = "requires read-only ISO mounting outside the sandbox"]
    fn live_iso_persistence_roundtrip() -> Result<()> {
        for (debian, name, dir) in [
            (false, "Linux Mint 22 live amd64", "casper"),
            (true, "Debian GNU/Linux Live amd64", "live"),
        ] {
            let workspace = windows::Workspace::new()?;
            let root = workspace.path.join("root");
            fs::create_dir_all(root.join(".disk"))?;
            fs::create_dir_all(root.join(dir))?;
            fs::write(root.join(".disk/info"), name)?;
            fs::write(root.join(dir).join("vmlinuz"), b"kernel fixture")?;
            fs::create_dir_all(root.join("boot/grub"))?;
            fs::write(
                root.join("boot/grub/grub.cfg"),
                format!(
                    "linux /{dir}/vmlinuz boot={} quiet ---\n",
                    if debian { "live" } else { "casper" }
                ),
            )?;
            fs::copy(
                bundled_resource("syslinux-isolinux.bin")?,
                root.join("boot.img"),
            )?;
            fs::copy(bundled_resource("uefi-ntfs.img")?, root.join("efi.img"))?;
            let iso = workspace.path.join("source.iso");
            let status = Command::new(bundled_tool("xorriso")?)
                .args([
                    "-as",
                    "mkisofs",
                    "-R",
                    "-b",
                    "boot.img",
                    "-no-emul-boot",
                    "-boot-load-size",
                    "4",
                    "-boot-info-table",
                    "-isohybrid-mbr",
                ])
                .arg(bundled_resource("syslinux-isohdpfx.bin")?)
                .args(["-eltorito-alt-boot", "-e", "efi.img", "-no-emul-boot", "-o"])
                .arg(&iso)
                .arg(&root)
                .output()?;
            assert!(
                status.status.success(),
                "{}",
                String::from_utf8_lossy(&status.stderr)
            );
            let progress_path = env::temp_dir().join(format!(
                "mafus-persistence-{}-{}.progress",
                std::process::id(),
                debian
            ));
            let mut progress = Progress::new(&progress_path)?;
            let (mut disk, prepared) = prepare(&iso, 1280 * 1024 * 1024, 1, &mut progress)?;
            let staged = prepared.path.join("persistent.iso");
            assert_eq!(disk.metadata()?.len(), 1280 * 1024 * 1024);
            let extracted = workspace.path.join("grub.cfg");
            let status = Command::new(bundled_tool("xorriso")?)
                .arg("-indev")
                .arg(&staged)
                .args(["-osirrox", "on", "-extract", "/boot/grub/grub.cfg"])
                .arg(&extracted)
                .output()?;
            assert!(
                status.status.success(),
                "{}",
                String::from_utf8_lossy(&status.stderr)
            );
            assert!(fs::read_to_string(extracted)?.contains(if debian {
                "persistence"
            } else {
                "persistent"
            }));
            let report = Command::new(bundled_tool("xorriso")?)
                .arg("-indev")
                .arg(&staged)
                .args(["-report_el_torito", "plain"])
                .output()?;
            let report = String::from_utf8_lossy(&report.stderr).to_string()
                + &String::from_utf8_lossy(&report.stdout);
            assert!(
                report.contains("BIOS") && report.contains("UEFI"),
                "{report}"
            );
            let overlay = prepared.path.join("persistence.ext4");
            let checked = Command::new(bundled_tool("e2fsck")?)
                .arg("-fn")
                .arg(&overlay)
                .output()?;
            assert!(
                checked.status.success(),
                "{}",
                String::from_utf8_lossy(&checked.stderr)
            );
            if debian {
                let read = Command::new(bundled_tool("debugfs")?)
                    .args(["-R", "cat persistence.conf"])
                    .arg(&overlay)
                    .output()?;
                assert_eq!(read.stdout, b"/ union\n");
            }
            disk.seek(SeekFrom::Start(512))?;
            let mut header = [0u8; 512];
            disk.read_exact(&mut header)?;
            assert_eq!(&header[..8], b"EFI PART");
        }
        Ok(())
    }
}
