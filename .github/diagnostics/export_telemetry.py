"""Read-only white-list telemetry around original export guard exceptions.
Diagnostic receipts always use injected dependencies, never publishable artifacts.
"""
import argparse,json,sys,time,os,threading
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'ci'))
import run_export as m
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
 for name in ('lock','project','output','private','godot','template','import-marker','diagnostic-output'):p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();out=a.diagnostic_output
 assert not out.exists();out.mkdir(mode=0o700)
 original_metrics=m.p.process_metrics;original_spawn=m.subprocess.Popen
 events=[];errors=[];runs=[];lock=threading.Lock()
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
   def spawn(*args,**kwargs):
    child=original_spawn(*args,**kwargs)
    try:
     worker=threading.Thread(target=observe,args=(child,identity(child.pid)),daemon=True)
     worker.start();workers.append(worker)
    except BaseException as exc:
     with lock:errors.append({'attempt':attempt,'observer_error':type(exc).__name__,'phase':'start'})
    return child  # Original guard must receive ownership even if instrumentation fails.
   def observed(child):
    try:return original_metrics(child)
    except (FileNotFoundError,KeyError,ProcessLookupError,PermissionError) as exc:
     record(child,'guard_'+type(exc).__name__,attempt);raise
   m.subprocess.Popen=spawn;m.p.process_metrics=observed
   args=argparse.Namespace(**vars(a));args.output=Path(str(a.output)+'-'+str(attempt));args.private=Path(str(a.private)+'-'+str(attempt))
   try:
    code=m.run(args)
   finally:
    stop.set()
    for worker in workers:worker.join(timeout=5)
    if any(worker.is_alive() for worker in workers):errors.append({'attempt':attempt,'observer_error':'JoinTimeout'})
    m.subprocess.Popen=original_spawn;m.p.process_metrics=original_metrics
   receipt=json.loads((args.output/'export-1/receipt.json').read_text())
   runs.append({'attempt':attempt,'guard_passed':receipt['passed'],'cleanup_complete':receipt['cleanup_complete'],'export_completed':receipt.get('export_completed',False),'test_dependencies':receipt['test_dependencies'],'observer_joined':all(not w.is_alive() for w in workers),'original_run_exit':code})
   if errors or events or not receipt['passed'] or not receipt['cleanup_complete']:break
 finally:
  m.p.process_metrics=original_metrics;m.subprocess.Popen=original_spawn
  (out/'summary.json').write_text(json.dumps({'scope':'Private bounded hosted exit observation only; not release validation','source':m.SOURCE,'build':m.BUILD,'instrumented_dependencies':True,'publishable':False,'maximum_exports':2,'event_count':len(events),'observer_errors':errors,'runs':runs},indent=2)+'\n')
 return 1  # Diagnostic observations can never be a successful release workflow.
if __name__=='__main__':raise SystemExit(main())
