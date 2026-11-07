#!/usr/bin/env python3
"""Bounded, closed-schema log diagnostics only. Never admits or uploads evidence."""
from pathlib import Path
import argparse, json, math, os, stat

PREFIX=b'NATIVE_TOUCH_PROGRESS '
MAX_LOG_BYTES=4*1024*1024
MAX_RECORDS=64
LABELS=('opening','worker-selected','target-guidance','command-mode','woodcutting','deposit-complete',
        'build-preview','build-confirmed','construction-active','house-complete','gather-order-accepted','wood-cargo','cargo-return','gather-resumed',
        'build-action-preview','construction-quarter','construction-half','construction-near-complete','house-complete-settled')
WAIT_STAGES=('wood','cargo','return','resumed','deposit','site','construction','quarter','half','near-complete','complete')
STATES=('missing','idle','move','gather','deliver','build','repair','return','attack')
CLIPS=('missing','idle','walk','carry_walk','gather_wood','gather_food','build','repair','attack','hit','death')
KEYS={'sequence','stage','phase','process_frame','tick','monotonic_msec','waited_frames','saved_frames',
      'worker_state','clip','carry','path_points','delivered','site_present','site_built','site_progress'}

class InvalidProgress(Exception):pass

def need(ok):
    if not ok:raise InvalidProgress()

def number(value,maximum):
    return type(value) in (int,float) and math.isfinite(value) and 0<=value<=maximum

def integer(value,maximum):return type(value) is int and 0<=value<=maximum

def no_duplicates(items):
    result={}
    for key,value in items:
        need(key not in result);result[key]=value
    return result

def validate(row,sequence,previous):
    need(type(row) is dict and set(row)==KEYS and row['sequence']==sequence and type(row['sequence']) is int)
    stage,phase=row['stage'],row['phase']
    need((stage=='startup' and phase in ('entered','scene-added')) or
         (stage in LABELS and phase in ('capture-start','capture-saved')) or
         (stage in WAIT_STAGES and phase in ('wait-start','wait-pulse')))
    for key,maximum in [('process_frame',100000),('tick',100000),('monotonic_msec',240000),
                        ('waited_frames',2700),('saved_frames',10),('path_points',10000)]:
        need(integer(row[key],maximum))
    need(row['worker_state'] in STATES and row['clip'] in CLIPS and number(row['carry'],1000) and
         number(row['delivered'],1000000) and number(row['site_progress'],1) and
         type(row['site_present']) is bool and type(row['site_built']) is bool)
    need((phase=='wait-pulse' and row['waited_frames']>0 and row['waited_frames']%300==0) or
         (phase!='wait-pulse' and row['waited_frames']==0))
    if previous:
        need(all(row[key]>=previous[key] for key in ('process_frame','tick','monotonic_msec','saved_frames','delivered')))
    return row

def summarize(data):
    need(type(data) is bytes and len(data)<=MAX_LOG_BYTES)
    rows=[]
    for line in data.splitlines():
        if not line.startswith(PREFIX):continue
        need(len(line)<=2048 and len(rows)<MAX_RECORDS)
        row=json.loads(line[len(PREFIX):].decode('utf-8'),object_pairs_hook=no_duplicates)
        rows.append(validate(row,len(rows),rows[-1] if rows else None))
    return {'diagnostic_status':'progress_retained' if rows else 'no_progress_records',
            'capture_acceptance':False,'record_count':len(rows),'progress_tail':rows[-8:],
            'reported_saved_labels':[r['stage'] for r in rows if r['phase']=='capture-saved'],
            'meaning':'Source-authored progress only; not screenshot, gameplay, or performance acceptance'}

def read_log(path):
    path=Path(path)
    need(not any(parent.is_symlink() for parent in (path,*path.parents)))
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        info=os.fstat(fd);need(stat.S_ISREG(info.st_mode) and info.st_size<=MAX_LOG_BYTES)
        with os.fdopen(fd,'rb',closefd=False) as stream:data=stream.read(MAX_LOG_BYTES+1)
        need(len(data)<=MAX_LOG_BYTES);return data
    finally:os.close(fd)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--log',type=Path,required=True);args=parser.parse_args()
    try:result=summarize(read_log(args.log))
    except FileNotFoundError:result={'diagnostic_status':'log_absent','capture_acceptance':False}
    except Exception:result={'diagnostic_status':'diagnostic_rejected','capture_acceptance':False}
    # No raw line, exception, arbitrary name, environment, file content or PNG is emitted.
    print('TOUCH_PROGRESS_RESULT '+json.dumps(result,sort_keys=True,separators=(',',':')))
    return 0  # Diagnostic status never overrides the preceding capture step's result.

if __name__=='__main__':raise SystemExit(main())
