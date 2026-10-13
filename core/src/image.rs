use super::*;
use std::process::Stdio;
pub struct Prepared {
    pub path: PathBuf,
    _workspace: Option<windows::Workspace>,
}
pub fn prepare(original: &Path, limit: u64) -> Result<Prepared> {
    prepare_reporting(original, limit, |_| Ok(()))
}
pub fn prepare_reporting(
    original: &Path,
    limit: u64,
    mut report: impl FnMut(u64) -> io::Result<()>,
) -> Result<Prepared> {
    let extension = original
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if extension == "zip" {
        let (path, workspace) = super::archive::extract(original, limit, &mut report)?;
        return Ok(Prepared {
            path,
            _workspace: Some(workspace),
        });
    }
    if !["gz", "bz2", "xz", "zst"].contains(&extension.as_str()) {
        return Ok(Prepared {
            path: original.to_owned(),
            _workspace: None,
        });
    }
    let filename = original
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or("Invalid compressed filename")?;
    if !filename.to_ascii_lowercase().ends_with(".iso")
        && !filename.to_ascii_lowercase().ends_with(".img")
    {
        return Err(
            "Compressed filenames must retain .iso or .img before .gz, .bz2, .xz or .zst".into(),
        );
    }
    let workspace = windows::Workspace::new()?;
    let path = workspace.path.join(filename);
    let mut destination = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&path)?;
    let errors = File::create(workspace.path.join("decompress.log"))?;
    let program = match extension.as_str() {
        "gz" => PathBuf::from("/usr/bin/gzip"),
        "bz2" => PathBuf::from("/usr/bin/bzip2"),
        "xz" | "zst" => {
            let name = if extension == "xz" { "xz" } else { "zstd" };
            #[cfg(not(test))]
            let path = env::current_exe()?
                .parent()
                .ok_or("Missing app directory")?
                .join(name);
            #[cfg(test)]
            let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap()
                .join(if name == "xz" {
                    ".build/vendor/xz-5.8.4/src/xz/xz"
                } else {
                    ".build/vendor/zstd-1.5.7/programs/zstd"
                });
            if !path.is_file() {
                return Err("Bundled decompressor is missing".into());
            }
            path
        }
        _ => unreachable!(),
    };
    let mut command = Command::new(program);
    command.arg("-dc");
    if extension == "xz" {
        command.arg("--memlimit-decompress=512MiB");
    }
    if extension == "zst" {
        command.arg("-M512MB");
    }
    let mut child = command
        .arg(original)
        .stdout(Stdio::piped())
        .stderr(errors)
        .spawn()?;
    let result = (|| -> Result<()> {
        let mut output = child.stdout.take().ok_or("No decompression stream")?;
        let mut data = vec![0u8; CHUNK];
        let mut done = 0u64;
        loop {
            let count = output.read(&mut data)?;
            if count == 0 {
                break;
            }
            done = done
                .checked_add(count as u64)
                .ok_or("Expanded image size overflow")?;
            if done > limit {
                return Err("Expanded image is larger than USB capacity".into());
            }
            destination.write_all(&data[..count])?;
            report(done)?;
        }
        if !child.wait()?.success() {
            return Err("Compressed image is corrupt or could not be expanded".into());
        }
        destination.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    result?;
    Ok(Prepared {
        path,
        _workspace: Some(workspace),
    })
}
pub fn payload_size(source: &mut File, extension: &str) -> Result<u64> {
    let size = source.metadata()?.len();
    if extension != "vhd" {
        return Ok(size);
    }
    if size < 1024 {
        return Err("Invalid VHD".into());
    }
    source.seek(SeekFrom::End(-512))?;
    let mut footer = [0u8; 512];
    source.read_exact(&mut footer)?;
    source.seek(SeekFrom::Start(0))?;
    if &footer[..8] != b"conectix" || u32::from_be_bytes(footer[60..64].try_into()?) != 2 {
        return Err(
            "Only fixed VHD is supported; dynamic VHD/VHDX needs a conversion engine".into(),
        );
    }
    let checksum = u32::from_be_bytes(footer[64..68].try_into()?);
    let sum = footer
        .iter()
        .enumerate()
        .filter(|(i, _)| !(64..68).contains(i))
        .map(|(_, b)| *b as u32)
        .sum::<u32>();
    let current = u64::from_be_bytes(footer[48..56].try_into()?);
    if checksum != !sum || current != size - 512 {
        return Err("VHD footer checksum or size is invalid".into());
    }
    Ok(current)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compressed_image_respects_capacity() -> Result<()> {
        let workspace = windows::Workspace::new()?;
        let image = workspace.path.join("test.img");
        fs::write(&image, vec![42; 512])?;
        let output = Command::new("/usr/bin/gzip")
            .arg("-c")
            .arg(&image)
            .output()?;
        let compressed = workspace.path.join("test.img.gz");
        fs::write(&compressed, output.stdout)?;
        assert!(prepare(&compressed, 511).is_err());
        let expanded = prepare(&compressed, 512)?;
        assert_eq!(fs::read(expanded.path)?, vec![42; 512]);
        Ok(())
    }
    #[test]
    fn xz_and_zstd_roundtrip_and_cancel() -> Result<()> {
        let workspace = windows::Workspace::new()?;
        let source = workspace.path.join("source.img");
        fs::write(&source, vec![73u8; 4096])?;
        for (extension, binary) in [
            ("xz", ".build/vendor/xz-5.8.4/src/xz/xz"),
            ("zst", ".build/vendor/zstd-1.5.7/programs/zstd"),
        ] {
            let program = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap()
                .join(binary);
            let output = Command::new(program).arg("-c").arg(&source).output()?;
            assert!(output.status.success());
            let packed = workspace.path.join(format!("fixture.img.{extension}"));
            fs::write(&packed, output.stdout)?;
            let expanded = prepare(&packed, 4096)?;
            assert_eq!(fs::read(&expanded.path)?, vec![73u8; 4096]);
            assert!(prepare_reporting(&packed, 4096, |_| Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "Cancelled"
            )))
            .is_err());
        }
        Ok(())
    }
    #[test]
    fn fixed_vhd_does_not_flash_its_footer() -> Result<()> {
        let workspace = windows::Workspace::new()?;
        let path = workspace.path.join("test.vhd");
        let mut bytes = vec![42; 512];
        bytes.extend_from_slice(&tools::vhd_footer(512)?);
        fs::write(&path, bytes)?;
        let mut file = File::open(&path)?;
        assert_eq!(payload_size(&mut file, "vhd")?, 512);
        let mut bytes = fs::read(&path)?;
        bytes[600] ^= 1;
        fs::write(&path, bytes)?;
        assert!(payload_size(&mut File::open(&path)?, "vhd").is_err());
        Ok(())
    }
}

