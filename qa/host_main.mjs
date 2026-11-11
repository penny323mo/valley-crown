// Ordinary nonroot host Chrome in exact transient service. No code runs on import
// by tests; supervisor explicitly executes this entrypoint only after review.
import http from 'node:http';
import path from 'node:path';
import {readFile, lstat, realpath, writeFile, appendFile} from 'node:fs/promises';
import {appendFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {runQA} from './browser_qa.mjs';
import {createServerDiagnostics} from './server_diagnostics.mjs';
const [exportRoot, output, deps, chromePath, profile] = process.argv.slice(2);
if (!exportRoot || !output || !deps || chromePath !== '/opt/google/chrome/chrome' || !['desktop','portrait'].includes(profile)) throw new Error('Required explicit paths/profile missing');
const require = createRequire(path.join(deps, 'package.json'));
const {chromium} = require('playwright');
const start = Date.now();
let admitted;
while (!admitted && Date.now()-start < 15000) {
  try {admitted = JSON.parse(await readFile(path.join(output, 'admitted.json'), 'utf8'));}
  catch {await new Promise(resolve => setTimeout(resolve, 100));}
}
if (!admitted || admitted.remaining_seconds < 1) throw new Error('Host admission missing');
const timer = setTimeout(() => process.exit(124), Math.min(90000, admitted.remaining_seconds*1000));
let serverPhase='server-starting';
const serverDiagnostics=createServerDiagnostics(line => appendFileSync(path.join(output,'server-requests.log'),line),() => serverPhase);
const mime = {'.html':'text/html', '.js':'text/javascript', '.wasm':'application/wasm', '.pck':'application/octet-stream', '.png':'image/png', '.svg':'image/svg+xml', '.json':'application/json'};
const server = http.createServer(async (req, res) => {
  const trace=serverDiagnostics.attach(req,res);
  try {
    if (!['GET','HEAD'].includes(req.method)) {res.writeHead(405); res.end(); return;}
    const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (name.includes('\0') || name.includes('\\') || name.split('/').includes('..')) throw new Error('Unsafe path');
    const target = path.resolve(exportRoot, '.' + (name === '/' ? '/index.html' : name));
    if (!target.startsWith(exportRoot + '/') || (await realpath(target)) !== target || !(await lstat(target)).isFile()) throw new Error('Unsafe target');
    res.writeHead(200, {'Content-Type':mime[path.extname(target)] || 'application/octet-stream', 'Cache-Control':'no-store',
      'Cross-Origin-Opener-Policy':'same-origin', 'Cross-Origin-Embedder-Policy':'require-corp', 'X-Content-Type-Options':'nosniff'});
    const body=req.method === 'HEAD' ? undefined : await readFile(target);
    trace.setBodyBytes(body?.length ?? 0);
    res.end(body);
  } catch {trace.setBodyBytes(9); res.writeHead(404); res.end('Not found');}
});
await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  serverPhase='browser-launch';
  browser = await chromium.launch({executablePath:chromePath, headless:true, chromiumSandbox:true, timeout:20000});
  await writeFile(path.join(output, 'browser-runtime.json'), JSON.stringify({origin, browserVersion:browser.version(), executablePath:chromePath,
    browserSource:'stock official host Chrome; observed version, not a pinned Playwright browser', chromiumSandbox:true, profile}, null, 2));
  serverPhase='construction-scenario';
  await runQA(browser, output, origin, profile);
  if (serverDiagnostics.state.failed) throw new Error(serverDiagnostics.state.reason);
} catch (error) {
  await appendFile(path.join(output, 'host-browser-error.log'), String(error).slice(0, 12000) + '\n');
  throw error;
} finally {
  serverPhase='closing';
  if (browser) await browser.close();
  await new Promise((resolve,reject) => server.close(error => error ? reject(error) : resolve()));
  clearTimeout(timer);
  if (serverDiagnostics.state.failed) throw new Error(serverDiagnostics.state.reason);
}
