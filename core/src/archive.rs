use super::*;
use std::ffi::{c_char, c_void, CStr, CString};
#[link(name = "archive")]
unsafe extern "C" {
    fn archive_read_new() -> *mut c_void;
    fn archive_read_free(a: *mut c_void) -> i32;
    fn archive_read_support_format_zip(a: *mut c_void) -> i32;
    fn archive_read_open_filename(a: *mut c_void, path: *const c_char, block: usize) -> i32;
    fn archive_read_next_header(a: *mut c_void, entry: *mut *mut c_void) -> i32;
    fn archive_read_data(a: *mut c_void, data: *mut c_void, size: usize) -> isize;
    fn archive_read_data_skip(a: *mut c_void) -> i32;
    fn archive_error_string(a: *mut c_void) -> *const c_char;
    fn archive_entry_pathname(e: *mut c_void) -> *const c_char;
    fn archive_entry_filetype(e: *mut c_void) -> u32;
    fn archive_entry_size(e: *mut c_void) -> i64;
    fn archive_entry_symlink(e: *mut c_void) -> *const c_char;
    fn archive_entry_hardlink(e: *mut c_void) -> *const c_char;
}
struct Reader(*mut c_void);
impl Drop for Reader {
    fn drop(&mut self) {
        unsafe {
            archive_read_free(self.0);
        }
    }
}
impl Reader {
    fn error(&self) -> Box<dyn std::error::Error> {
        let p = unsafe { archive_error_string(self.0) };
        if p.is_null() {
            "Invalid ZIP archive".into()
        } else {
            unsafe { CStr::from_ptr(p) }
                .to_string_lossy()
                .into_owned()
                .into()
        }
    }
}
pub fn extract(
    original: &Path,
    limit: u64,
    report: &mut impl FnMut(u64) -> io::Result<()>,
) -> Result<(PathBuf, windows::Workspace)> {
    let workspace = windows::Workspace::new()?;
    let reader = Reader(unsafe { archive_read_new() });
    if reader.0.is_null() {
        return Err("No ZIP reader".into());
    }
    let name = CString::new(original.as_os_str().as_encoded_bytes())?;
    unsafe {
        if archive_read_support_format_zip(reader.0) != 0
            || archive_read_open_filename(reader.0, name.as_ptr(), 65536) != 0
        {
            return Err(reader.error());
        }
    }
    let mut result = None;
    let mut entries = 0;
    loop {
        let mut e = std::ptr::null_mut();
        let status = unsafe { archive_read_next_header(reader.0, &mut e) };
        if status == 1 {
            break;
        }
        if status != 0 {
            return Err(reader.error());
        }
        entries += 1;
        if entries > 10000 {
            return Err("Too many ZIP entries".into());
        }
        let p = unsafe { archive_entry_pathname(e) };
        if p.is_null() {
            return Err("Invalid ZIP name".into());
        }
        let relative = unsafe { CStr::from_ptr(p) }.to_str()?;
        if relative.starts_with('/')
            || relative.contains('\\')
            || relative.split('/').any(|s| s == "..")
        {
            return Err("Unsafe ZIP path".into());
        }
        let ext = Path::new(relative)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();
        if !["img", "iso", "vhd"].contains(&ext.as_str()) {
            if unsafe { archive_read_data_skip(reader.0) } < 0 {
                return Err(reader.error());
            }
            continue;
        }
        if result.is_some() {
            return Err("ZIP must contain exactly one ISO, IMG or VHD".into());
        }
        if unsafe { archive_entry_filetype(e) } != 0o100000
            || !unsafe { archive_entry_symlink(e) }.is_null()
            || !unsafe { archive_entry_hardlink(e) }.is_null()
        {
            return Err("ZIP image must be a regular file".into());
        }
        let declared = unsafe { archive_entry_size(e) };
        if declared <= 0 || declared as u64 > limit {
            return Err("ZIP image exceeds USB capacity".into());
        }
        let path = workspace.path.join(format!("extracted.{ext}"));
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        let mut bytes = vec![0u8; CHUNK];
        let mut total = 0;
        loop {
            let n = unsafe { archive_read_data(reader.0, bytes.as_mut_ptr().cast(), bytes.len()) };
            if n < 0 {
                return Err(reader.error());
            }
            if n == 0 {
                break;
            }
            total += n as u64;
            if total > limit || total > declared as u64 {
                return Err("ZIP expanded size exceeds limit".into());
            }
            file.write_all(&bytes[..n as usize])?;
            report(total)?;
        }
        if total != declared as u64 {
            return Err("Truncated ZIP payload".into());
        }
        file.sync_all()?;
        result = Some(path);
    }
    Ok((result.ok_or("ZIP contains no image")?, workspace))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn single_image_and_capacity() -> Result<()> {
        let w = windows::Workspace::new()?;
        let image = w.path.join("test.img");
        fs::write(&image, vec![3; 512])?;
        let zip = w.path.join("test.zip");
        assert!(Command::new("/usr/bin/zip")
            .arg("-jq")
            .arg(&zip)
            .arg(&image)
            .status()?
            .success());
        let (p, _w) = extract(&zip, 512, &mut |_| Ok(()))?;
        assert_eq!(fs::read(p)?, vec![3; 512]);
        assert!(extract(&zip, 511, &mut |_| Ok(())).is_err());
        let another = w.path.join("another.img");
        fs::write(&another, vec![4; 512])?;
        Command::new("/usr/bin/zip")
            .arg("-jq")
            .arg(&zip)
            .arg(&another)
            .status()?;
        assert!(extract(&zip, 1024, &mut |_| Ok(())).is_err());
        Ok(())
    }
}
