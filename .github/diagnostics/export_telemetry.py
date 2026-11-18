"""Read-only white-list telemetry around original export guard exceptions.
Diagnostic receipts always use injected dependencies, never publishable artifacts.
"""
import argparse,json,sys,time,os
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
 root=Path(f'/proc/{child.pid}');x={'monotonic':time.monotonic(),'poll_before':child.poll(),'identity_before':identity(child.pid),'leader':fields(root/'status'),'statm':statm(root/'statm'),'tasks':[]}
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
 x['identity_after']=identity(child.pid);x['poll_after']=child.poll();return x

def main():
 p=argparse.ArgumentParser()
 for name in ('lock','project','output','private','godot','template','import-marker','diagnostic-output'):p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();out=a.diagnostic_output
 assert not out.exists();out.mkdir(mode=0o700)
 original=m.p.process_metrics;events=[]
 def observed(child):
  try:return original(child)
  except (FileNotFoundError,KeyError,ProcessLookupError,PermissionError) as e:
   if len(events)>=4:raise RuntimeError('Diagnostic event bound exceeded') from e
   events.append({'initial_exception':type(e).__name__,'kernel_release':os.uname().release,'adjacent_snapshots':[snapshot(child),snapshot(child)]})
   (out/'telemetry.json').write_text(json.dumps(events,indent=2)+'\n')
   raise
 m.p.process_metrics=observed
 try:
  code=m.run(a)
 finally:
  m.p.process_metrics=original
  (out/'summary.json').write_text(json.dumps({'scope':'Private hosted export telemetry only; not release validation','source':m.SOURCE,'build':m.BUILD,'instrumented_dependencies':True,'publishable':False,'event_count':len(events)},indent=2)+'\n')
 return code
if __name__=='__main__':raise SystemExit(main())
