// Smoke-test an exported Bloom build in headless Chromium (phone-sized viewport).
//   node play.js <site-dir> '[[x, y, waitMs, "shot.png"], ...]'
// Waits for the engine to start, screenshots the first frame, replays the taps,
// and prints any console errors.
const http=require('http'),fs=require('fs'),path=require('path');
const puppeteer=require('puppeteer-core');const chromium=require('@sparticuz/chromium').default;
const dir=path.resolve(process.argv[2]);
const T={'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm'};
const srv=http.createServer((q,r)=>{let p=q.url.split('?')[0];if(p.endsWith('/'))p+='index.html';const f=path.join(dir,p);
 if(!fs.existsSync(f)){r.writeHead(404);return r.end()}r.writeHead(200,{'Content-Type':T[path.extname(f)]||'application/octet-stream'});r.end(fs.readFileSync(f))}).listen(0);
(async()=>{const b=await puppeteer.launch({executablePath:await chromium.executablePath(),args:[...chromium.args,'--use-angle=swiftshader','--enable-unsafe-swiftshader'],headless:true});
const p=await b.newPage();await p.setViewport({width:400,height:800});const errs=[];
p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});p.on('pageerror',e=>errs.push(String(e)));
await p.goto(`http://127.0.0.1:${srv.address().port}/`);await p.waitForFunction(()=>!document.getElementById('status'),{timeout:60000});
const w=ms=>new Promise(r=>setTimeout(r,ms));await w(1500);await p.screenshot({path:process.env.SHOT||'first-frame.png'});
for(const [x,y,ms,shot] of JSON.parse(process.argv[3])){await p.mouse.click(x,y);await w(ms||400);if(shot)await p.screenshot({path:shot});}
console.log('errors:',errs.length?errs.slice(0,5):'none');await b.close();srv.close()})();
