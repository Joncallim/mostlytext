#!/usr/bin/env python3
"""Extract only digest-pinned decoder scripts for the D2/Google AST comparison."""
import argparse
import hashlib
from pathlib import Path
import tarfile

INPUTS=(
 ('d2_source','91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391',
  'd2-581c91096b62d644fb5168313142c836b7e68e74/d2js/js/vendor/decode.min.js',
  'd2-decode.min.js','67de1ff9e3bf170ca99d317a6466cb107f288a1f565f3971cd7dd8dc9922f677'),
 ('google_source','833366021ae552ceb40a14f1c71619d2af7a5c7765472882434b5094ff811536',
  'brotli-3efb30f-git/js/decode.min.js','google-decode.min.js',
  '2055420568c3701fdd83a53f6bd0fb8d7f3352b571f3057eedaf555e750f8235'),
)
def sha(body):return hashlib.sha256(body).hexdigest()
def extract(source,archive_sha,member_name,member_sha):
 if sha(source.read_bytes())!=archive_sha:raise ValueError('source archive digest changed: '+source.name)
 with tarfile.open(source,'r:gz') as tar:
  item=tar.getmember(member_name)
  if not item.isfile() or item.size>262144:raise ValueError('decoder source is not a bounded regular file')
  body=tar.extractfile(item).read()
 if sha(body)!=member_sha:raise ValueError('decoder member digest changed: '+member_name)
 return body

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--d2-source',type=Path,required=True)
 p.add_argument('--google-source',type=Path,required=True)
 p.add_argument('--output',type=Path,required=True)
 a=p.parse_args()
 if a.output.exists() and (not a.output.is_dir() or any(a.output.iterdir())):
  raise ValueError('output directory must be empty')
 files=[(name,extract(getattr(a,field),archive_sha,member,member_sha))
        for field,archive_sha,member,name,member_sha in INPUTS]
 a.output.mkdir(parents=True,exist_ok=True)
 for name,body in files:
  with (a.output/name).open('xb') as out:out.write(body)
  print(name,len(body),sha(body))
if __name__=='__main__':main()
