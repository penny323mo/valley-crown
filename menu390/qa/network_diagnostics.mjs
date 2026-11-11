// Passive, bounded metadata only. Never reads request/response bodies or secrets.
export const MAX_REQUESTS = 128;
const HEADERS = ['content-type','content-length','content-encoding','content-range','cache-control',
  'cross-origin-opener-policy','cross-origin-embedder-policy','x-rts-request-id'];
const text = (value, limit=512) => String(value ?? '').slice(0,limit);
function safeUrl(value) {
  try {const u=new URL(value); return text(u.origin+u.pathname);}
  catch {return '[invalid URL]';}
}

export function createNetworkDiagnostics(phase, onError, now=Date.now) {
  const started=now(), ids=new WeakMap();
  const data={limit:MAX_REQUESTS, total_requests:0, overflow:false, records:[]};
  const stamp=() => ({elapsed_ms:now()-started,phase:text(phase(),96)});
  const identify=request => {
    if (ids.has(request)) return ids.get(request);
    data.total_requests++;
    if (data.records.length >= MAX_REQUESTS) {
      ids.set(request,null);
      if (!data.overflow) {data.overflow=true; onError({kind:'request-log-overflow',text:'More than128 requests; diagnostic budget exceeded'});}
      return null;
    }
    const record={id:'r'+String(data.total_requests).padStart(4,'0'),url:safeUrl(request.url()),
      method:text(request.method(),16),resource_type:text(request.resourceType(),32),started:stamp()};
    ids.set(request,record); data.records.push(record); return record;
  };
  return {data,
    request:request => {identify(request);},
    response:response => {
      const record=identify(response.request()); if (!record) return;
      const headers=response.headers();
      record.response={...stamp(),status:response.status(),headers:Object.fromEntries(
        HEADERS.filter(name => headers[name] !== undefined).map(name => [name,text(headers[name],256)]))};
      if (response.status() >= 400) onError({kind:'http-error',request_id:record.id,status:response.status(),url:record.url});
    },
    finished:request => {const record=identify(request); if (record) record.finished=stamp();},
    failed:request => {
      const record=identify(request), failure=text(request.failure()?.errorText,512);
      if (record) record.failed={...stamp(),error:failure};
      // No abort whitelist, including context shutdown and late startup failures.
      onError({kind:'requestfailed',request_id:record?.id ?? '[over-budget]',text:failure});
    },
  };
}
