"""Linux x86_64 fail-closed ptrace startup gate; never used after startup.
Only official Godot -> dash -c exact xdg command -> xdg-user-dir DESKTOP.
Detach only at successful parent wait4 reap after every helper has exited.
"""
import ctypes, errno, hashlib, os, signal, stat, time
from pathlib import Path
TRACEME=0; PEEK=2; CONT=7; GETREGS=12; SYSCALL=24; DETACH=17; SETOPTIONS=0x4200
OPTIONS=1|2|4|8|16|64|0x100000 # syscall tags, fork/vfork/clone/exec/exit, exitkill
libc=ctypes.CDLL(None,use_errno=True)
libc.ptrace.restype=ctypes.c_long
class Regs(ctypes.Structure):
 _fields_=[(n,ctypes.c_ulonglong) for n in 'r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs'.split()]
def ptrace(req,pid,addr=0,data=0):
 r=libc.ptrace(req,pid,ctypes.c_void_p(addr),data if not isinstance(data,int) else ctypes.c_void_p(data))
 if r==-1: raise OSError(ctypes.get_errno(),os.strerror(ctypes.get_errno()))
 return r
def trace_me():
 ptrace(TRACEME,0)
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def binary(path):
 p=Path(path).resolve(strict=True);s=p.stat()
 if not stat.S_ISREG(s.st_mode) or s.st_uid!=0 or s.st_mode&0o022: raise RuntimeError('Untrusted startup helper')
 return str(p),digest(p)
def inspect(pid):
 p=Path('/proc')/str(pid)
 a=(p/'cmdline').read_bytes()
 if not a or len(a)>8192: raise RuntimeError('Incomplete startup argv')
 return str(Path(os.readlink(p/'exe')).resolve()),a.rstrip(b'\0').decode('utf-8').split('\0')
def validate_exec(role,exe,args,engine,dash):
 if role=='engine': return exe==engine and args[0]==engine
 if role=='shell': return exe==dash and args==['sh','-c','--','"xdg-user-dir" "DESKTOP" 2>/dev/null']
 if role=='xdg': return exe==dash and args==['/bin/sh','/usr/bin/xdg-user-dir','DESKTOP']
 return False

