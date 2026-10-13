use super::*;
pub fn crc32(data: &[u8]) -> u32 {
    let mut c = !0u32;
    for b in data {
        c ^= *b as u32;
        for _ in 0..8 {
            c = (c >> 1) ^ (0xedb88320u32 & (0u32.wrapping_sub(c & 1)));
        }
    }
    !c
}
fn put64(b: &mut [u8], at: usize, v: u64) {
    b[at..at + 8].copy_from_slice(&v.to_le_bytes());
}
fn put32(b: &mut [u8], at: usize, v: u32) {
    b[at..at + 4].copy_from_slice(&v.to_le_bytes());
}
fn get64(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn get32(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(b[at..at + 4].try_into().unwrap())
}
fn random_id() -> Result<[u8; 16]> {
    let mut b = [0; 16];
    File::open("/dev/urandom")?.read_exact(&mut b)?;
    Ok(b)
}
fn at(file: &mut File, offset: u64, data: &[u8]) -> Result<()> {
    file.seek(SeekFrom::Start(offset))?;
    file.write_all(data)?;
    Ok(())
}
fn header(entries: &[u8], id: [u8; 16], this: u64, other: u64, table: u64, last: u64) -> Vec<u8> {
    let mut b = vec![0; 512];
    b[..8].copy_from_slice(b"EFI PART");
    put32(&mut b, 8, 0x10000);
    put32(&mut b, 12, 92);
    put64(&mut b, 24, this);
    put64(&mut b, 32, other);
    put64(&mut b, 40, 34);
    put64(&mut b, 48, last - 33);
    b[56..72].copy_from_slice(&id);
    put64(&mut b, 72, table);
    put32(&mut b, 80, 128);
    put32(&mut b, 84, 128);
    put32(&mut b, 88, crc32(entries));
    let crc = crc32(&b[..92]);
    put32(&mut b, 16, crc);
    b
}
pub fn windows(
    file: &mut File,
    size: u64,
    ntfs_sectors: u64,
    gpt: bool,
    bios: bool,
) -> Result<u64> {
    if size % 512 != 0 || size < 512 * 4096 {
        return Err("Unsupported USB size".into());
    }
    let last = size / 512 - 1;
    let start = 2048;
    let fat_start = start + ntfs_sectors;
    let fat_len = 2048;
    if fat_start + fat_len + 34 > last || (!gpt && size / 512 > u32::MAX as u64) {
        return Err("Windows partition layout does not fit USB".into());
    }
    file.set_len(size)?;
    let mut mbr = [0u8; 512];
    mbr[510..].copy_from_slice(&[0x55, 0xaa]);
    if gpt {
        mbr[446 + 4] = 0xee;
        put32(&mut mbr, 446 + 8, 1);
        put32(&mut mbr, 446 + 12, last.min(u32::MAX as u64) as u32);
        let mut entries = vec![0u8; 16384];
        for (i, first, count, kind, name) in [
            (
                0,
                start,
                ntfs_sectors,
                [
                    0xa2, 0xa0, 0xd0, 0xeb, 0xe5, 0xb9, 0x33, 0x44, 0x87, 0xc0, 0x68, 0xb6, 0xb7,
                    0x26, 0x99, 0xc7,
                ],
                "MAFUS",
            ),
            (
                1,
                fat_start,
                fat_len,
                [
                    0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11, 0xba, 0x4b, 0, 0xa0, 0xc9,
                    0x3e, 0xc9, 0x3b,
                ],
                "UEFI_NTFS",
            ),
        ] {
            let e = &mut entries[i * 128..(i + 1) * 128];
            e[..16].copy_from_slice(&kind);
            e[16..32].copy_from_slice(&random_id()?);
            put64(e, 32, first);
            put64(e, 40, first + count - 1);
            for (j, u) in name.encode_utf16().enumerate() {
                e[56 + 2 * j..58 + 2 * j].copy_from_slice(&u.to_le_bytes());
            }
        }
        let id = random_id()?;
        at(file, 1024, &entries)?;
        at(file, (last - 32) * 512, &entries)?;
        at(file, 512, &header(&entries, id, 1, last, 2, last))?;
        at(
            file,
            last * 512,
            &header(&entries, id, last, 1, last - 32, last),
        )?;
    } else {
        if bios {
            let code = fs::read(super::bundled_resource("windows-mbr.bin")?)?;
            if code.len() > 440 {
                return Err("Invalid BIOS MBR".into());
            }
            mbr[..code.len()].copy_from_slice(&code);
        }
        for (i, first, count, kind) in
            [(0, start, ntfs_sectors, 7u8), (1, fat_start, fat_len, 0xef)]
        {
            let e = &mut mbr[446 + i * 16..462 + i * 16];
            if i == 0 && bios {
                e[0] = 0x80;
            }
            e[1..4].copy_from_slice(&[0xfe, 0xff, 0xff]);
            e[4] = kind;
            e[5..8].copy_from_slice(&[0xfe, 0xff, 0xff]);
            put32(e, 8, first as u32);
            put32(e, 12, count as u32);
        }
    }
    at(file, 0, &mbr)?;
    Ok(fat_start * 512)
}
// Validate GPT checksums before moving the backup table to the true device end.
pub fn relocate_gpt(file: &mut File, size: u64) -> Result<()> {
    let old = file.metadata()?.len();
    if old > size || size % 512 != 0 {
        return Err("Prepared Linux image exceeds USB capacity".into());
    }
    let mut h = vec![0; 512];
    file.seek(SeekFrom::Start(512))?;
    file.read_exact(&mut h)?;
    if &h[..8] != b"EFI PART" || get32(&h, 12) != 92 {
        return Err("Persistence requires a hybrid GPT ISO".into());
    }
    let checksum = get32(&h, 16);
    put32(&mut h, 16, 0);
    if crc32(&h[..92]) != checksum {
        return Err("Invalid GPT header checksum".into());
    }
    let count = get32(&h, 80) as usize;
    let entry = get32(&h, 84) as usize;
    if count == 0 || count > 4096 || entry != 128 {
        return Err("Unsupported GPT table".into());
    }
    let bytes = count * entry;
    let table = get64(&h, 72) * 512;
    if table.checked_add(bytes as u64).is_none_or(|end| end > old) {
        return Err("GPT table outside image".into());
    }
    let mut entries = vec![0; bytes];
    file.seek(SeekFrom::Start(table))?;
    file.read_exact(&mut entries)?;
    if crc32(&entries) != get32(&h, 88) {
        return Err("Invalid GPT partition checksum".into());
    }
    let last = size / 512 - 1;
    let table_sectors = (bytes as u64).div_ceil(512);
    let end = last - table_sectors - 1;
    for e in entries
        .chunks_exact(128)
        .filter(|e| e[..16].iter().any(|b| *b != 0))
    {
        if get64(e, 40) > end || get64(e, 32) > get64(e, 40) {
            return Err("GPT partition outside USB".into());
        }
    }
    file.set_len(size)?;
    put64(&mut h, 32, last);
    put64(&mut h, 48, end);
    let crc = crc32(&h[..92]);
    put32(&mut h, 16, crc);
    at(file, 512, &h)?;
    put64(&mut h, 24, last);
    put64(&mut h, 32, 1);
    put64(&mut h, 72, last - table_sectors);
    put32(&mut h, 16, 0);
    let crc = crc32(&h[..92]);
    put32(&mut h, 16, crc);
    at(file, (last - table_sectors) * 512, &entries)?;
    at(file, last * 512, &h)?;
    let mut mbr = [0; 512];
    file.seek(SeekFrom::Start(0))?;
    file.read_exact(&mut mbr)?;
    for i in 0..4 {
        let off = 446 + i * 16;
        if mbr[off + 4] == 0xee {
            put32(&mut mbr, off + 12, last.min(u32::MAX as u64) as u32);
        }
    }
    at(file, 0, &mbr)?;
    file.sync_all()?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gpt_geometry_and_crc() -> Result<()> {
        let w = windows::Workspace::new()?;
        let p = w.path.join("layout.img");
        let mut f = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(p)?;
        windows(&mut f, 16 * 1024 * 1024, 8192, true, false)?;
        relocate_gpt(&mut f, 32 * 1024 * 1024)?;
        assert_eq!(f.metadata()?.len(), 32 * 1024 * 1024);
        f.seek(SeekFrom::Start(512))?;
        let mut h = [0; 512];
        f.read_exact(&mut h)?;
        assert_eq!(get64(&h, 32), 65535);
        h[88] ^= 1;
        at(&mut f, 512, &h)?;
        assert!(relocate_gpt(&mut f, 64 * 1024 * 1024).is_err());
        Ok(())
    }
}
