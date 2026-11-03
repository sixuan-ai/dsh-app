const {spawn}=require('node:child_process');const fs=require('node:fs');const os=require('node:os');const path=require('node:path');const http=require('node:http');const crypto=require('node:crypto');const assert=require('node:assert/strict');
(async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'xharness-auth-test-'));const store=path.join(dir,'users.json');const salt=crypto.randomBytes(16).toString('hex');
 const entry={username:'enrolled-test',salt,digest:crypto.pbkdf2Sync('new-test-pass',Buffer.from(salt,'hex'),210000,32,'sha256').toString('hex'),iterations:210000,algorithm:'pbkdf2-sha256'};
 const save=x=>fs.writeFileSync(store,JSON.stringify(x));save({version:1,users:[entry]});
 const upstream=http.createServer((req,res)=>{res.writeHead(200);res.end('upstream-ok')});await new Promise(r=>upstream.listen(0,'127.0.0.1',r));const up=upstream.address().port;
 const reserve=http.createServer();await new Promise(r=>reserve.listen(0,'127.0.0.1',r));const port=reserve.address().port;await new Promise(r=>reserve.close(r));
 const env={...process.env,LISTEN_HOST:'127.0.0.1',LISTEN_PORT:String(port),UPSTREAM_PORT:String(up),AUTH_USER:'legacy-test',AUTH_PASSWORD:'legacy-test-pass',AUTH_COOKIE_SECRET:crypto.randomBytes(32).toString('hex'),AUTH_USERS_FILE:store,DSH_TOKEN_FILE:''};
 const child=spawn(process.execPath,[path.resolve(__dirname,'../dsh-auth-proxy.js')],{env,stdio:'ignore'});let count=0;
 const auth=(u,p)=>'Basic '+Buffer.from(u+':'+p).toString('base64');
 const query=(url='/',headers={},method='GET',body='')=>new Promise((resolve,reject)=>{let q=http.request({host:'127.0.0.1',port,path:url,headers,method},r=>{r.resume();r.on('end',()=>resolve({status:r.statusCode,cookie:r.headers['set-cookie']}))});q.on('error',reject);q.end(body)});
 const check=async(name,expected,fn)=>{assert.equal((await fn()).status,expected,name);count++;console.log('PASS',name)};
 try{
  for(let i=0;i<50;i++){try{await query();break}catch{await new Promise(r=>setTimeout(r,50))}}
  await check('missing auth denied',401,()=>query());
  await check('legacy account retained',200,()=>query('/',{Authorization:auth('legacy-test','legacy-test-pass')}));
  await check('enrolled account accepted',200,()=>query('/',{Authorization:auth('enrolled-test','new-test-pass')}));
  await check('incorrect enrolled password denied',401,()=>query('/',{Authorization:auth('enrolled-test','bad-pass')}));
  await check('unknown account denied',401,()=>query('/',{Authorization:auth('unknown','new-test-pass')}));
  const response=await query('/__auth',{'Content-Type':'application/x-www-form-urlencoded'},'POST','user=enrolled-test&password=new-test-pass&next=%2F');assert.equal(response.status,302);count++;
  const cookie=response.cookie[0].split(';')[0];await check('enrolled login cookie works',200,()=>query('/',{Cookie:cookie}));
  save({version:1,users:[{...entry,digest:'not-hex'}]});await check('corrupt digest denied',401,()=>query('/',{Authorization:auth('enrolled-test','new-test-pass')}));
  save({version:1,users:[{...entry,iterations:999999999}]});await check('unbounded hash work denied',401,()=>query('/',{Authorization:auth('enrolled-test','new-test-pass')}));
  fs.writeFileSync(store,'not JSON');await check('broken store denied',401,()=>query('/',{Authorization:auth('enrolled-test','new-test-pass')}));
  await check('legacy survives broken extra store',200,()=>query('/',{Authorization:auth('legacy-test','legacy-test-pass')}));
  fs.rmSync(store);await check('missing store denies extra account',401,()=>query('/',{Authorization:auth('enrolled-test','new-test-pass')}));
  console.log('AUTH_TESTS_PASSED',count);
 }finally{child.kill('SIGTERM');upstream.close();fs.rmSync(dir,{recursive:true,force:true})}
})().catch(e=>{console.error(e.message);process.exitCode=1});
