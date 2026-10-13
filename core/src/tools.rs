use super::*;
use std::os::unix::fs::MetadataExt;

pub fn format(options: &Options, progress: &mut Progress) -> Result<()> {
    if options.filesystem == "FAT16" && options.size > 2 * 1024 * 1024 * 1024 {
        return Err("FAT16 with these cluster sizes requires a disk of at most 2 GiB".into());
    }
    let identity = validate(options)?;
    progress.update("format", 0, 0, Instant::now())?;
    if validate(options)? != identity {
        return Err("Disk identity changed".into());
    }
    let output = Command::new("/usr/sbin/diskutil")
        .args([
            "eraseDisk",
            if options.filesystem == "FAT16" {
                "MS-DOS FAT16"
            } else {
                &options.filesystem
            },
            &options.label,
            &options.scheme,
            &options.device,
        ])
        .output()?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
    }
    if options.cluster > 0 {
        if validate(options)? != identity {
            return Err("Disk identity changed after format".into());
        }
        let partition = windows::target_partition(options)?;
        let output = Command::new("/usr/sbin/diskutil")
            .args(["unmount", &partition])
            .output()?;
        if !output.status.success() {
            return Err("Cannot unmount partition for custom cluster formatting".into());
        }
        let output = Command::new("/sbin/newfs_msdos")
            .args([
                "-F",
                if options.filesystem == "FAT16" {
                    "16"
                } else {
                    "32"
                },
                "-b",
                &options.cluster.to_string(),
                "-v",
                &options.label,
                &partition,
            ])
            .output()?;
        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
        }
        let output = Command::new("/usr/sbin/diskutil")
            .args(["mount", &partition])
            .output()?;
        if !output.status.success() {
            return Err("Formatted volume could not be mounted".into());
        }
    }
    println!("USB formatted successfully.");
    Ok(())
}
fn raw(options: &Options, writable: bool) -> Result<File> {
    let identity = validate(options)?;
    let output = Command::new("/usr/sbin/diskutil")
        .args(["unmountDisk", &options.device])
        .output()?;
    if !output.status.success() {
        return Err("Cannot unmount the USB disk".into());
    }
    if validate(options)? != identity {
        return Err("Disk changed while unmounting".into());
    }
    let file = OpenOptions::new()
        .read(true)
        .write(writable)
        .custom_flags(0x100)
        .open(options.device.replacen("/dev/disk", "/dev/rdisk", 1))?;
    if !file.metadata()?.file_type().is_char_device() {
        return Err("Not a raw disk device".into());
    }
    disable_cache(&file)?;
    Ok(file)
}
pub fn backup(options: &Options, progress: &mut Progress) -> Result<()> {
    let output = options
        .output
        .as_ref()
        .ok_or("Choose a backup destination")?;
    let parent = fs::canonicalize(output.parent().ok_or("Invalid output path")?)?;
    require_internal_source(&parent)?;
    if parent.metadata()?.uid() != options.owner {
        return Err(
            "Save backups in a folder owned by the current user on the internal disk".into(),
        );
    }
    let target = parent.join(output.file_name().ok_or("Missing output filename")?);
    if ![Some("img"), Some("vhd")].contains(&target.extension().and_then(|s| s.to_str())) {
        return Err("Backup requires .img or fixed .vhd".into());
    }
    let free = Command::new("/bin/df").arg("-Pk").arg(&parent).output()?;
    let listing = String::from_utf8(free.stdout)?;
    let available: u64 = listing
        .lines()
        .last()
        .and_then(|line| line.split_whitespace().nth(3))
        .ok_or("Cannot determine free space")?
        .parse()?;
    if available.saturating_mul(1024) < options.size.saturating_add(512) {
        return Err("Insufficient free space for the complete USB backup".into());
    }
    let mut source = raw(options, false)?;
    let mut destination = OpenOptions::new()
        .write(true)
        .read(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(0x100)
        .open(&target)?;
    use std::os::fd::AsRawFd;
    unsafe extern "C" {
        fn fchown(fd: i32, owner: u32, group: u32) -> i32;
    }
    if unsafe { fchown(destination.as_raw_fd(), options.owner, u32::MAX) } == -1 {
        return Err(io::Error::last_os_error().into());
    }
    let result = (|| -> Result<()> {
        let start = Instant::now();
        copy_image(&mut source, &mut destination, options.size, |count| {
            progress.update("backup", count, options.size, start)
        })?;
        if options.verify {
            let start = Instant::now();
            verify_image(&mut source, &mut destination, options.size, |count| {
                progress.update("verify", count, options.size, start)
            })?;
        }
        if target.extension().is_some_and(|s| s == "vhd") {
            destination.seek(SeekFrom::End(0))?;
            destination.write_all(&vhd_footer(options.size)?)?;
            destination.sync_all()?;
        }
        Ok(())
    })();
    if result.is_err() {
        drop(destination);
        let _ = fs::remove_file(target);
    }
    result?;
    println!("Backup completed.");
    Ok(())
}
pub(crate) fn vhd_footer(size: u64) -> Result<[u8; 512]> {
    let mut footer = [0u8; 512];
    footer[0..8].copy_from_slice(b"conectix");
    footer[8..12].copy_from_slice(&2u32.to_be_bytes());
    footer[12..16].copy_from_slice(&0x0001_0000u32.to_be_bytes());
    footer[16..24].copy_from_slice(&u64::MAX.to_be_bytes());
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs()
        .saturating_sub(946684800) as u32;
    footer[24..28].copy_from_slice(&now.to_be_bytes());
    footer[28..32].copy_from_slice(b"MAFU");
    footer[32..36].copy_from_slice(&0x0003_0000u32.to_be_bytes());
    footer[36..40].copy_from_slice(b"Mac ");
    footer[40..48].copy_from_slice(&size.to_be_bytes());
    footer[48..56].copy_from_slice(&size.to_be_bytes());
    let sectors = (size / 512).min(65535 * 16 * 255);
    let (mut sectors_per_track, mut heads) = (17u64, ((sectors / 17 + 1023) / 1024).max(4));
    if heads > 16 || sectors / 17 >= heads * 1024 {
        sectors_per_track = 31;
        heads = 16;
    }
    if sectors / sectors_per_track >= heads * 1024 {
        sectors_per_track = 63;
        heads = 16;
    }
    if sectors >= 65535 * 16 * 63 {
        sectors_per_track = 255;
        heads = 16;
    }
    let cylinders = sectors / sectors_per_track / heads;
    footer[56..58].copy_from_slice(&(cylinders as u16).to_be_bytes());
    footer[58] = heads as u8;
    footer[59] = sectors_per_track as u8;
    footer[60..64].copy_from_slice(&2u32.to_be_bytes());
    File::open("/dev/urandom")?.read_exact(&mut footer[68..84])?;
    let checksum = !footer.iter().map(|b| *b as u32).sum::<u32>();
    footer[64..68].copy_from_slice(&checksum.to_be_bytes());
    Ok(footer)
}
pub fn diagnostic(options: &Options, operation: &str, progress: &mut Progress) -> Result<()> {
    let mut disk = raw(options, operation != "read-test")?;
    let mut buffer = vec![0u8; CHUNK];
    let mut actual = vec![0u8; CHUNK];
    let passes = if operation == "bad-blocks" {
        options.passes
    } else {
        1
    };
    for pass in 0..passes {
        let start = Instant::now();
        let mut done = 0;
        disk.seek(SeekFrom::Start(0))?;
        while done < options.size {
            let count = (options.size - done).min(CHUNK as u64) as usize;
            if operation == "read-test" {
                disk.read_exact(&mut buffer[..count])?;
            } else {
                // Address-dependent pattern catches aliased/fake-capacity blocks on a full read-back pass.
                for (i, byte) in buffer[..count].iter_mut().enumerate() {
                    let address = done + i as u64;
                    *byte = if operation == "zero" {
                        0
                    } else {
                        ((address / 512)
                            .wrapping_mul(0x9e3779b97f4a7c15)
                            .rotate_left((i % 64) as u32)
                            ^ (pass as u64 * 0xa5)
                            ^ address) as u8
                    };
                }
                disk.write_all(&buffer[..count])?;
            }
            done += count as u64;
            progress.update(operation, done, options.size, start)?;
        }
        if operation != "read-test" {
            disk.sync_all()?;
        }
        if operation == "bad-blocks" || (operation == "zero" && options.verify) {
            disk.seek(SeekFrom::Start(0))?;
            let start = Instant::now();
            let mut done = 0;
            while done < options.size {
                let count = (options.size - done).min(CHUNK as u64) as usize;
                disk.read_exact(&mut actual[..count])?;
                for (i, byte) in actual[..count].iter().enumerate() {
                    let address = done + i as u64;
                    let expected = if operation == "zero" {
                        0
                    } else {
                        ((address / 512)
                            .wrapping_mul(0x9e3779b97f4a7c15)
                            .rotate_left((i % 64) as u32)
                            ^ (pass as u64 * 0xa5)
                            ^ address) as u8
                    };
                    if *byte != expected {
                        return Err(format!(
                            "Bad block or aliased capacity at byte {address}, pass {}",
                            pass + 1
                        )
                        .into());
                    }
                }
                done += count as u64;
                progress.update("verify", done, options.size, start)?;
            }
        }
    }
    println!("{operation}: completed {passes} pass(es).");
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fixed_vhd_has_valid_checksum() -> Result<()> {
        let footer = vhd_footer(16 * 1024 * 1024)?;
        assert_eq!(&footer[..8], b"conectix");
        assert_eq!(u32::from_be_bytes(footer[60..64].try_into()?), 2);
        let checksum = u32::from_be_bytes(footer[64..68].try_into()?);
        let sum = footer
            .iter()
            .enumerate()
            .filter(|(i, _)| !(64..68).contains(i))
            .map(|(_, b)| *b as u32)
            .sum::<u32>();
        assert_eq!(checksum, !sum);
        Ok(())
    }
}
