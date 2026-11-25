"""Exercise ordinary checkpoint on two exact public Godot exports. No save seeding."""
import base64, contextlib, hashlib, json, os, pathlib, shutil, socket
import subprocess, sys, tempfile, time, urllib.request

ROOT = 'https://penny323mo.github.io/valley-crown-play/builds/'
OLD, NEW = 'vc-9b7236f5e71c', 'vc-561fdd2865e3'
MANIFESTS = json.loads(pathlib.Path(__file__).with_name('pins.json').read_text())
OUT = pathlib.Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
proof = {'scope':'public Pages, disposable stock Chrome profile, ordinary manual slot', 'checks':[], 'pass':False}
def require(ok, message):
    if not ok: raise RuntimeError(message)
def until(fn, detail, limit=45):
    end = time.monotonic() + limit
    while time.monotonic() < end:
        val = fn()
        if val: return val
        time.sleep(.2)
    raise RuntimeError('Timed out: ' + detail)
def digest(data): return hashlib.sha256(data).hexdigest()
def pin_check(build):
    url = ROOT + build + '/'
    with urllib.request.urlopen(url+'WEB_EXPORT_MANIFEST.json', timeout=25) as r:
        raw = r.read()
    require(digest(raw) == MANIFESTS[build], f'{build}: unexpected manifest bytes')
    for name, expected in json.loads(raw)['files_sha256'].items():
        if not name.startswith('index.'): continue
        with urllib.request.urlopen(url+name, timeout=30) as r:
            require(digest(r.read()) == expected, f'{build}: wrong {name}')
