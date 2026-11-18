"""Read-only white-list telemetry around original import guard gaps.
Diagnostic receipts always use injected dependencies, never publishable artifacts.
"""
import argparse,json,sys,time,os,threading
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ci'))
import guarded_manifest_ci as adapter
import prepare_web_release as prep
KEYS=('State','Tgid','Pid','Threads','VmRSS','VmHWM')
def bounded(path):
 with path.open() as f:s=f.read(65537)
 if len(s)>65536:raise ValueError('Oversized proc observation')
 return s

def fields(path):
 try:
  f=dict(l.split(':',1) for l in bounded(path).splitlines() if ':' in l)
  return {k:f.get(k,'MISSING').strip() for k in KEYS}
 except (FileNotFoundError,ProcessLookupError,PermissionError) as e:return {'read_error':type(e).__name__}

def task_identity(path):
 try:
  raw=bounded(path);pid=int(raw.split(' ',1)[0]);tail=raw[raw.rfind(')')+2:].split()
  return {'pid':pid,'state':tail[0],'ppid':tail[1],'starttime_ticks':tail[19],'flags':int(tail[6]),'exit_signal':int(tail[35]),'exit_code':int(tail[49])}
 except (FileNotFoundError,ProcessLookupError,PermissionError) as e:return {'read_error':type(e).__name__}

def identity(pid):
 return task_identity(Path(f'/proc/{pid}/stat'))

def statm(path):
 try:
  values=bounded(path).split()
  if len(values)!=7 or not all(x.isdigit() for x in values):raise ValueError('Malformed statm observation')
  return [int(x) for x in values]
 except (FileNotFoundError,ProcessLookupError,PermissionError) as e:return {'read_error':type(e).__name__}

def snapshot(child):
 root=Path(f'/proc/{child.pid}');x={'monotonic':time.monotonic(),'identity_before':identity(child.pid),'leader':fields(root/'status'),'statm':statm(root/'statm'),'tasks':[]}
 try:
  tasks=sorted((root/'task').iterdir());x['task_count']=len(tasks)
  if len(tasks)>128:raise ValueError('Proc task observation bound exceeded')
  for p in tasks:
   d=fields(p/'status');d['stat']=task_identity(p/'stat');d['statm']=statm(p/'statm')
   try:
    raw=bounded(p/'children');d['children']=raw.split()
    if len(d['children'])>128:raise ValueError('Proc child observation bound exceeded')
   except (FileNotFoundError,ProcessLookupError,PermissionError) as e:d['children_error']=type(e).__name__
   x['tasks'].append(d)
 except (FileNotFoundError,ProcessLookupError,PermissionError) as e:x['tasks_error']=type(e).__name__
 x['identity_after']=identity(child.pid);return x

