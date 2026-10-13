use super::*;
pub fn write_windows(
    options: &Options,
    files: &[windows::Entry],
    required: u64,
    progress: &mut Progress,
) -> Result<()> {
    let bios = options.boot_target != "uefi";
    if bios
        && files.iter().any(|e| {
            e.relative
                .to_string_lossy()
                .eq_ignore_ascii_case("efi/boot/bootaa64.efi")
        })
        && !files.iter().any(|e| {
            e.relative
                .to_string_lossy()
                .eq_ignore_ascii_case("efi/boot/bootx64.efi")
        })
    {
        return Err("ARM64 Windows does not support BIOS/CSM".into());
    }
    if bios && options.scheme != "MBR" {
        return Err("BIOS/CSM Windows requires MBR".into());
    }
    if bios
        && (!files
            .iter()
            .any(|e| e.relative.to_string_lossy().eq_ignore_ascii_case("bootmgr"))
            || !files.iter().any(|e| {
                e.relative
                    .to_string_lossy()
                    .eq_ignore_ascii_case("boot/bcd")
            }))
    {
        return Err("Windows ISO lacks BIOS bootmgr/BCD".into());
    }
    let sector = info(&options.device)?
        .get("DeviceBlockSize")
        .and_then(Value::as_unsigned_integer)
        .ok_or("No sector geometry")?;
    if sector != 512 {
        return Err(
            "UEFI:NTFS/BIOS preparation currently requires 512-byte logical sectors".into(),
        );
    }
    let reserve = 4 * 1024 * 1024;
    if options.size < required.saturating_add(reserve) {
        return Err("USB too small for NTFS Windows files".into());
    }
    let (mut disk, _workspace) = prepare(
        files,
        &options.label,
        options.size,
        options.scheme == "GPT",
        bios,
        progress,
    )?;
    let identity = validate(options)?;
    super::flash_prepared(options, &mut disk, options.size, 512, &identity, progress)?;
    println!("Windows NTFS USB prepared; BIOS/UEFI support follows selected target and ISO architecture.");
    Ok(())
}

