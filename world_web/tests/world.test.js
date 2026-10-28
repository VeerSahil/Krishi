import test from 'node:test';
import assert from 'node:assert/strict';
import {multiply,perspective,lookAt,translation,project,inPolygon,regionPosition,transitionValue} from '../math3d.js';
import {CROP_ASSETS,cropGeometry,groundGeometry} from '../assets.js';
import {matchingFarms,newerSnapshot,canApprove,canRelease} from '../world-state.js';
import {parseEvents,consumeLive} from '../live-client.js';
import {sampleWorld,sampleReport} from '../sample-world.js';

test('projection centres the target and excludes points behind the camera',()=>{
 const camera=multiply(perspective(.7,1,.1,100),lookAt([0,10,10],[0,0,0]));
 const p=project([0,0,0],camera,800,800);assert.ok(Math.abs(p.x-400)<.01&&Math.abs(p.y-400)<.01);
 assert.equal(project([0,20,20],camera,800,800),null);
 const shifted=multiply(camera,translation(0,0,0));assert.deepEqual([...shifted],[...camera]);
});
test('plot selection uses its projected polygon',()=>{
 const square=[{x:10,y:10},{x:20,y:10},{x:20,y:20},{x:10,y:20}];
 assert.ok(inPolygon(15,15,square));assert.ok(!inPolygon(25,15,square));assert.ok(!inPolygon(15,15,[null,...square]));
});
test('regions remain independent and stable',()=>{
 const positions=Array.from({length:1000},(_,i)=>regionPosition(i+1));
 assert.equal(new Set(positions.map(p=>p.join(','))).size,1000);assert.deepEqual(regionPosition(7),[0,0,12]);
 for(let i=0;i<5;i++)assert.ok(positions[i+1][0]-positions[i][0]>11.6);
});
test('class transitions reach endpoints smoothly and reverse without a jump',()=>{
 assert.equal(transitionValue(.88,.04,0),.88);assert.ok(Math.abs(transitionValue(.88,.04,1500)-.04)<1e-9);
 const mid=transitionValue(.88,.04,750);assert.ok(Math.abs(mid-.46)<1e-9);
 assert.equal(transitionValue(mid,.88,0),mid);assert.ok(Math.abs(transitionValue(mid,.88,2000)-.88)<1e-9);
});
test('all six reusable crop meshes contain finite lit geometry and care vertices',()=>{
 const meshes=new Set();
 for(const asset of CROP_ASSETS){const values=cropGeometry(asset.id);assert.equal(values.length%30,0);assert.ok(values.length>10000);
 assert.ok([...values].every(Number.isFinite));assert.ok([...values].some((v,i)=>i%10===9&&v===1));
 assert.deepEqual(values,cropGeometry(asset.id));meshes.add(Buffer.from(values.buffer).toString('base64'));}
 assert.equal(meshes.size,6);assert.throws(()=>cropGeometry('unknown'));
 assert.ok([...groundGeometry(sampleWorld())].every(Number.isFinite));
});
test('directory filters by name, crop and class without changing source data',()=>{
 const farms=sampleWorld();const count=farms.length;
 assert.ok(matchingFarms(farms,'potato').length>0);assert.ok(matchingFarms(farms,'','C').every(f=>f.assessment.grade==='C'));
 assert.equal(matchingFarms(farms,'unfindable-name').length,0);assert.equal(farms.length,count);
});
test('stale snapshots cannot downgrade field versions; removed assignments disappear',()=>{
 const old=[{id:'a',version:4},{id:'b',version:2}];const next=newerSnapshot(old,[{id:'a',version:3}]);
 assert.equal(next.length,1);assert.equal(next[0].version,4);
 assert.equal(newerSnapshot(old,[{id:'a',version:5}])[0].version,5);
});
test('only admin can approve requests and prepare released reports',()=>{
 for(const role of['farmer','team']){assert.ok(!canApprove(role,{status:'pending'}));assert.ok(!canRelease(role,{status:'awaiting_review'}));}
 assert.ok(canApprove('admin',{status:'pending'}));assert.ok(canRelease('admin',{status:'awaiting_review'}));
 assert.ok(!canRelease('admin',{status:'completed'}));
});
test('SSE parser handles chunk boundaries, comments and CRLF',()=>{
 const first=parseEvents(': heartbeat\r\n\r\nevent: snapshot\r\ndata: {"farms":');assert.equal(first.events.length,0);
 const next=parseEvents(first.rest+'[]}\r\n\r\nevent: connected\ndata: {"mode":"live"}\n\n');
 assert.deepEqual(next.events.map(e=>e.event),['snapshot','connected']);assert.deepEqual(next.events[0].data.farms,[]);assert.equal(next.rest,'');
 assert.throws(()=>parseEvents('data: invalid\n\n'));
});
test('live fetch uses Bearer authorization, keeps token out of URL, and dispatches snapshots',async()=>{
 let request;const seen=[];const bytes=new TextEncoder().encode('event: snapshot\ndata: {"farms":[]}\n\n');
 const api={baseUrl:'https://example.invalid',session:{idToken:'private-test-token',expiresAt:Date.now()+100000},
 fetcher:async(url,options)=>{request={url,options};return new Response(new ReadableStream({start(c){c.enqueue(bytes);c.close();}}));}};
 await consumeLive(api,new AbortController().signal,event=>seen.push(event),400);
 assert.equal(request.url,'https://example.invalid/world/events?limit=400');assert.equal(request.options.headers.Authorization,'Bearer private-test-token');assert.equal(seen[0].event,'snapshot');
});
test('sample reports provide farmer-facing text in each language with no writes',()=>{
 for(const language of['en','hi','mr']){const report=sampleReport(sampleWorld()[0],language);assert.equal(report.language,language);assert.ok(report.summary.length>10);assert.ok(report.actions.length);}
});
