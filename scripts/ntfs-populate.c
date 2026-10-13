/* Mafus NTFS image writer, GPL-3.0-or-later; links NTFS-3G. Only regular image files. */
#include "config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <locale.h>
#include "ntfs-3g/volume.h"
#include "ntfs-3g/dir.h"
#include "ntfs-3g/inode.h"
#include "ntfs-3g/attrib.h"
#include "ntfs-3g/unistr.h"
static void fail(const char *s) { perror(s); exit(1); }
static ntfs_inode *directory(ntfs_volume *v, char *path) {
 ntfs_inode *parent=ntfs_pathname_to_inode(v,NULL,"/"); if(!parent) fail("NTFS root");
 char *save=NULL;
 for(char *name=strtok_r(path,"/",&save);name;name=strtok_r(NULL,"/",&save)) {
  if(!strcmp(name,".") || !strcmp(name,"..")) fail("Invalid path");
  ntfs_inode *next=ntfs_pathname_to_inode(v,parent,name);
  if(!next) { ntfschar *u=NULL; int len=ntfs_mbstoucs(name,&u); if(len<1||len>255) fail("NTFS name"); next=ntfs_create(parent,const_cpu_to_le32(0),u,len,S_IFDIR); free(u); }
  if(!next) fail("Create NTFS directory");
  if(ntfs_inode_close(parent)) fail("Close parent"); parent=next;
 }
 return parent;
}
int main(int argc,char **argv) {
 if(argc!=3) return 2;
 setlocale(LC_ALL,"en_US.UTF-8");
 struct stat st; if(lstat(argv[1],&st)||!S_ISREG(st.st_mode)) fail("Expected regular image file");
 FILE *manifest=fopen(argv[2],"rb"); if(!manifest) fail("Manifest");
 ntfs_volume *v=ntfs_mount(argv[1],0); if(!v) fail("Mount NTFS image");
 char *source=NULL,*relative=NULL; size_t sc=0,rc=0; unsigned char *data=malloc(1048576),*check=malloc(1048576); if(!data||!check) fail("Memory");
 while(getdelim(&source,&sc,0,manifest)>0) {
  if(getdelim(&relative,&rc,0,manifest)<=1 || relative[0]=='/') fail("Invalid manifest path");
  char *last=strrchr(relative,'/'),*name=last?last+1:relative;
  if(!*name||!strcmp(name,".")||!strcmp(name,"..")) fail("Invalid filename");
  if(last) *last=0;
  ntfs_inode *parent=directory(v,last?relative:"");
  ntfschar *unicode=NULL; int len=ntfs_mbstoucs(name,&unicode); if(len<1||len>255) fail("Filename encoding");
  ntfs_inode *ni=ntfs_create(parent,const_cpu_to_le32(0),unicode,len,S_IFREG); free(unicode); if(!ni) fail("Create NTFS file");
  if(ntfs_inode_close(parent)) fail("Close NTFS parent");
  ntfs_attr *attr=ntfs_attr_open(ni,AT_DATA,AT_UNNAMED,0); if(!attr) fail("Open NTFS stream");
  FILE *input=fopen(source,"rb"); if(!input) fail("Source"); s64 done=0; size_t count;
  while((count=fread(data,1,1048576,input))) { if(ntfs_attr_pwrite(attr,done,count,data)!=(s64)count) fail("NTFS write"); done+=count; }
  if(ferror(input)) fail("Source read"); rewind(input); done=0;
  while((count=fread(data,1,1048576,input))) { if(ntfs_attr_pread(attr,done,count,check)!=(s64)count||memcmp(data,check,count)) fail("NTFS verification"); done+=count; }
  if(ferror(input)) fail("Source verification read");
  fclose(input); ntfs_attr_close(attr); if(ntfs_inode_close(ni)) fail("Close NTFS file");
 }
 if(ferror(manifest)) fail("Manifest read"); fclose(manifest); free(source);free(relative);free(data);free(check);
 if(ntfs_umount(v,0)) fail("Unmount NTFS image"); return 0;
}
