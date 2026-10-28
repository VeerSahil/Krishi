import{AdminApi}from'/admin/portal-api.js';
import{FarmWorldRenderer}from'./renderer.js';
import{CROP_ASSETS}from'./assets.js';
import{CLASSES,STATUS,careClass,matchingFarms,newerSnapshot,canApprove,canRelease}from'./world-state.js';
import{consumeLive}from'./live-client.js';
import{sampleWorld,sampleVisit,sampleReport}from'./sample-world.js';
const $=selector=>document.querySelector(selector),api=new AdminApi({role:'staff'});
const state={farms:[],user:null,demo:false,selected:null,selectionRequest:0,grade:'all',renderer:null,nextCursor:null,windowLimit:200,controller:null,retry:null,poll:null,epoch:0,team:[],farmerCursor:null,report:null,reportDirty:false,sampleReports:new Map(),reportRequest:0};
const labels={moisture:'Moisture',temperature:'Temperature',nitrogen:'Nitrogen (N)',potassium:'Potassium (K)'};
function node(tag,text,className){const el=document.createElement(tag);if(text!=null)el.textContent=String(text);if(className)el.className=className;return el;}
function toast(message){$('#toast').textContent=message;$('#toast').hidden=false;clearTimeout(state.toastTimer);state.toastTimer=setTimeout(()=>{$('#toast').hidden=true;},5500);}
function connection(text,kind=''){const el=$('#connection');el.textContent=text;el.className='connection '+kind;}
function action(label,handler,kind='primary full'){const b=node('button',label,kind);b.type='button';b.addEventListener('click',()=>busy(b,handler));return b;}
async function busy(button,work){button.disabled=true;try{await work();}catch(error){toast(error.message||String(error));if(error.status===401)signOut();}finally{button.disabled=false;}}
const selectedFarm=()=>state.farms.find(f=>f.id===state.selected);
function initRenderer(){if(state.renderer)return;try{state.renderer=new FarmWorldRenderer($('#world-canvas'),$('#plot-labels'),id=>selectField(id));}catch(error){$('#world-error').textContent=error.message;$('#world-error').hidden=false;}}
function renderList(){
 const rows=matchingFarms(state.farms,$('#field-search').value,state.grade),container=$('#field-list');container.replaceChildren();
 $('#field-count').textContent=state.farms.length+' '+(state.user?.role==='team'?'assigned fields loaded':'registered fields loaded');
 for(const grade of['A','B','C','U'])$('#count-'+grade).textContent=state.farms.filter(f=>careClass(f)===grade).length;
 $('#list-empty').hidden=rows.length>0;
 for(const farm of rows){const b=node('button',null,'field-card'+(farm.id===state.selected?' active':''));b.type='button';b.setAttribute('aria-pressed',String(farm.id===state.selected));
  const asset=CROP_ASSETS.find(a=>a.id===farm.cropAsset),icon=node('span',asset?.icon||'♧','field-icon'),copy=node('span',null,'field-copy');
  copy.append(node('strong',farm.farmName),node('span',farm.farmerName+' · '+(asset?.name||farm.cropAsset)));
  const foot=node('span',null,'field-card-foot'),grade=careClass(farm);foot.append(node('span',grade==='U'?'?':grade,'mini-grade grade-'+grade),node('span',STATUS[farm.latestSurveyStatus]||'No visit yet'));copy.append(foot);b.append(icon,copy);b.addEventListener('click',()=>selectField(farm.id,true));container.append(b);
 }
 $('#world-empty').hidden=state.farms.length>0;
 $('#world-empty-copy').textContent=state.user?.role==='team'?'Your fields appear here when an admin approves and assigns a visit.':'Add a registered farmer’s field and choose its crop asset.';
 $('#more-fields').hidden=!state.nextCursor||state.farms.length>=1000;
}
function applyFarms(incoming){
 const before=new Map(state.farms.map(f=>[f.id,careClass(f)]));state.farms=newerSnapshot(state.farms,incoming);
 renderList();state.renderer?.setFarms(state.farms);
 for(const farm of state.farms)if(before.has(farm.id)&&before.get(farm.id)!==careClass(farm))$('#world-announcement').textContent=farm.farmName+' changed from class '+before.get(farm.id)+' to '+careClass(farm)+'.';
 if(state.selected){if(selectedFarm())selectField(state.selected,false);else{state.selected=null;$('#selection').hidden=true;$('#selection-empty').hidden=false;}}
}
async function reload(){
 if(state.demo)return;
 const epoch=state.epoch,all=[];let cursor=null,result;
 do{result=await api.request('/world/farms?limit=200'+(cursor?'&cursor='+encodeURIComponent(cursor):''));all.push(...result.farms);cursor=result.nextCursor;}while(cursor&&all.length<state.windowLimit);
 if(epoch!==state.epoch)return;state.nextCursor=cursor;applyFarms(all);
}
function stopLive(){state.controller?.abort();clearTimeout(state.retry);clearInterval(state.poll);state.controller=null;state.retry=null;state.poll=null;}
function startLive(){
 stopLive();if(state.demo||!state.user)return;
 const epoch=state.epoch;state.controller=new AbortController();const controller=state.controller;
 consumeLive(api,controller.signal,event=>{
  if(epoch!==state.epoch)return;
  if(event.event==='snapshot'){connection('Live updates','live');applyFarms(event.data.farms);}
  if(event.event==='revoked'){toast(event.data.message);signOut();}
  if(event.event==='reconnect'){connection('Polling fallback','offline');controller.abort();}
 },state.windowLimit).catch(error=>{if(!controller.signal.aborted&&epoch===state.epoch){connection('Reconnecting','offline');if(error.status===401)api.refreshToken().catch(()=>signOut());}}).finally(()=>{
  if(epoch===state.epoch&&state.user&&!state.demo){connection('Polling fallback','offline');state.retry=setTimeout(()=>startLive(),5000);}
 });
 state.poll=setInterval(()=>{if(!document.hidden)reload().catch(()=>connection('Offline · retrying','offline'));},15000);
}
function openWorkspace(user,demo=false){state.user=user;state.demo=demo;state.epoch++;$('#login').hidden=true;$('#workspace').hidden=false;$('#sample-banner').hidden=!demo;$('#sign-out').hidden=false;$('#member').hidden=false;$('#member').textContent=user.name||user.role;$('#add-field').hidden=user.role!=='admin'||demo;$('#dashboard-link').hidden=demo;$('#dashboard-link').href=user.role==='admin'?'/admin/':'/team/';$('#dashboard-link').textContent=user.role==='admin'?'Dashboard ↗':'Team workspace ↗';initRenderer();}
function signOut(){stopLive();state.epoch++;api.signOut();state.user=null;state.demo=false;state.farms=[];state.selected=null;state.report=null;state.renderer?.setFarms([]);$('#login').hidden=false;$('#workspace').hidden=true;$('#sample-banner').hidden=true;for(const id of['sign-out','member','add-field','dashboard-link'])$('#'+id).hidden=true;$('#farm-dialog').close();$('#report-dialog').close();connection('Not connected');}
async function selectField(id,focus=false){
 const farm=state.farms.find(f=>f.id===id);if(!farm)return;state.selected=id;const request=++state.selectionRequest;state.renderer?.select(id);if(focus)state.renderer?.focus(id);renderList();renderSelection(farm,null);
 try{const data=state.demo?{farm,survey:{...sampleVisit(farm),farmerReport:state.sampleReports.get(farm.id)}}:await api.request('/world/farms/'+encodeURIComponent(id));
  if(request!==state.selectionRequest||state.selected!==id||!state.user)return;
  renderSelection(data.farm,data.survey);
 }catch(error){if(request===state.selectionRequest)toast(error.message);}
}
function reading(parent,label,value,unit=''){const item=node('div',null,'reading');item.append(node('strong',value==null?'—':String(value)+unit),node('span',label));parent.append(item);}
function renderSelection(farm,survey){
 $('#selection-empty').hidden=true;$('#selection').hidden=false;$('#selected-owner').textContent=farm.farmerName;$('#selected-name').textContent=farm.farmName;
 const asset=CROP_ASSETS.find(a=>a.id===farm.cropAsset),grade=careClass(farm),info=CLASSES[grade];$('#selected-grade').textContent=grade==='U'?'Unverified':'Class '+grade;$('#selected-grade').className='care-badge grade-'+grade;
 $('#selected-meta').textContent=(asset?.name||farm.cropAsset)+' · '+farm.city+' · Region '+farm.slot;
 const notices=$('#selected-notices');notices.replaceChildren();
 if(farm.assessment?.demonstrationOnly)notices.append(node('p','Demo assessment · review the evidence before acting.','notice'));
 if(survey?.temperatureSource==='simulated')notices.append(node('p','Temperature was simulated, not measured.','notice'));
 $('#selected-status').textContent=STATUS[farm.latestSurveyStatus]||'No survey requested yet';
 const metrics=$('#selected-readings');metrics.replaceChildren();
 if(survey?.moisture!=null){reading(metrics,survey.moistureUnit==='vwc_percent'?'Moisture · volumetric':'Moisture · relative / declared',survey.moisture,'%');reading(metrics,'Temperature'+(survey.temperatureSource==='simulated'?' · demo':''),survey.temperature,' °C');reading(metrics,'Nitrogen · '+(survey.nutrientUnit||'units unspecified'),survey.nitrogen);reading(metrics,'Potassium · '+(survey.nutrientUnit||'units unspecified'),survey.potassium);}
 const findings=$('#selected-findings');findings.replaceChildren();
 if(farm.assessment){findings.append(node('h3',info.label));
  for(const finding of farm.assessment.findings||[])findings.append(node('div',(labels[finding.key]||finding.key)+' is '+finding.value+'; policy band '+finding.low+'–'+finding.high+'. Confirm with the team.','finding'));
  if(!farm.assessment.findings?.length&&grade==='A')findings.append(node('p','No readings outside the selected bands. This does not establish crop health.','small-note'));
  for(const warning of farm.assessment.warnings||[])findings.append(node('p',warning,'small-note'));
  if(farm.previousClass&&farm.previousClass!==grade)findings.append(node('p','Last change: '+farm.previousClass+' → '+grade,'transition-note'));
 }else findings.append(node('p','An inspection will add the first care class to this field.','small-note'));
 const policy=$('#selected-policy');policy.replaceChildren();policy.append(node('p',farm.policy.name+' · '+(farm.policy.basis==='demo_rules'?'Demonstration bands':'Admin-configured bands')));
 const table=node('table');for(const[key,band]of Object.entries(farm.policy.ranges)){const row=node('tr');row.append(node('td',labels[key]),node('td',band.low+'–'+band.high));table.append(row);}policy.append(table,node('p','A: no out-of-band readings. B: one. C: two or more. U: evidence or units need verification. Classes use moisture, temperature, N and K; P stays in the visit record.'));
 if(farm.policy.reference)policy.append(node('p','Reference: '+farm.policy.reference));
 const actions=$('#selected-actions');actions.replaceChildren();
 if(canApprove(state.user.role,survey))renderApproval(actions,survey);
 else if(canRelease(state.user.role,survey))actions.append(action('Prepare farmer report →',()=>openReport(survey)));
 else if(survey?.status==='completed'&&survey.farmerReport)renderPublishedReport(actions,survey.farmerReport);
 else if(survey?.status==='approved'||survey?.status==='in_progress'){
  actions.append(node('p','Use the same Krishi Team mobile visit form to record the gadget readings and submit them. The world updates after the report is saved.','small-note'));
  if(state.user.role==='team'){const link=node('a','Open team website ↗','secondary full');link.href='/team/';actions.append(link);}
 }else if(!survey&&state.user.role==='admin')renderUnlinked(actions,farm);
}
async function renderApproval(parent,survey){
 const label=node('label','Assign an inspector'),select=node('select');select.append(new Option('Choose a team member',''));label.append(select);parent.append(label);
 try{if(state.demo)state.team=[{id:'sample-team',name:'Sample inspection team'}];else if(!state.team.length)state.team=(await api.request('/admin/team-members?limit=100')).members||[];
  if(state.selected!==survey.farmId)return;for(const member of state.team)select.append(new Option(member.name||member.email||member.id,member.id));
 }catch(error){toast(error.message);}
 parent.append(action('Approve visit & assign →',async()=>{
  if(!select.value)throw new Error('Choose a team member first.');
  if(state.demo){const farm=selectedFarm();farm.latestSurveyStatus='approved';farm.version++;applyFarms([...state.farms]);toast('Sample visit approved. No live request was changed.');return;}
  await api.request('/admin/process-survey',{method:'POST',body:{surveyId:survey.surveyId,action:'approve',teamId:select.value}});await reload();toast('Visit approved and assigned.');
 }));
}
async function renderUnlinked(parent,farm){
 parent.append(node('p','The farmer can request a survey from their phone. Older unlinked requests can be connected below.','small-note'));if(state.demo)return;
 try{const data=await api.request('/admin/surveys?status=pending&farmer_id='+encodeURIComponent(farm.farmerId)+'&limit=100');if(state.selected!==farm.id||!parent.isConnected)return;const rows=data.surveys.filter(s=>!s.farmId);if(!rows.length)return;
  const label=node('label','Existing farmer request'),select=node('select');select.append(new Option('Choose a request',''));for(const s of rows)select.append(new Option(s.farmName+' · '+s.surveyId,s.surveyId));label.append(select);parent.append(label,action('Connect request to this field',async()=>{if(!select.value)throw new Error('Choose the matching farmer request.');await api.request('/world/farms/'+encodeURIComponent(farm.id)+'/link-survey',{method:'POST',body:{surveyId:select.value}});await reload();toast('Request connected to this field.');},'secondary full'));
 }catch(error){toast(error.message);}
}
function renderPublishedReport(parent,report){const copy=node('article',null,'report-copy');copy.lang=report.language;copy.append(node('span',report.language.toUpperCase()+' · APPROVED REPORT','report-language'),node('h3',report.title),node('p',report.summary));const list=node('ul');for(const step of report.actions)list.append(node('li',step));copy.append(list);for(const note of report.notices||[])copy.append(node('p',note,'small-note'));parent.append(copy);}