def gate(child,engine,receipt,timeout=3.0,resource_check=None):
 """Returns only with original direct child running and all helpers reaped.
 Any failure kills owned tracees via pidfd, reaps them, then raises.
 """
 report={'passed':False,'events':[],'helpers':{}}
 receipt['startup_identity']=report
 roles={child.pid:'engine'};fds={};dead=set();pending=set();unbound=set();root_helper=None;xdg_pid=None;start=time.monotonic();sysentry=True
 def log(event,pid,**kw):
  report['events'].append({'event':event,'pid':pid,**kw})
  if len(report['events'])>32:raise RuntimeError('Startup event bound')
 last_check=-1.0
 def wait_one():
  nonlocal last_check
  while time.monotonic()-start<timeout:
   now=time.monotonic()
   if resource_check is not None and now-last_check>=0.025:
    resource_check(tuple(pid for pid in fds if pid not in dead));last_check=now
   pid,status=os.waitpid(-1,os.WNOHANG|0x40000000)
   if pid:return pid,status
   time.sleep(.0005)
  raise RuntimeError('Startup identity timeout')
 try:
  fds[child.pid]=os.pidfd_open(child.pid)
  if os.uname().machine!='x86_64':raise RuntimeError('Startup tracing requires x86_64')
  engine=str(Path(engine).resolve(strict=True));dash,dh=binary('/bin/sh');xdg,xh=binary('/usr/bin/xdg-user-dir')
  if dash!='/usr/bin/dash' or xdg!='/usr/bin/xdg-user-dir':raise RuntimeError('Unexpected helper path')
  report['helpers']={'dash_sha256':dh,'xdg_sha256':xh}
  if dh!='86d31f6fb799e91fa21bad341484564510ca287703a16e9e46c53338776f4f42' or xh!='66f6896a88c333b2c3152617fd3be51d7e896481abc07028a064dad17e64f6b8':raise RuntimeError('Startup helper digest mismatch')
  pid,status=wait_one()
  if pid!=child.pid or not os.WIFSTOPPED(status) or os.WSTOPSIG(status)!=signal.SIGTRAP:raise RuntimeError('Missing initial exec stop')
  ex,args=inspect(pid)
  if not validate_exec('engine',ex,args,engine,dash):raise RuntimeError('Wrong engine identity')
  ptrace(SETOPTIONS,pid,0,OPTIONS);ptrace(SYSCALL,pid)
  while True:
   pid,status=wait_one()
   if pid not in roles:
    # Linux may deliver the child's initial stop before the parent's fork event.
    # Quarantine it: never resume before kernel parent event binds its role.
    if os.WIFSTOPPED(status) and os.WSTOPSIG(status)==signal.SIGSTOP and not unbound:
     fds[pid]=os.pidfd_open(pid);unbound.add(pid);log('quarantined_initial_stop',pid);continue
    raise RuntimeError('Unowned traced process')
   role=roles[pid]
   if os.WIFEXITED(status):
    code=os.WEXITSTATUS(status);log('exited',pid,code=code)
    if role=='engine' or code!=0:raise RuntimeError('Unexpected startup exit')
    dead.add(pid);continue
   if os.WIFSIGNALED(status):raise RuntimeError('Startup tracee killed')
   if not os.WIFSTOPPED(status):raise RuntimeError('Unknown trace status')
   sig=os.WSTOPSIG(status);event=status>>16
   if event in (1,2,3):
    n=ctypes.c_ulonglong();ptrace(0x4201,pid,0,ctypes.byref(n));new=n.value
    if new not in fds:fds[new]=os.pidfd_open(new)
    if event==3:raise RuntimeError('Thread before startup barrier')
    if role=='engine' and root_helper is None: newrole='shell';root_helper=new
    elif role=='shell' and xdg_pid is None:newrole='xdg';xdg_pid=new
    else:raise RuntimeError('Unexpected startup descendant')
    roles[new]=newrole
    if new in unbound:
     unbound.remove(new);ptrace(CONT,new)
    else:pending.add(new)
    log('fork',pid,child=new,role=newrole)
   elif event==4:
    ex,args=inspect(pid)
    if role=='engine' or not validate_exec(role,ex,args,engine,dash):raise RuntimeError('Unexpected startup executable or argv')
    if digest(dash)!=dh or digest(xdg)!=xh:raise RuntimeError('Helper changed')
    log('exec',pid,role=role,executable=ex,argv=args)
   elif event==6: pass
   elif sig==signal.SIGSTOP and pid in pending:pending.remove(pid)
   elif sig==(signal.SIGTRAP|0x80) and role=='engine':
    regs=Regs();ptrace(GETREGS,pid,0,ctypes.byref(regs))
    if not sysentry and regs.orig_rax==61 and regs.rax==root_helper:
     if root_helper not in dead or xdg_pid not in dead or len(roles)!=3 or unbound:raise RuntimeError('Startup descendants not fully reaped')
     if len([x for x in report['events'] if x['event']=='exec'])!=2:raise RuntimeError('Startup executable chain incomplete')
     if digest(dash)!=dh or digest(xdg)!=xh:raise RuntimeError('Helper binding changed')
     ptrace(DETACH,child.pid);report['passed']=True;report['seconds']=round(time.monotonic()-start,4);return
    sysentry=not sysentry
   elif sig==signal.SIGCHLD: pass
   else:raise RuntimeError('Unexpected startup signal')
   ptrace(SYSCALL if role=='engine' else CONT,pid,0,signal.SIGCHLD if sig==signal.SIGCHLD else 0)
 except BaseException as exc:
  report['error']=type(exc).__name__+': '+str(exc)
  for pid,fd in fds.items():
   if pid not in dead:
    try:signal.pidfd_send_signal(fd,signal.SIGKILL)
    except ProcessLookupError:pass
  end=time.monotonic()+2
  while time.monotonic()<end:
   try:
    pid,status=os.waitpid(-1,os.WNOHANG|0x40000000)
    if not pid:time.sleep(.001);continue
    if os.WIFSTOPPED(status):ptrace(CONT,pid,0,signal.SIGKILL)
    elif os.WIFEXITED(status) or os.WIFSIGNALED(status):dead.add(pid)
   except ChildProcessError:break
  report['cleanup_complete']=child.pid in dead and all(p in dead for p in fds)
  if child.pid in dead:child.returncode=-signal.SIGKILL
  raise
 finally:
  for fd in fds.values():os.close(fd)