fn prepare(
    files: &[windows::Entry],
    label: &str,
    size: u64,
    gpt: bool,
    bios: bool,
    progress: &mut Progress,
) -> Result<(File, windows::Workspace)> {
    let reserve = 4 * 1024 * 1024;
    let workspace = windows::Workspace::new()?;
    let partition = workspace.path.join("windows.ntfs");
    let sectors = (size - reserve) / 512;
    let mut volume = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&partition)?;
    volume.set_len(sectors * 512)?;
    progress.update("prepare", 0, 0, Instant::now())?;
    let mut formatter = Command::new(bundled_tool("mkntfs")?);
    formatter
        .args([
            "-F", "-Q", "-s", "512", "-p", "2048", "-H", "255", "-S", "63", "-L", &label,
        ])
        .arg(&partition);
    persistence::run(&mut formatter, &workspace, progress)?;
    let manifest = workspace.path.join("files.manifest");
    let mut list = File::create(&manifest)?;
    for entry in files {
        list.write_all(entry.source.as_os_str().as_encoded_bytes())?;
        list.write_all(&[0])?;
        list.write_all(entry.relative.as_os_str().as_encoded_bytes())?;
        list.write_all(&[0])?;
    }
    drop(list);
    let mut populate = Command::new(bundled_tool("ntfs-populate")?);
    populate.arg(&partition).arg(&manifest);
    persistence::run(&mut populate, &workspace, progress)?;
    if bios {
        let jump = fs::read(bundled_resource("windows-ntfs-jump.bin")?)?;
        let code = fs::read(bundled_resource("windows-ntfs-code.bin")?)?;
        if jump.len() != 11 || code.len() > 8192 - 0x54 {
            return Err("Invalid NTFS boot code".into());
        }
        volume.seek(SeekFrom::Start(0))?;
        volume.write_all(&jump)?;
        volume.seek(SeekFrom::Start(0x54))?;
        volume.write_all(&code)?;
        let mut boot = [0; 512];
        volume.seek(SeekFrom::Start(0))?;
        volume.read_exact(&mut boot)?;
        volume.seek(SeekFrom::Start((sectors - 1) * 512))?;
        volume.write_all(&boot)?;
        volume.sync_all()?;
    }
    let path = workspace.path.join("windows.img");
    let mut disk = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    let fat_offset = layout::windows(&mut disk, size, sectors, gpt, bios)?;
    volume.seek(SeekFrom::Start(0))?;
    disk.seek(SeekFrom::Start(2048 * 512))?;
    let start = Instant::now();
    let mut buffer = vec![0u8; CHUNK];
    let mut done = 0u64;
    while done < sectors * 512 {
        let count = (sectors * 512 - done).min(CHUNK as u64) as usize;
        volume.read_exact(&mut buffer[..count])?;
        if buffer[..count].iter().any(|b| *b != 0) {
            disk.write_all(&buffer[..count])?;
        } else {
            disk.seek(SeekFrom::Current(count as i64))?;
        }
        done += count as u64;
        progress.update("prepare", done, sectors * 512, start)?;
    }
    let fat = fs::read(bundled_resource("uefi-ntfs.img")?)?;
    if fat.len() != 1024 * 1024 {
        return Err("Invalid bundled UEFI:NTFS image".into());
    }
    disk.seek(SeekFrom::Start(fat_offset))?;
    disk.write_all(&fat)?;
    disk.sync_all()?;
    disk.seek(SeekFrom::Start(0))?;

    Ok((disk, workspace))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ntfs_boot_layout_and_data() -> Result<()> {
        let workspace = windows::Workspace::new()?;
        let source = workspace.path.join("bootmgr");
        fs::write(&source, b"Windows boot manager fixture")?;
        let files = vec![
            windows::Entry {
                source: source.clone(),
                relative: PathBuf::from("bootmgr"),
                size: 28,
            },
            windows::Entry {
                source: source.clone(),
                relative: PathBuf::from("boot/BCD"),
                size: 28,
            },
            windows::Entry {
                source: source.clone(),
                relative: PathBuf::from("efi/boot/bootx64.efi"),
                size: 28,
            },
        ];
        let p = env::temp_dir().join(format!("mafus-ntfs-{}.progress", std::process::id()));
        let mut progress = Progress::new(&p)?;
        for (gpt, bios) in [(true, false), (false, true)] {
            let (mut disk, staging) =
                prepare(&files, "MAFUS", 128 * 1024 * 1024, gpt, bios, &mut progress)?;
            disk.seek(SeekFrom::Start(0))?;
            let mut mbr = [0; 512];
            disk.read_exact(&mut mbr)?;
            assert_eq!(&mbr[510..], &[0x55, 0xaa]);
            assert_eq!(mbr[450], if gpt { 0xee } else { 7 });
            if bios {
                assert_eq!(mbr[446], 0x80);
            }
            disk.seek(SeekFrom::Start(2048 * 512))?;
            let mut boot = [0; 512];
            disk.read_exact(&mut boot)?;
            assert_eq!(&boot[3..11], b"NTFS    ");
            if bios {
                assert_eq!(&boot[..3], &[0xeb, 0x52, 0x90]);
                assert!(fs::read(staging.path.join("windows.ntfs"))?
                    .windows(7)
                    .any(|b| b == b"BOOTMGR"));
            }
            let output = Command::new(
                PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .unwrap()
                    .join(".build/vendor/ntfs-3g-2026.9.28/ntfsprogs/ntfscat"),
            )
            .arg(staging.path.join("windows.ntfs"))
            .arg("/efi/boot/bootx64.efi")
            .output()?;
            assert!(output.status.success());
            assert_eq!(output.stdout, fs::read(&source)?);
        }
        Ok(())
    }
}
