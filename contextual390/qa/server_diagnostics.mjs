// Metadata only, bounded synchronous lines preserve evidence on abrupt deadlines.
// Queued body bytes are NOT proof that Chrome received or consumed those bytes.
export function createServerDiagnostics(writeLine, phase, now=Date.now) {
  let count=0, lines=0;
  const started=now(), state={failed:false,reason:null};
  const fail=reason => {state.failed=true; state.reason=String(reason).slice(0,256);};
  const emit=record => {
    if (lines >= 513) {fail('Server diagnostic line budget exceeded'); return;}
    lines++;
    try {writeLine(JSON.stringify({...record,elapsed_ms:now()-started,phase:String(phase()).slice(0,96)})+'\n');}
    catch {fail('Server diagnostic write failed');}
  };
  return {state, attach(req,res) {
    count++;
    if (count > 128) {
      if (count === 129) emit({event:'overflow',limit:128});
      fail('Server request diagnostic budget exceeded');
      return {setBodyBytes:() => {}};
    }
    const id='s'+String(count).padStart(4,'0');
    let pathname='[invalid URL]';
    try {pathname=new URL(req.url,'http://localhost').pathname.slice(0,512);} catch {}
    let bodyBytes=0;
    const common=() => ({id,method:String(req.method).slice(0,16),path:pathname,status:res.statusCode,
      body_bytes_queued:bodyBytes,writable_finished:res.writableFinished===true});
    res.setHeader('X-RTS-Request-ID',id);
    emit({...common(),event:'request'});
    req.once('aborted',() => {fail('Server request aborted: '+id); emit({...common(),event:'request-aborted'});});
    res.once('finish',() => emit({...common(),event:'response-finish'}));
    res.once('close',() => {
      if (!res.writableFinished) fail('Server response closed before finish: '+id);
      emit({...common(),event:res.writableFinished?'response-close':'response-premature-close'});
    });
    return {setBodyBytes:bytes => {bodyBytes=Number.isSafeInteger(bytes)&&bytes>=0?bytes:0;}};
  }};
}