def run(profile, log):
    chrome = shutil.which('google-chrome')
    driver = shutil.which('chromedriver') or os.path.join(os.getenv('CHROMEWEBDRIVER',''), 'chromedriver')
    require(chrome and pathlib.Path(driver).is_file(), 'Runner needs matching stock Chrome and ChromeDriver')
    with socket.socket() as s:
        s.bind(('127.0.0.1',0)); port=s.getsockname()[1]
    driver_proc = subprocess.Popen([driver, f'--port={port}', '--allowed-ips=127.0.0.1'], stdout=log, stderr=log)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def api(method, path, data=None):
        r=urllib.request.Request(f'http://127.0.0.1:{port}'+path,
            json.dumps(data).encode() if data is not None else None,
            {'Content-Type':'application/json'}, method=method)
        with opener.open(r, timeout=65) as result: return json.load(result)['value']
    prefix=''
    def call(method, path, data=None): return api(method, prefix+path, data)
    def js(code, async_=False): return call('POST','/execute/'+('async' if async_ else 'sync'), {'script':code,'args':[]})
    def cdp(cmd, **params): return call('POST','/goog/cdp/execute',{'cmd':cmd,'params':params})
    def snap():
        return js("""if(typeof valleyMenuSnapshot==='function')valleyMenuSnapshot();
        if(typeof valleySnapshot==='function')valleySnapshot();
        return {m:window.valleyMenuState||null,g:window.valleyState||null,url:location.href};""")
    def menu(page, exists=None):
        def current():
            m=snap()['m'] or {}
            return m if m.get('visible') and m.get('page')==page and (
                exists is None or m['match_exists']==exists) else None
        return until(current, 'menu '+page)
    def game(test, detail):
        def current():
            g=snap()['g'] or {}
            return g if g and test(g) else None
        return until(current, detail)
    def frames(n):
        js(f"const done=arguments[arguments.length-1];let n={n};const step=()=>--n?requestAnimationFrame(step):done(true);requestAnimationFrame(step);", True)
    def click(rect):
        x,y,w,h=rect
        require(w>=24 and h>=24 and 0<=x+w/2<896 and 0<=y+h/2<540,'Invalid touch rectangle')
        cdp('Input.dispatchTouchEvent',type='touchStart',touchPoints=[{'x':x+w/2,'y':y+h/2,'id':1}])
        frames(2)
        cdp('Input.dispatchTouchEvent',type='touchEnd',touchPoints=[])
        frames(4)
    def item(items, field, label):
        visible = [x for x in items if x[field]==label and min(x['rect'][2:])>=24 and not x.get('disabled')]
        return visible[0] if len(visible)==1 else None
    def menu_click(page, identity):
        i=until(lambda:item(menu(page)['buttons'],'id',identity), identity)
        click(i['rect']); proof['checks'].append(f'tapped {page}/{identity}')
    def hud_click(label):
        def button():
            g=snap()['g'] or {}
            return item((g.get('hud') or {}).get('buttons',[]),'text',label)
        click(until(button,label)['rect'])
    def image(name):
        data=base64.b64decode(call('GET','/screenshot'))
        require(data[:8]==b'\x89PNG\r\n\x1a\n','Screenshot not PNG')
        (OUT/(name+'.png')).write_bytes(data)
        proof.setdefault('images',{})[name]=digest(data)
    def file_state():
        return js("""const done=arguments[arguments.length-1];
          (async()=>{for(const entry of await indexedDB.databases()){
            if(entry.name!='/userfs')continue;
            const db=await new Promise((resolve,reject)=>{const r=indexedDB.open(entry.name);
              r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
            try{
              if(!db.objectStoreNames.contains('FILE_DATA'))continue;
              const tx=db.transaction('FILE_DATA','readonly');
              const match=await new Promise((resolve,reject)=>{const r=tx.objectStore('FILE_DATA').openCursor();
                r.onerror=()=>reject(r.error);r.onsuccess=()=>{const c=r.result;
                  if(!c)return resolve(null);
                  if(String(c.key).endsWith('/battle_checkpoint_v1.bin'))return resolve(c.value.contents);
                  c.continue();};});
              if(match){const h=await crypto.subtle.digest('SHA-256',match);
                return {bytes:match.byteLength,sha256:Array.from(new Uint8Array(h),n=>n.toString(16).padStart(2,'0')).join('')};}
            }finally{db.close();}
          }return null;})().then(done,e=>done({error:String(e)}));""", True)
    def saved():
        f=file_state()
        require(not f or not f.get('error'),f'IndexedDB read failed: {f}')
        return f
    def open_game(build):
        handle=call('POST','/window/new',{'type':'tab'})['handle']
        call('POST','/window',{'handle':handle})
        url=ROOT+build+'/?qa=1'
        call('POST','/url',{'url':url})
        menu('home',False)
        require(snap()['url']==url,'Not the expected exact public build URL')
    def close_game():
        require(call('DELETE','/window')==[anchor],'Unexpected concurrent game tab')
        call('POST','/window',{'handle':anchor})
    sig_keys=('build','tick','bank_milli','population','capacity','trained','built','delivered')
    def signature(g): return {x:g[x] for x in sig_keys}
    try:
        def ready():
            require(driver_proc.poll() is None,'ChromeDriver exited')
            try: return api('GET','/status')['ready']
            except OSError: return False
        until(ready,'ChromeDriver',15)
        caps={'browserName':'chrome','pageLoadStrategy':'eager',
            'goog:chromeOptions':{'binary':chrome,'args':['--headless','--disable-background-networking',
            '--no-first-run',f'--user-data-dir={profile}','--use-gl=angle','--use-angle=swiftshader'],
            'mobileEmulation':{'deviceMetrics':{'width':896,'height':540,'pixelRatio':1,'mobile':True,'touch':True}}}}
        s=api('POST','/session',{'capabilities':{'alwaysMatch':caps}})
        prefix='/session/'+s['sessionId']; proof['browser']=s['capabilities']['browserVersion']
        args=cdp('Browser.getBrowserCommandLine')['arguments']
        bad={'--no-sandbox','--disable-setuid-sandbox','--disable-gpu-sandbox','--enable-unsafe-swiftshader','--single-process'}
        require(not bad.intersection(x.split('=',1)[0] for x in args),'Browser sandbox flags changed')
        anchor=call('GET','/window')
        proof['phase']='Recon: create genuine save and wait for IndexedDB'
        open_game(OLD); require(saved() is None,'Disposable profile already has a manual checkpoint')
        menu_click('home','StartMatchButton')
        menu_click('battle_groups','BattleGroup0')
        menu_click('battle_options','ChooseBattle_practice')
        menu_click('setup','LaunchMatchButton')
        game(lambda g:g['build']==OLD and not g['paused'] and g['tick']>=60,'run ordinary Recon Practice')
        hud_click('選單')
        hud_click('設定')
        hud_click('主選單')
        menu('home',True)
        original=signature(game(lambda g:g['build']==OLD and g['paused'],'ordinary paused game'))
        menu_click('home','CheckpointMenuButton')
        menu_click('checkpoint','SaveCheckpointButton')
        file=until(saved,'manual checkpoint commits in IndexedDB')
        require(file['bytes']>0,'Empty saved file')
        proof['saved']=file; proof['state']=original
        image('01-recon-saved');close_game()
        def old_restore(name):
            open_game(OLD); require(saved()==file,'Reopened Recon storage differs')
            menu_click('home','CheckpointMenuButton'); menu_click('checkpoint','LoadCheckpointButton')
            menu('home',True)
            g=game(lambda g:g['build']==OLD and g['paused'],'restored Recon paused')
            require(signature(g)==original,'Restored authoritative signature differs')
            image(name)
        proof['phase']='Recon: validate cold-tab durable restore'
        old_restore('02-recon-cold-restore');close_game()
        proof['phase']='Quiet: incompatible load, no write'
        open_game(NEW); require(saved()==file,'Quiet origin cannot see original save')
        menu_click('home','CheckpointMenuButton'); menu_click('checkpoint','LoadCheckpointButton')
        js("const done=arguments[arguments.length-1];let n=12;const step=()=>--n?requestAnimationFrame(step):done(true);requestAnimationFrame(step);",True)
        menu('checkpoint',False)
        require(not snap()['g'] and saved()==file,'Quiet restored or mutated incompatible save')
        image('03-quiet-rejected-load');close_game()
        proof['phase']='Recon: recover unchanged paused state after Quiet'
        old_restore('04-recon-recovered')
        menu_click('home','ResumeMatchButton')
        game(lambda g:g['build']==OLD and not g['paused'] and g['tick']>original['tick'],'clock after resume')
        image('05-recon-resumed');close_game()
        proof['pass']=True
    except Exception:
        if prefix:
            with contextlib.suppress(Exception): proof['last_snapshot']=snap()
            with contextlib.suppress(Exception): image('failure-last-frame')
            with contextlib.suppress(Exception): proof['console']=call('POST','/log',{'type':'browser'})[-15:]
        raise
    finally:
        if prefix:
            with contextlib.suppress(Exception): call('DELETE','')
        driver_proc.terminate()
        try: driver_proc.wait(5)
        except subprocess.TimeoutExpired: driver_proc.kill();driver_proc.wait()
try:
    proof['phase']='Pins'
    for b in (OLD,NEW): pin_check(b)
    with tempfile.TemporaryDirectory(prefix='vc-checkpoint-chrome-') as p:
        with (OUT/'driver.log').open('wb') as log: run(p,log)
finally:
    (OUT/'proof.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(proof,ensure_ascii=False),flush=True)
