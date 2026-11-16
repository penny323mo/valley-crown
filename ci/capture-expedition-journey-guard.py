import os,sys,json,time,resource,subprocess,signal,hashlib,pathlib
R=pathlib.Path('/tmp/capture'); G=R; name='native-render'
def metrics():
 m={l.split(':')[0]:int(l.split()[1]) for l in pathlib.Path('/proc/meminfo').read_text().splitlines()}
 o=int(next(l.split()[1] for l in pathlib.Path('/proc/vmstat').read_text().splitlines() if l.startswith('oom_kill ')))
 return {'available_kib':m['MemAvailable'],'oom':o}
r={'baseline':metrics(),'limits':{'address_space_bytes':2147483648,'cpu_seconds':300,'wall_seconds':330,'reserve_kib':3145728,'preflight_floor_kib':4194304,'preflight_seconds':30},'inputs':{str(p.relative_to(G)):hashlib.sha256(p.read_bytes()).hexdigest() for p in G.rglob('*') if p.is_file() and '.godot' not in p.parts and 'reports' not in p.parts}}
def save(): (R/(name+'-receipt.json')).write_text(json.dumps(r,indent=2))
t=time.monotonic()
while time.monotonic()-t<30:
 s=metrics()
 if s['oom']!=r['baseline']['oom'] or s['available_kib']<4194304:r['status']='PREFLIGHT_STOP';save();sys.exit(2)
 time.sleep(.25)
def limits():
 os.setsid();resource.setrlimit(resource.RLIMIT_AS,(2147483648,2147483648));resource.setrlimit(resource.RLIMIT_CPU,(300,300));resource.setrlimit(resource.RLIMIT_CORE,(0,0));resource.setrlimit(resource.RLIMIT_FSIZE,(16777216,16777216))
cmd=['xvfb-run','-a','-s','-screen 0 1280x720x24','/tmp/Godot_v4.6.3-stable_linux.x86_64','--resolution','640x360','--audio-driver','Dummy','--main-pack','/tmp/capture/index.pck','--rendering-method','gl_compatibility','--single-threaded-scene','--script','/tmp/capture/capture.gd']
out=open(R/(name+'-stdout.txt'),'w');err=open(R/(name+'-stderr.txt'),'w');t=time.monotonic()
p=subprocess.Popen(cmd,stdout=out,stderr=err,preexec_fn=limits,env={**os.environ,'HOME':str(R),'XDG_DATA_HOME':str(R/'userdata'),'XDG_CONFIG_HOME':str(R/'config'),'XDG_CACHE_HOME':str(R/'cache'),'GODOT_SILENCE_ROOT_WARNING':'1','LIBGL_ALWAYS_SOFTWARE':'1','LP_NUM_THREADS':'1','GALLIUM_DRIVER':'softpipe','MESA_GL_VERSION_OVERRIDE':'3.3'});r['pid']=p.pid;r['stop_reason']=None
try:
 while p.poll() is None:
  s=metrics();errors=(R/(name+'-stderr.txt')).read_text()
  if s['oom']!=r['baseline']['oom'] or s['available_kib']<3145728 or time.monotonic()-t>330 or any(x in errors for x in ['SCRIPT ERROR:','Parse Error:']):r['stop_reason']='resource_wall_or_script_error';os.killpg(p.pid,signal.SIGKILL);break
  time.sleep(.05)
finally:
 if p.poll() is None:os.killpg(p.pid,signal.SIGKILL)
 r['returncode']=p.wait()
 try:os.killpg(p.pid,signal.SIGKILL)
 except ProcessLookupError:pass
 r['wall_seconds']=time.monotonic()-t;r['after']=metrics()
 # Xvfb can leave a short-lived zombie after process-group kill. Distinguish
 # an unreaped zombie from a running leftover rather than accepting either.
 def group_members():
  members=[]
  for proc in pathlib.Path('/proc').iterdir():
   if not proc.name.isdigit():continue
   try:
    raw=(proc/'stat').read_text();fields=raw[raw.rfind(')')+2:].split()
    if int(fields[2])==p.pid:members.append({'pid':int(proc.name),'state':fields[0]})
   except (FileNotFoundError,ProcessLookupError,PermissionError,ValueError,IndexError):pass
  return members
 cleanup_deadline=time.monotonic()+2
 remaining=group_members()
 while remaining and time.monotonic()<cleanup_deadline:
  time.sleep(.05);remaining=group_members()
 r['remaining_process_group']=remaining
 r['process_group_gone']=not remaining
 r['live_process_group_gone']=not any(x['state'] not in ['Z','X'] for x in remaining)
 if not r['live_process_group_gone']:r['stop_reason']='live_process_group_cleanup_failed'
 out.close();err.close();r['status']='PROCESS_COMPLETED' if r['returncode']==0 and not r['stop_reason'] else 'PROCESS_FAILED';save()
print(json.dumps({k:v for k,v in r.items() if k!='inputs'}));sys.exit(0 if r['status']=='PROCESS_COMPLETED' else 1)
