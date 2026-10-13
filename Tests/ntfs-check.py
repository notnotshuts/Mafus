import pathlib,tempfile,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
bin=root/'.build/tools'
ntfs=root/'.build/vendor/ntfs-3g-2026.9.28/ntfsprogs'
with tempfile.TemporaryDirectory() as td:
 d=pathlib.Path(td); image=d/'ntfs.img'
 with image.open('wb') as f:f.truncate(128*1024*1024)
 subprocess.run([bin/'mkntfs','-F','-Q','-s','512','-L','MAFUS',image],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 payload=d/'payload';payload.write_bytes(bytes(range(256))*512)
 script=d/'script';script.write_bytes(b'echo integration fixture\r\n')
 manifest=d/'manifest';manifest.write_bytes(str(payload).encode()+b'\0efi/boot/bootx64.efi\0'+str(script).encode()+b'\0sources/$OEM$/$$/Setup/Scripts/Mafus-Specialize.ps1\0')
 subprocess.run([bin/'ntfs-populate',image,manifest],check=True)
 for path,expected in [('/efi/boot/bootx64.efi',payload),('/sources/$OEM$/$$/Setup/Scripts/Mafus-Specialize.ps1',script)]:
  actual=subprocess.run([ntfs/'ntfscat',image,path],check=True,stdout=subprocess.PIPE).stdout
  assert actual==expected.read_bytes(),path
print('NTFS checks passed: directories, EFI, OEM scripts and read-back via ntfscat')
