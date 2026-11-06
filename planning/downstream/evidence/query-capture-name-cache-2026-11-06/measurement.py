from pathlib import Path
import hashlib,json,statistics,subprocess
root=Path(__file__).parent;bins={'baseline':root/'build/release/ParserQueryProfile','candidate':root/'candidate-build/release/ParserQueryProfile'};rows=[];hashes={}
for phase,binary in bins.items():
 links=subprocess.check_output(['otool','-L',str(binary)],text=True);assert not any(x in links for x in ['AppKit','SwiftUI','WebKit','CoreGraphics','CoreText','QuartzCore']);hashes[phase]=hashlib.sha256(binary.read_bytes()).hexdigest()
for pair in range(8):
 digests=[]
 for phase in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
  log=root/('final-names-'+str(pair)+'-'+phase+'.jsonl');capture=root/('final-names-'+str(pair)+'-'+phase+'-captures.json')
  with log.open('w') as f:subprocess.run([str(bins[phase]),'3',str(capture)],stdout=f,stderr=subprocess.STDOUT,check=True,timeout=30)
  raw=[json.loads(s) for s in log.read_text().splitlines()];assert raw[-2:]==[{'metadata_controls':True},{'range_alias_concurrent_controls':True}];values=raw[:-2];assert len(values)==3 and all(x['captures']==23256 for x in values)
  sha=hashlib.sha256(capture.read_bytes()).hexdigest();digests.append(sha);rows.append({'pair':pair,'phase':phase,'capture_sha256':sha,'metadata_controls':True,'values':values})
 assert len(set(digests))==1
summary={}
for phase in bins:
 values=[v for row in rows if row['phase']==phase for v in row['values']];summary[phase]={key:statistics.median(x[key] for x in values) for key in ['parse_seconds','query_seconds','total_seconds']}
summary.update(query_reduction=1-summary['candidate']['query_seconds']/summary['baseline']['query_seconds'],total_reduction=1-summary['candidate']['total_seconds']/summary['baseline']['total_seconds'],identical_ordered_captures=len({x['capture_sha256'] for x in rows})==1,production_adopted=False,scope='Owned-copy experiment only; exact current fixture and explicit named/global/last-wins/depth, range-reuse and concurrent cursor controls. No hosted/full-suite or general policy acceptance.')
for phase,binary in bins.items():assert hashlib.sha256(binary.read_bytes()).hexdigest()==hashes[phase]
(root/'final-names-cache-results.json').write_text(json.dumps({'summary':summary,'hashes':hashes,'rows':rows},indent=2)+'\n');print(summary)