pub fn validate_dos(file: &mut File, total: u64) -> Result<()> {
    let mut boot = [0u8; 512];
    file.seek(SeekFrom::Start(0))?;
    file.read_exact(&mut boot)?;
    fn fat(boot: &[u8]) -> bool {
        u16::from_le_bytes([boot[11], boot[12]]) == 512
            && boot[13].is_power_of_two()
            && boot[13] <= 128
            && boot[14..16] != [0, 0]
            && [1, 2].contains(&boot[16])
            && boot[21] >= 0xf0
            && &boot[510..512] == [0x55, 0xaa]
    }
    if !fat(&boot) {
        let entry = boot[446..510]
            .chunks_exact(16)
            .find(|e| e[0] == 0x80 && [1, 4, 6, 0xb, 0xc, 0xe].contains(&e[4]))
            .ok_or("DOS IMG requires a bootable FAT volume or active FAT MBR partition")?;
        let offset = u32::from_le_bytes(entry[8..12].try_into()?) as u64 * 512;
        let length = u32::from_le_bytes(entry[12..16].try_into()?) as u64 * 512;
        if offset == 0 || length == 0 || offset.checked_add(length).is_none_or(|end| end > total) {
            return Err("Invalid DOS partition bounds".into());
        }
        file.seek(SeekFrom::Start(offset))?;
        file.read_exact(&mut boot)?;
        if !fat(&boot) {
            return Err("DOS partition has no supported FAT boot sector".into());
        }
    }
    file.seek(SeekFrom::Start(0))?;
    Ok(())
}

#[cfg(test)]
mod dos_tests {
    use super::*;
    #[test]
    fn validates_dos_boot_and_partition_bounds() -> Result<()> {
        let workspace = windows::Workspace::new()?;
        let path = workspace.path.join("dos.img");
        let mut bytes = vec![0u8; 2048];
        bytes[510..512].copy_from_slice(&[0x55, 0xaa]);
        bytes[446] = 0x80;
        bytes[450] = 6;
        bytes[454..458].copy_from_slice(&1u32.to_le_bytes());
        bytes[458..462].copy_from_slice(&3u32.to_le_bytes());
        let boot = &mut bytes[512..1024];
        boot[11..13].copy_from_slice(&512u16.to_le_bytes());
        boot[13] = 1;
        boot[14] = 1;
        boot[16] = 2;
        boot[21] = 0xf8;
        boot[510..512].copy_from_slice(&[0x55, 0xaa]);
        fs::write(&path, &bytes)?;
        validate_dos(&mut File::open(&path)?, 2048)?;
        bytes[458..462].copy_from_slice(&4u32.to_le_bytes());
        fs::write(&path, &bytes)?;
        assert!(validate_dos(&mut File::open(&path)?, 2048).is_err());
        bytes[446] = 0;
        fs::write(&path, &bytes)?;
        assert!(validate_dos(&mut File::open(&path)?, 2048).is_err());
        Ok(())
    }
}
