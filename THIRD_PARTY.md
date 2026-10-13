# Dependencies distributed with Mafus 0.1.0

Mafus application code is GPL-3.0-or-later. Source archives, dependency licenses and build scripts accompany the application/source package. Native binaries are built for macOS 14+ on Apple Silicon; no FUSE installation is required.

| Component | Version | Use | Upstream |
|---|---|---|---|
| wimlib | 1.14.4 | WIM/ESD/SWM | https://wimlib.net/ |
| XZ Utils | 5.8.4 | XZ decompression | https://tukaani.org/xz/ |
| Zstandard | 1.5.7 | Zstandard decompression | https://github.com/facebook/zstd |
| NTFS-3G / ntfsprogs | 2026.9.28 | Create and populate staged NTFS images | https://github.com/tuxera/ntfs-3g |
| xorriso | 1.5.8 pl02 | Replay ISO boot equipment and append persistence | https://www.gnu.org/software/xorriso/ |
| e2fsprogs | 1.47.3 | Create ext4 filesystem images | https://www.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/ |
| ms-sys | upstream source snapshot | BOOTMGR NTFS bootstrap and Windows 7 compatible MBR | https://github.com/pbatard/ms-sys |
| UEFI:NTFS | 2.8, signed image from Rufus | EFI filesystem bridge | https://github.com/pbatard/uefi-ntfs |
| EFI NTFS / EfiFs | 1.9 / 1.12 | Drivers in UEFI:NTFS FAT image | https://github.com/pbatard/ntfs-3g and https://github.com/pbatard/EfiFs |
| pkg-config | 0.29.2 | Build tool only | https://pkgconfig.freedesktop.org/ |
| libarchive | supplied by macOS | Read ZIP streams | https://www.libarchive.org/ |

The UEFI FAT image is obtained from Rufus `res/uefi/uefi-ntfs.img`. Its accompanying upstream description is included in `vendor/UEFI-IMAGE-README.txt`. Signed EFI binaries are preserved as published. Signature trust and revocation depend on target firmware; Mafus does not promise Secure Boot compatibility on every machine.

EFI projects use gnu-efi, and EfiFs uses GRUB as submodules. Exact upstream submodule revisions and additional source archives are listed in `vendor/EFI-SUBMODULES.txt`. Upstream release source can also be checked out recursively at the versions above. Signing keys are not part of Mafus.

FreeDOS is downloaded on demand from https://download.freedos.org/1.4/FD14-LiteUSB.zip and checked against the project's published SHA-256. No FreeDOS or Microsoft DOS system files are embedded in Mafus. MS-DOS requires a bootable image supplied by the user.

Mafus generates its own Windows customization scripts and unattended XML. Windows customization behavior was checked against Microsoft unattended documentation and Rufus's feature descriptions; the Rufus source is not compiled into the application. The ms-sys boot resources are compiled data from GPL-2.0-or-later source, retained in the source package.
