//! File and raw-device synchronization are different operations on macOS.
//! Rust File::sync_all uses F_FULLFSYNC, which a /dev/rdiskN may reject with ENOTTY.
use std::{
    fs::File,
    io,
    os::{fd::AsRawFd, unix::fs::FileTypeExt},
};

// SDK sys/disk.h: _IO('d', 22), supported by the macOS storage driver.
const DKIOCSYNCHRONIZECACHE: std::ffi::c_ulong = 0x20006416;
unsafe extern "C" {
    fn ioctl(fd: std::ffi::c_int, request: std::ffi::c_ulong, ...) -> std::ffi::c_int;
    fn fsync(fd: std::ffi::c_int) -> std::ffi::c_int;
}

pub(crate) fn sync(file: &File) -> io::Result<()> {
    if file.metadata()?.file_type().is_char_device() {
        // Raw I/O bypasses the filesystem. Flush the device's own write cache instead.
        // Never turn a failed device flush into successful completion.
        if unsafe { ioctl(file.as_raw_fd(), DKIOCSYNCHRONIZECACHE, 0usize) } == -1 {
            let error = io::Error::last_os_error();
            return Err(io::Error::new(
                error.kind(),
                format!("Cannot flush USB device cache: {error}"),
            ));
        }
        return Ok(());
    }
    // Some FAT/exFAT filesystem implementations do not expose F_FULLFSYNC.
    // POSIX fsync still flushes their file data; the final volume unmount flushes the disk.
    file_sync_with_fallback(file.sync_all(), || {
        if unsafe { fsync(file.as_raw_fd()) } == -1 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    })
}

fn file_sync_with_fallback(
    result: io::Result<()>,
    fallback: impl FnOnce() -> io::Result<()>,
) -> io::Result<()> {
    match result {
        Err(error) if matches!(error.raw_os_error(), Some(19 | 22 | 25 | 45)) => fallback(),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unsupported_fullsync_uses_real_fsync_but_does_not_hide_io_errors() {
        for code in [19, 22, 25, 45] {
            let mut called = false;
            file_sync_with_fallback(Err(io::Error::from_raw_os_error(code)), || {
                called = true;
                Ok(())
            })
            .unwrap();
            assert!(called);
        }
        let error = file_sync_with_fallback(Err(io::Error::from_raw_os_error(5)), || {
            panic!("I/O errors must not be ignored")
        })
        .unwrap_err();
        assert_eq!(error.raw_os_error(), Some(5));
        let error = file_sync_with_fallback(Err(io::Error::from_raw_os_error(25)), || {
            Err(io::Error::from_raw_os_error(5))
        })
        .unwrap_err();
        assert_eq!(error.raw_os_error(), Some(5));
    }
    #[test]
    fn raw_device_flush_failure_is_reported() {
        // /dev/null is a harmless character device, not a disk. It rejects disk ioctls.
        // No USB is opened and no data is written.
        let file = File::open("/dev/null").unwrap();
        let error = sync(&file).unwrap_err();
        assert!(error.to_string().contains("Cannot flush USB device cache"));
    }
}