async function loadFarmers(more=false){
 const data=await api.request('/admin/farmers?limit=100'+(more&&state.farmerCursor?'&cursor='+encodeURIComponent(state.farmerCursor):''));
 if(!more)$('#farm-owner').replaceChildren(new Option('Choose a farmer',''));
 for(const farmer of data.farmers)$('#farm-owner').append(new Option(farmer.name+' · '+farmer.email,farmer.id));
 state.farmerCursor=data.nextCursor;$('#more-farmers').hidden=!data.nextCursor;
}
async function openFarmDialog(){
 if(state.demo||state.user?.role!=='admin')return;$('#farm-error').textContent='';$('#farm-form').reset();
 const occupied=new Set(state.farms.map(f=>f.slot));let slot=1;while(occupied.has(slot))slot++;$('#farm-slot').value=slot;
 $('#farm-dialog').showModal();$('#create-farm').disabled=true;
 try{await loadFarmers();const soils=await api.fetchJson(api.baseUrl+'/soil-types');$('#farm-soil').replaceChildren(...soils.soil_types.map(s=>new Option(s,s)));$('#farm-soil').value='Black';}
 catch(error){$('#farm-error').textContent=error.message;}
 finally{$('#create-farm').disabled=false;}
}
function policyFromForm(){return{name:$('#policy-name').value.trim(),basis:$('#policy-basis').value,moistureUnit:$('#policy-moisture-unit').value,nutrientUnit:$('#policy-nutrient-unit').value,reference:$('#policy-reference').value.trim()||null,ranges:Object.fromEntries(Object.keys(labels).map(key=>[key,{low:Number($('#band-'+key+'-low').value),high:Number($('#band-'+key+'-high').value)}]))};}
async function loadReport(language){
 const farm=selectedFarm(),sid=state.reportSurveyId,epoch=state.epoch,request=++state.reportRequest;state.report=null;$('#release-report').disabled=true;$('#save-report').disabled=true;
 try{const data=state.demo?{report:sampleReport(farm,language)}:await api.request('/world/surveys/'+encodeURIComponent(sid)+'/report?language='+language);
  if(sid!==state.reportSurveyId||epoch!==state.epoch||request!==state.reportRequest)return;
  state.report=data.report;state.reportDirty=false;$('#report-summary').value=data.report.summary;$('#report-actions').value=data.report.actions.join('\n');$('#report-error').textContent='';
  const context=$('#report-context');context.replaceChildren(node('strong',farm.farmName),node('span','Class '+data.report.careClass+' · '+(CLASSES[data.report.careClass]?.label||'Needs verification')));
  const notices=$('#report-notices');notices.replaceChildren(...data.report.notices.map(note=>node('p',note)));
 }catch(error){if(request===state.reportRequest){$('#report-error').textContent=error.message;state.report=null;}}
 finally{if(request===state.reportRequest){$('#release-report').disabled=!state.report;$('#save-report').disabled=!state.report;}}
}
async function openReport(survey){state.reportSurveyId=survey.surveyId;$('#report-language').value='en';$('#report-dialog').showModal();await loadReport('en');}
async function saveReport(release=false){
 if(!state.report||!$('#report-form').reportValidity())return;const actions=$('#report-actions').value.split('\n').map(s=>s.trim()).filter(Boolean);
 if(!actions.length||actions.length>6||actions.some(s=>s.length>500)){ $('#report-error').textContent='Add one to six clear steps, each under 500 characters.';return;}
 const body={submissionId:state.report.submissionId,language:state.report.language,summary:$('#report-summary').value.trim(),actions};
 $('#release-report').disabled=true;$('#save-report').disabled=true;$('#report-error').textContent='';
 try{
  if(state.demo){const report={...state.report,...body};state.sampleReports.set(state.selected,report);if(release){const farm=selectedFarm();farm.latestSurveyStatus='completed';farm.version++;applyFarms([...state.farms]);}}
  else{await api.request('/world/surveys/'+encodeURIComponent(state.reportSurveyId)+'/report',{method:'POST',body});if(release)await api.request('/admin/process-survey',{method:'POST',body:{surveyId:state.reportSurveyId,action:'publish'}});}
  state.reportDirty=false;
  if(release){$('#report-dialog').close();if(!state.demo)await reload();else selectField(state.selected);toast(state.demo?'Sample report released locally. Nothing was sent.':'Approved report is now available in the farmer app.');}
  else toast(state.demo?'Sample draft saved locally.':'Report draft saved privately.');
 }catch(error){$('#report-error').textContent=error.message;}
 finally{$('#release-report').disabled=false;$('#save-report').disabled=false;}
}
function enterSample(){api.signOut();stopLive();state.selected=null;state.nextCursor=null;state.sampleReports.clear();openWorkspace({role:'admin',name:'Sample administrator'},true);connection('Sample data');applyFarms(sampleWorld());state.renderer?.overview();}
$('#login-form').addEventListener('submit',async event=>{event.preventDefault();$('#login-error').textContent='';const button=$('#login-submit');button.disabled=true;
 try{const user=await api.signIn($('#email').value.trim(),$('#password').value);$('#password').value='';state.team=[];state.selected=null;state.windowLimit=200;openWorkspace(user);await reload();state.renderer?.overview();const fieldId=new URLSearchParams(location.search).get('field');if(fieldId){if(!state.farms.some(f=>f.id===fieldId)){const detail=await api.request('/world/farms/'+encodeURIComponent(fieldId));applyFarms([...state.farms,detail.farm]);}await selectField(fieldId,true);}startLive();}
 catch(error){$('#login-error').textContent=error.message;signOut();}finally{button.disabled=false;}
});
$('#sample-world').addEventListener('click',enterSample);$('#sign-out').addEventListener('click',signOut);
$('#field-search').addEventListener('input',renderList);
for(const button of document.querySelectorAll('[data-class]'))button.addEventListener('click',()=>{state.grade=button.dataset.class;for(const b of document.querySelectorAll('[data-class]'))b.setAttribute('aria-pressed',String(b===button));renderList();});
$('#more-fields').addEventListener('click',()=>busy($('#more-fields'),async()=>{if(!state.nextCursor||state.demo)return;const result=await api.request('/world/farms?limit=200&cursor='+encodeURIComponent(state.nextCursor));state.nextCursor=result.nextCursor;const merged=new Map([...state.farms,...result.farms].map(f=>[f.id,f]));state.windowLimit=Math.min(1000,Math.max(200,Math.ceil(merged.size/200)*200));applyFarms([...merged.values()]);startLive();}));
$('#overview').addEventListener('click',()=>state.renderer?.overview());$('#zoom-in').addEventListener('click',()=>state.renderer?.zoom(.8));$('#zoom-out').addEventListener('click',()=>state.renderer?.zoom(1.25));
$('#world-canvas').addEventListener('world-unavailable',()=>{$('#world-error').textContent='The 3D view paused. You can still select fields from the list; reload to restore graphics.';$('#world-error').hidden=false;});
$('#sample-transition').addEventListener('click',()=>{const farm=state.farms.find(f=>f.id==='sample-0');if(!state.demo||!farm)return;const previous=careClass(farm);state.renderer?.focus(farm.id);farm.previousClass=previous;farm.assessment={...farm.assessment,grade:previous==='C'?'A':'C',findings:previous==='C'?[]:[{key:'moisture',value:19,low:30,high:70,direction:'low'},{key:'potassium',value:28,low:50,high:500,direction:'low'}]};farm.version++;state.selected=farm.id;$('#sample-transition').textContent='Preview class change '+farm.assessment.grade+' → '+previous;applyFarms([...state.farms]);toast('Sample animation only; no real field readings changed.');});
$('#add-field').addEventListener('click',()=>busy($('#add-field'),openFarmDialog));$('#close-farm').addEventListener('click',()=>$('#farm-dialog').close());$('#more-farmers').addEventListener('click',()=>busy($('#more-farmers'),()=>loadFarmers(true)));
$('#policy-basis').addEventListener('change',()=>{$('#policy-reference').required=$('#policy-basis').value==='configured_rules';});
$('#farm-form').addEventListener('submit',async event=>{event.preventDefault();if(state.demo||state.user?.role!=='admin')return;const button=$('#create-farm');button.disabled=true;$('#farm-error').textContent='';
 try{const body={farmerId:$('#farm-owner').value,farmName:$('#farm-name').value.trim(),farmAddress:$('#farm-address').value.trim(),city:$('#farm-city').value,soilType:$('#farm-soil').value,cropAsset:document.querySelector('input[name="crop-asset"]:checked')?.value||'potato',slot:Number($('#farm-slot').value),areaHectares:$('#farm-area').value?Number($('#farm-area').value):null,policy:policyFromForm()};
  const data=await api.request('/world/farms',{method:'POST',body});$('#farm-dialog').close();await reload();if(!state.farms.some(f=>f.id===data.farm.id))applyFarms([...state.farms,data.farm]);await selectField(data.farm.id,true);toast('Field added. The farmer can request its first survey.');
 }catch(error){$('#farm-error').textContent=error.message;}finally{button.disabled=false;}
});
$('#close-report').addEventListener('click',()=>$('#report-dialog').close());$('#report-form').addEventListener('submit',event=>{event.preventDefault();saveReport(true);});$('#save-report').addEventListener('click',()=>saveReport(false));
for(const id of['report-summary','report-actions'])$('#'+id).addEventListener('input',()=>{state.reportDirty=true;});
$('#report-language').addEventListener('change',()=>{if(state.reportDirty&&!confirm('Replace the unsaved text with the template for this language?')){$('#report-language').value=state.report.language;return;}loadReport($('#report-language').value);});
for(const asset of CROP_ASSETS){const label=node('label',null,'asset-choice'),input=document.createElement('input');input.type='radio';input.name='crop-asset';input.value=asset.id;input.checked=asset.id==='potato';const copy=node('span');copy.append(node('strong',asset.name),node('small',asset.note));label.append(input,node('span',asset.icon,'crop-symbol'),copy);$('#asset-picker').append(label);}
for(const[key,name]of Object.entries(labels)){const row=node('div',null,'range-row');row.append(node('span',name));for(const[side,value]of[['low',key==='moisture'?30:key==='temperature'?18:50],['high',key==='moisture'?70:key==='temperature'?35:500]]){const label=node('label'),text=node('span',side==='low'?'Minimum':'Maximum','sr-only'),input=document.createElement('input');input.type='number';input.step='any';input.id='band-'+key+'-'+side;input.value=value;input.required=true;label.append(text,input);row.append(label);}$('#policy-ranges').append(row);}
api.loadConfig().then(config=>{$('#login-submit').disabled=!config.configured;if(!config.configured)$('#login-error').textContent='Staff sign-in needs Firebase configuration. The sample world is available below.';}).catch(error=>{$('#login-error').textContent=error.message;});
if(new URLSearchParams(location.search).get('demo')==='1')enterSample();
