from pathlib import Path
import re,tarfile
root=Path(__file__).resolve().parents[1]
with tarfile.open(root/'vendor/ms-sys.tar.gz') as archive:
 for name,header in [('windows-mbr.bin','mbr_win7.h'),('windows-ntfs-jump.bin','br_ntfs_0x0.h'),('windows-ntfs-code.bin','br_ntfs_0x54.h')]:
  source=archive.extractfile('ms-sys-master/inc/'+header).read().decode()
  body=source.split('{',1)[1].split('}',1)[0]
  data=bytes(int(value,16) for value in re.findall(r'0x([0-9a-fA-F]{2})',body))
  (root/'vendor'/name).write_bytes(data)
