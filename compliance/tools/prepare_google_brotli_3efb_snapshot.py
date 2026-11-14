#!/usr/bin/env python3
"""Create a deterministic complete Git-tree source snapshot for the D2 JS decoder reference."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import posixpath

COMMIT='3efb30f96ba50389c4a2fcd9f884b7dbfbadebae'
TREE='98bf174cfe47330ba0ad0db0ad96224830ef1588'
PREFIX='brotli-3efb30f-git/'

def git(repo,*args): return subprocess.check_output(['git','-C',str(repo),*args])
def sha(body): return hashlib.sha256(body).hexdigest()
def capture(repo):
    if git(repo,'rev-parse',COMMIT+'^{tree}').strip().decode()!=TREE:
        raise ValueError('Google Brotli tree changed')
    rows=git(repo,'ls-tree','-r','-z',COMMIT).split(b'\0')
    files={}
    for row in rows:
        if not row: continue
        header,path=row.split(b'\t',1)
        mode,kind,oid=header.decode().split()
        name=path.decode()
        pure=PurePosixPath(name)
        if kind!='blob' or mode not in ('100644','100755','120000') or pure.is_absolute() or '..' in pure.parts:
            raise ValueError('unsafe source entry '+name)
        files[name]=(mode,git(repo,'cat-file','blob',oid))
    if len(files)!=377 or sum(p.startswith('js/') for p in files)!=14:
        raise ValueError('Brotli source file set changed')
    for required in ('LICENSE','README.md','js/decode.ts','js/decode.js','js/decode.min.js','js/package.json'):
        if required not in files: raise ValueError('source input missing '+required)
    if sha(files['LICENSE'][1])!='3d180008e36922a4e8daec11c34c7af264fed5962d07924aea928c38e8663c94':
        raise ValueError('MIT root licence changed')
    if sha(files['js/decode.min.js'][1])!='2055420568c3701fdd83a53f6bd0fb8d7f3352b571f3057eedaf555e750f8235':
        raise ValueError('decoder generated input changed')
    return files

def write(path,files):
    if path.exists(): raise ValueError('refusing to overwrite source archive')
    with path.open('xb') as output,gzip.GzipFile(fileobj=output,mode='wb',mtime=0,filename='') as gz:
        with tarfile.open(fileobj=gz,mode='w',format=tarfile.PAX_FORMAT) as tar:
            for name,(mode,body) in sorted(files.items()):
                item=tarfile.TarInfo(PREFIX+name)
                item.mode,item.mtime,item.uid,item.gid=0o755 if mode=='100755' else 0o644,0,0,0
                item.uname=item.gname=''
                if mode=='120000':
                    target=body.decode()
                    resolved=posixpath.normpath(posixpath.join(posixpath.dirname(name),target))
                    if PurePosixPath(target).is_absolute() or resolved == '..' or resolved.startswith('../'):
                        raise ValueError('symlink escapes source tree')
                    item.type=tarfile.SYMTYPE
                    item.linkname=target
                    tar.addfile(item)
                else:
                    item.size=len(body)
                    tar.addfile(item,io.BytesIO(body))
    with tarfile.open(path,'r:gz') as tar:
        found={item.name.removeprefix(PREFIX):( '120000' if item.issym() else '100755' if item.mode & 0o111 else '100644',
                item.linkname.encode() if item.issym() else tar.extractfile(item).read()) for item in tar}
    if found!=files: raise ValueError('source archive readback mismatch')
    return {'commit':COMMIT,'tree':TREE,'files':len(files),'javascript_files':14,
            'archive_bytes':path.stat().st_size,'archive_sha256':sha(path.read_bytes()),
            'decode_min_sha256':sha(files['js/decode.min.js'][1]),
            'decode_ts_sha256':sha(files['js/decode.ts'][1]),
            'licence_sha256':sha(files['LICENSE'][1])}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    print(json.dumps(write(a.output,capture(a.repo)),indent=2,sort_keys=True))
if __name__=='__main__': main()
