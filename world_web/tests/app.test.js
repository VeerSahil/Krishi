import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {CROP_ASSETS} from '../assets.js';
import * as worldState from '../world-state.js';
import {sampleWorld,sampleVisit,sampleReport} from '../sample-world.js';

async function workspace(){
 const elements=new Map(),classes=[];
 class Element{
  constructor(tag='div'){this.tagName=tag;this.children=[];this.events={};this.value='';this.hidden=false;this.disabled=false;this.open=false;this.dataset={};this.className='';this.isConnected=true;this.textContent='';this.classList={toggle(){}};}
  set id(value){this._id=value;elements.set(value,this);}get id(){return this._id;}
  append(...children){this.children.push(...children);}replaceChildren(...children){this.children=children;this.textContent='';}
  addEventListener(event,callback){this.events[event]=callback;}setAttribute(key,value){this[key]=value;}
  showModal(){this.open=true;}close(){this.open=false;}reportValidity(){return true;}reset(){}
  async fire(name='click'){await this.events[name]?.({preventDefault(){}});await flush();}
 }
 const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
 for(const[,id]of html.matchAll(/id="([^"]+)"/g)){const e=new Element();e.id=id;}
 for(const grade of['all','A','B','C','U']){const el=new Element('button');el.dataset.class=grade;classes.push(el);}
 const document={querySelector:selector=>selector.startsWith('#')?elements.get(selector.slice(1)):null,
 querySelectorAll:()=>classes,createElement:tag=>new Element(tag),hidden:false};
 class Api{
  constructor(){this.calls=[];this.baseUrl='';this.config={configured:true};this.session=null;}
  async loadConfig(){return this.config;}signOut(){this.session=null;}
  async signIn(){this.session={idToken:'test'};return{role:'admin',name:'Admin'};}
  async request(path,options={}){this.calls.push({path,...options});
   if(path.startsWith('/world/farms?'))return{farms:sampleWorld(),nextCursor:null};
   if(path.startsWith('/world/farms/')){const farm=sampleWorld()[0];return{farm,survey:sampleVisit(farm)};}
   if(path.includes('/report'))return{report:sampleReport(sampleWorld()[0],'en')};
   if(path.includes('/team-members'))return{members:[{id:'team',name:'Team'}]};return{};
  }
 }
 class Renderer{constructor(){this.calls=[];}setFarms(farms){this.calls.push(farms.map(f=>({id:f.id,grade:f.assessment?.grade})));}overview(){}select(){}focus(){}zoom(){}}
 const source=(await readFile(new URL('../app.js',import.meta.url),'utf8')).replace(/^import.*;\r?\n/gm,'');
 const context={document,AdminApi:Api,FarmWorldRenderer:Renderer,CROP_ASSETS,...worldState,sampleWorld,sampleVisit,sampleReport,
 consumeLive:async()=>{},location:{search:''},URLSearchParams,AbortController,
 Option:function(text,value){const e=new Element('option');e.textContent=text;e.value=value;return e;},
 setTimeout:()=>1,clearTimeout(){},setInterval:()=>1,clearInterval(){},confirm:()=>true,console};
 vm.runInNewContext(source+';globalThis.inspect={state,api,selectField,openReport,loadReport,saveReport,signOut};',context);
 await flush();return{...context.inspect,elements,classes};
}
async function flush(){for(let i=0;i<3;i++)await new Promise(resolve=>setImmediate(resolve));}

test('sample exploration, class change, report release and sign-out never call the live mutation API',async()=>{
 const app=await workspace();await app.elements.get('sample-world').fire();
 assert.equal(app.state.farms.length,8);assert.equal(app.elements.get('workspace').hidden,false);
 await app.elements.get('sample-transition').fire();assert.equal(app.state.farms[0].assessment.grade,'A');
 assert.equal(app.state.renderer.calls.at(-1)[0].grade,'A');
 await app.openReport(sampleVisit(app.state.farms[0]));
 await app.saveReport(true);assert.equal(app.state.farms[0].latestSurveyStatus,'completed');
 assert.equal(app.api.calls.length,0);assert.equal(app.state.sampleReports.size,1);
 await app.elements.get('sign-out').fire();assert.equal(app.elements.get('workspace').hidden,true);assert.equal(app.state.farms.length,0);
});
test('directory and class filters update the actual field list',async()=>{
 const app=await workspace();await app.elements.get('sample-world').fire();
 app.elements.get('field-search').value='potato';await app.elements.get('field-search').fire('input');
 assert.equal(app.elements.get('field-list').children.length,2);
 await app.classes.find(e=>e.dataset.class==='A').fire();assert.equal(app.elements.get('field-list').children.length,0);assert.equal(app.elements.get('list-empty').hidden,false);
});
test('real report is saved privately before publishing and never publishes on save-only',async()=>{
 const app=await workspace();await app.elements.get('login-form').fire('submit');
 await app.selectField('sample-0');await app.openReport(sampleVisit(app.state.farms[0]));
 app.elements.get('report-language').value='mr'; // Body language must belong to the loaded template, not a racing select.
 app.elements.get('report-summary').value='We checked your field. Please arrange the next visit.';
 app.elements.get('report-actions').value='Ask the team to verify the moisture reading.';
 await app.saveReport(false);
 assert.equal(app.api.calls.filter(c=>c.path==='/admin/process-survey').length,0);
 assert.equal(app.api.calls.filter(c=>c.method==='POST').at(-1).body.language,'en');
 await app.saveReport(true);
 const mutations=app.api.calls.filter(c=>c.method==='POST');assert.ok(mutations.at(-2).path.endsWith('/report'));
 assert.equal(mutations.at(-1).path,'/admin/process-survey');assert.equal(mutations.at(-1).body.action,'publish');
});
