from pathlib import Path
import subprocess,os,time,json,hashlib,math,sys
p=Path(__file__).parent;raw=p/'raw';raw.mkdir(exist_ok=True);home=p/'home';home.mkdir(exist_ok=True)
fixtures=json.loads((p/'fixtures.json').read_text());env=os.environ.copy();env['CFFIXED_USER_HOME']=str(home);env['LLVM_PROFILE_FILE']=str(p/'measure-%p.profraw')
manifest=[]
for fixture in fixtures:
 for operation in ['snapshot','revision','probe']:
  for population,index in [('fresh',i) for i in range(20)]+[('warm',0)]:
   stem=f'{fixture["size"]}-{operation}-{population}-{index:02}'
   args=[str(p/'harness'),operation,fixture['path'],'--expected-size',str(fixture['size']),'--expected-sha256',fixture['sha256']]+(['--once'] if population=='fresh' else ['--warm-count','50'])
   started=time.monotonic();peak=0;stop=None
   with (raw/(stem+'.jsonl')).open('w') as out,(raw/(stem+'.stderr')).open('w') as err:
    proc=subprocess.Popen(args,cwd=p,env=env,stdout=out,stderr=err)
    while proc.poll() is None:
     r=subprocess.run(['ps','-p',str(proc.pid),'-o','rss='],capture_output=True,text=True)
     if r.stdout.strip().isdigit():peak=max(peak,int(r.stdout.strip()))
     if peak>512*1024:stop='512MiB owned-child RSS threshold'
     if time.monotonic()-started>20:stop='20-second owned-child deadline'
     if stop:
      proc.terminate()
      try:proc.wait(timeout=2)
      except subprocess.TimeoutExpired:proc.kill();proc.wait()
      break
     time.sleep(.05)
   rows=[json.loads(line) for line in (raw/(stem+'.jsonl')).read_text().splitlines()]
   samples=[r for r in rows if r.get('type')=='sample'];error=next((r.get('validationError') for r in samples if r.get('validationError')),None)
   item={'stem':stem,'arguments':args,'pid':proc.pid,'exit':proc.returncode,'seconds':time.monotonic()-started,'peakObservedRSSKiB':peak,'stopReason':stop,'sampleCount':len(samples),'error':error,'hostLoadAverage':os.getloadavg()};manifest.append(item);(p/'run-manifest.json').write_text(json.dumps(manifest,indent=2))
   expected=1 if population=='fresh' else 51
   if proc.returncode or stop or error or len(samples)!=expected:
    print(json.dumps({'failed':item}),flush=True);sys.exit(1)
  print(f'Completed {fixture["size"]} {operation}:20fresh+50warm+1prime',flush=True)
summary=[]
for fixture in fixtures:
 for operation in ['snapshot','revision','probe']:
  for label in ['first-read-fresh-process-cache-uncontrolled','warm-same-process']:
   samples=[]
   for f in raw.glob(f'{fixture["size"]}-{operation}-*.jsonl'):
    samples += [r for r in map(json.loads,f.read_text().splitlines()) if r.get('type')=='sample' and r['cacheLabel']==label]
   values=sorted(r['apiNanoseconds']/1e6 for r in samples);outer=sorted(r['outerDetachedNanoseconds']/1e6 for r in samples)
   percentile=lambda v,q:v[max(0,math.ceil(len(v)*q)-1)]
   summary.append({'sizeBytes':fixture['size'],'operation':operation,'cacheLabel':label,'count':len(values),'apiMilliseconds':{'p50':percentile(values,.5),'p95':percentile(values,.95),'max':max(values)},'outerMilliseconds':{'p50':percentile(outer,.5),'p95':percentile(outer,.95),'max':max(outer)},'maxProcessPeakResidentBytes':max(r['memoryAfter'].get('processPeakResidentBytes',0) for r in samples)})
(p/'summary.json').write_text(json.dumps(summary,indent=2));print('Serial matrix complete',flush=True)