def main():
 p=argparse.ArgumentParser()
 for name in ('work','godot','diagnostic-output'):p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();out=a.diagnostic_output
 assert not out.exists();out.mkdir(mode=0o700)
 events=[];errors=[];runs=[];lock=threading.Lock();original_load=adapter.load_monitor
 def record(child,kind,attempt):
  with lock:
   if len(events)>=4:raise RuntimeError('Diagnostic event bound exceeded')
   pair=[snapshot(child),snapshot(child)]
   for x in pair:
    before=x['identity_before'];after=x['identity_after']
    if 'read_error' not in before and 'read_error' not in after and (before['pid'],before['starttime_ticks'])!=(after['pid'],after['starttime_ticks']):raise RuntimeError('Observed lifetime changed')
   events.append({'kind':kind,'attempt':attempt,'kernel_release':os.uname().release,'adjacent_snapshots':pair})
   (out/'telemetry.json').write_text(json.dumps(events,indent=2)+'\n')
 try:
  for attempt in (1,2):
   work=a.work/('attempt-'+str(attempt));prep.prepare('product',work)
   stop=threading.Event();workers=[]
   def observe(child,initial):
    began=time.monotonic();complete_seen=False
    try:
     while not stop.wait(.001):
      if time.monotonic()-began>300:raise RuntimeError('Observer wall bound exceeded')
      now=identity(child.pid)
      if now.get('read_error') in ('FileNotFoundError','ProcessLookupError'):break
      if 'read_error' in now or 'read_error' in initial:raise RuntimeError('Observer identity unavailable')
      if (now['pid'],now['starttime_ticks'])!=(initial['pid'],initial['starttime_ticks']):raise RuntimeError('Observer lifetime changed')
      row=fields(Path(f'/proc/{child.pid}/status'))
      if row.get('read_error') in ('FileNotFoundError','ProcessLookupError'):break
      if 'read_error' in row:raise RuntimeError('Observer status unavailable')
      if row['VmRSS']!='MISSING' and row['VmHWM']!='MISSING':complete_seen=True
      elif complete_seen:
       record(child,'complete_memory_to_missing',attempt);break
    except BaseException as exc:
     with lock:errors.append({'attempt':attempt,'observer_error':type(exc).__name__})
   def loaded():
    monitor=original_load();original_run=monitor.run;original_spawn=monitor.subprocess.Popen;original_metrics=monitor.process_metrics
    def spawn(*args,**kwargs):
     child=original_spawn(*args,**kwargs)
     try:
      worker=threading.Thread(target=observe,args=(child,identity(child.pid)),daemon=True)
      worker.start();workers.append(worker)
     except BaseException as exc:
      with lock:errors.append({'attempt':attempt,'observer_error':type(exc).__name__,'phase':'start'})
     return child
    def observed(pid):
     try:
      value=original_metrics(pid)
      if isinstance(value,dict) and 'VmRSS' not in value:
       record(type('ObservedPID',(),{'pid':pid})(),'guard_missing_VmRSS',attempt)
      return value
     except (FileNotFoundError,KeyError,ProcessLookupError,PermissionError) as exc:
      record(type('ObservedPID',(),{'pid':pid})(),'guard_'+type(exc).__name__,attempt);raise
    def run(*args,**kwargs):
     return original_run(*args,**kwargs,_popen=spawn,_process=observed)
    monitor.run=run
    return monitor
   adapter.load_monitor=loaded
   manifest=work/'import-manifest.json';archive=work/'source.zip'
   argv=['guarded_manifest_ci.py','import','--project',str(work/'project'),'--godot',str(a.godot),'--archive',str(archive),'--manifest',str(manifest),'--archive-sha256',prep.sha(archive),'--manifest-sha256',prep.sha(manifest),'--output',str(work/'import-evidence'),'--xdg',str(work/'private/import'),'--hosted-execution-approved']
   saved_argv=sys.argv
   try:
    sys.argv=argv;code=adapter.main()
   finally:
    sys.argv=saved_argv;stop.set()
    for worker in workers:worker.join(timeout=5)
    if any(worker.is_alive() for worker in workers):errors.append({'attempt':attempt,'observer_error':'JoinTimeout'})
    adapter.load_monitor=original_load
   receipt=json.loads((work/'import-evidence/import.json').read_text())
   invocation=json.loads((work/'import-evidence/import.invocation.json').read_text())
   phase=json.loads((work/'import-evidence/phase-summary.json').read_text())
   expected_diagnostic_rejection=phase.get('error',{}).get('message')=='Mocked/mismatched monitor invocation'
   assert invocation['test_dependencies'] is True
   runs.append({'attempt':attempt,'guard_passed':receipt['passed'],'cleanup_complete':receipt['cleanup_complete'],'test_dependencies':True,'observer_joined':all(not w.is_alive() for w in workers),'original_adapter_exit':code,'expected_diagnostic_rejection':expected_diagnostic_rejection})
   if errors or events or not receipt['passed'] or not receipt['cleanup_complete'] or not expected_diagnostic_rejection:break
 finally:
  adapter.load_monitor=original_load
  (out/'summary.json').write_text(json.dumps({'scope':'Private bounded hosted import observation only; not release validation','source':prep.SOURCE,'build':prep.SIDES['product']['build'],'instrumented_dependencies':True,'publishable':False,'maximum_imports':2,'event_count':len(events),'observer_errors':errors,'runs':runs},indent=2)+'\n')
 return 1
if __name__=='__main__':raise SystemExit(main())
