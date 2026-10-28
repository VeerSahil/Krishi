import{clamp,multiply,perspective,lookAt,translation,project,inPolygon,regionPosition,transitionValue}from'./math3d.js';
import{cropGeometry,groundGeometry}from'./assets.js';
import{CLASSES,careClass,STATUS}from'./world-state.js';
const VERTEX=`
attribute vec3 aPosition;attribute vec3 aNormal;attribute vec3 aColor;attribute float aKind;
uniform mat4 uProjectionView;uniform mat4 uModel;uniform float uCare;uniform vec3 uBorder;uniform vec3 uEye;
varying vec3 vColor;varying float vFog;
void main(){vec3 p=aPosition;vec3 color=aColor;
if(aKind>.5&&aKind<1.5){p.y=.35+(p.y-.35)*(1.-uCare*.43);p.x+=(p.y-.35)*uCare*.11;color=mix(color,vec3(.54,.39,.20),uCare*.82);}
if(aKind>1.5){color=uBorder;}
vec4 world=uModel*vec4(p,1.);float diffuse=max(dot(normalize(aNormal),normalize(vec3(-.4,.85,.5))),0.);
vColor=color*(.63+diffuse*.37);vFog=clamp(length(world.xyz-uEye)/650.,0.,.65);
gl_Position=uProjectionView*world;}`;
const FRAGMENT=`precision mediump float;varying vec3 vColor;varying float vFog;void main(){gl_FragColor=vec4(mix(vColor,vec3(.89,.93,.88),vFog),1.);}`;
export class FarmWorldRenderer{
 constructor(canvas,labels,onSelect){
  this.canvas=canvas;this.labels=labels;this.onSelect=onSelect;this.farms=new Map();this.buffers=new Map();this.labelNodes=new Map();this.selected=null;this.dirty=true;
  this.camera={target:[28,0,9],distance:90,yaw:-.65,elevation:.88};this.controller=new AbortController();
  this.reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
  const gl=canvas.getContext('webgl',{antialias:true,alpha:false,powerPreference:'low-power'});
  if(!gl)throw new Error('3D rendering is unavailable in this browser. Your fields remain accessible in the field list.');this.gl=gl;
  const shader=(type,source)=>{const value=gl.createShader(type);gl.shaderSource(value,source);gl.compileShader(value);if(!gl.getShaderParameter(value,gl.COMPILE_STATUS))throw new Error('Could not prepare the 3D view.');return value;};
  this.program=gl.createProgram();gl.attachShader(this.program,shader(gl.VERTEX_SHADER,VERTEX));gl.attachShader(this.program,shader(gl.FRAGMENT_SHADER,FRAGMENT));gl.linkProgram(this.program);
  if(!gl.getProgramParameter(this.program,gl.LINK_STATUS))throw new Error('Could not prepare the 3D view.');
  this.attr=Object.fromEntries(['aPosition','aNormal','aColor','aKind'].map(k=>[k,gl.getAttribLocation(this.program,k)]));
  this.uniform=Object.fromEntries(['uProjectionView','uModel','uCare','uBorder','uEye'].map(k=>[k,gl.getUniformLocation(this.program,k)]));
  gl.enable(gl.DEPTH_TEST);gl.clearColor(.89,.93,.88,1);this.bindControls();
  this.resizeObserver=new ResizeObserver(()=>{this.resize();this.dirty=true;});this.resizeObserver.observe(canvas);this.resize();
  canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();this.lost=true;canvas.dispatchEvent(new CustomEvent('world-unavailable'));},{signal:this.controller.signal});
  this.frame=requestAnimationFrame(time=>this.loop(time));
 }
 resize(){const r=this.canvas.getBoundingClientRect(),dpr=Math.min(devicePixelRatio||1,2);this.width=Math.max(r.width,1);this.height=Math.max(r.height,1);this.canvas.width=Math.round(this.width*dpr);this.canvas.height=Math.round(this.height*dpr);this.gl.viewport(0,0,this.canvas.width,this.canvas.height);}
 upload(array){const gl=this.gl,buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,array,gl.STATIC_DRAW);return{buffer,count:array.length/10};}
 setFarms(farms){
  const now=performance.now(),ids=new Set(farms.map(f=>f.id));
  for(const[id]of this.farms)if(!ids.has(id)){this.farms.delete(id);this.labelNodes.get(id)?.remove();this.labelNodes.delete(id);}
  for(const farm of farms){
   const old=this.farms.get(farm.id),grade=careClass(farm),target=CLASSES[grade]?.care??.15;
   if(old&&old.data.version>farm.version)continue;
   const from=old?this.careAt(old,now):target;
   this.farms.set(farm.id,{data:farm,from:from,to:target,changedAt:now,position:regionPosition(farm.slot)});
   if(!this.buffers.has(farm.cropAsset))this.buffers.set(farm.cropAsset,this.upload(cropGeometry(farm.cropAsset)));
   let label=this.labelNodes.get(farm.id);
   if(!label){label=document.createElement('button');label.type='button';label.className='plot-label';label.addEventListener('click',()=>this.onSelect(farm.id),{signal:this.controller.signal});this.labels.append(label);this.labelNodes.set(farm.id,label);}
   label.replaceChildren();const mark=document.createElement('span');mark.className='plot-grade grade-'+grade;mark.textContent=grade==='U'?'?':grade;
   const text=document.createElement('span');text.textContent=farm.farmName;label.append(mark,text);
   label.setAttribute('aria-label',farm.farmName+', '+CLASSES[grade].label+', '+(STATUS[farm.latestSurveyStatus]||'No survey yet'));
   label.dataset.pending=String(farm.latestSurveyStatus==='pending');label.classList.toggle('selected',this.selected===farm.id);
  }
  if(this.ground)this.gl.deleteBuffer(this.ground.buffer);this.ground=this.upload(groundGeometry(farms));this.dirty=true;
 }
 careAt(farm,time){return this.reduced?farm.to:transitionValue(farm.from,farm.to,time-farm.changedAt);}
 select(id){this.selected=id;for(const[key,node]of this.labelNodes)node.classList.toggle('selected',key===id);this.dirty=true;}
 focus(id){const farm=this.farms.get(id);if(!farm)return;this.camera.target=[...farm.position];this.camera.distance=29;this.select(id);}
 overview(){const list=[...this.farms.values()];if(!list.length){this.camera.target=[28,0,8];this.camera.distance=90;return;}
 const xs=list.map(f=>f.position[0]),zs=list.map(f=>f.position[2]);this.camera.target=[(Math.min(...xs)+Math.max(...xs))/2,0,(Math.min(...zs)+Math.max(...zs))/2];this.camera.distance=clamp(Math.max(Math.max(...xs)-Math.min(...xs),Math.max(...zs)-Math.min(...zs))*1.1+28,40,220);this.camera.yaw=-.65;this.camera.elevation=.88;this.dirty=true;}
 zoom(amount){this.camera.distance=clamp(this.camera.distance*amount,12,250);this.dirty=true;}
 bindControls(){
  const signal=this.controller.signal;let down=null,moved=false;
  this.canvas.addEventListener('contextmenu',e=>e.preventDefault(),{signal});
  this.canvas.addEventListener('pointerdown',e=>{this.canvas.focus();this.canvas.setPointerCapture(e.pointerId);down={x:e.clientX,y:e.clientY,button:e.button,shift:e.shiftKey};moved=false;},{signal});
  this.canvas.addEventListener('pointermove',e=>{if(!down)return;const dx=e.clientX-down.x,dy=e.clientY-down.y;if(Math.abs(dx)+Math.abs(dy)>3)moved=true;
   if(down.button===2||down.shift){const s=this.camera.distance*.0017,yaw=this.camera.yaw;this.camera.target[0]-=(dx*Math.cos(yaw)+dy*Math.sin(yaw))*s;this.camera.target[2]+=(dx*Math.sin(yaw)-dy*Math.cos(yaw))*s;}
   else{this.camera.yaw-=dx*.007;this.camera.elevation=clamp(this.camera.elevation+dy*.006,.3,1.42);}down.x=e.clientX;down.y=e.clientY;this.dirty=true;
  },{signal});
  this.canvas.addEventListener('pointerup',e=>{if(down&&!moved){const r=this.canvas.getBoundingClientRect();this.pick(e.clientX-r.left,e.clientY-r.top);}down=null;},{signal});
  this.canvas.addEventListener('pointercancel',()=>{down=null;},{signal});
  this.canvas.addEventListener('wheel',e=>{e.preventDefault();this.zoom(Math.exp(e.deltaY*.001));},{passive:false,signal});
  this.canvas.addEventListener('keydown',e=>{const step=this.camera.distance*.035;const moves={ArrowLeft:[-step,0],ArrowRight:[step,0],ArrowUp:[0,-step],ArrowDown:[0,step]};if(moves[e.key]){e.preventDefault();this.camera.target[0]+=moves[e.key][0];this.camera.target[2]+=moves[e.key][1];this.dirty=true;}if(e.key==='+'||e.key==='=')this.zoom(.85);if(e.key==='-')this.zoom(1.15);},{signal});
 }
 pick(x,y){if(!this.projectionView)return;const candidates=[];for(const farm of this.farms.values()){const p=farm.position;const corners=[[-5.8,.35,-4.6],[5.8,.35,-4.6],[5.8,.35,4.6],[-5.8,.35,4.6]].map(v=>project(v.map((n,i)=>n+p[i]),this.projectionView,this.width,this.height));if(inPolygon(x,y,corners))candidates.push({id:farm.data.id,depth:corners.reduce((s,v)=>s+v.depth,0)});}candidates.sort((a,b)=>a.depth-b.depth);if(candidates.length)this.onSelect(candidates[0].id);}
 drawMesh(mesh,model,care,border){
  const gl=this.gl;gl.bindBuffer(gl.ARRAY_BUFFER,mesh.buffer);let offset=0;
  for(const[name,size]of[['aPosition',3],['aNormal',3],['aColor',3],['aKind',1]]){gl.enableVertexAttribArray(this.attr[name]);gl.vertexAttribPointer(this.attr[name],size,gl.FLOAT,false,40,offset);offset+=size*4;}
  gl.uniformMatrix4fv(this.uniform.uModel,false,model);gl.uniform1f(this.uniform.uCare,care);gl.uniform3fv(this.uniform.uBorder,border);gl.drawArrays(gl.TRIANGLES,0,mesh.count);
 }
 render(time){
  const gl=this.gl,c=this.camera,r=Math.cos(c.elevation)*c.distance;
  const eye=[c.target[0]+Math.sin(c.yaw)*r,c.target[1]+Math.sin(c.elevation)*c.distance,c.target[2]+Math.cos(c.yaw)*r];
  this.projectionView=multiply(perspective(.67,this.width/this.height,.1,5000),lookAt(eye,c.target));
  gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(this.program);gl.uniformMatrix4fv(this.uniform.uProjectionView,false,this.projectionView);gl.uniform3fv(this.uniform.uEye,eye);
  if(this.ground)this.drawMesh(this.ground,translation(0,0,0),0,[1,1,1]);
  for(const farm of this.farms.values()){
   const label=this.labelNodes.get(farm.data.id),p=farm.position,screen=project([p[0],2.4,p[2]+5],this.projectionView,this.width,this.height);
   const visible=screen&&screen.depth<1&&screen.x>-120&&screen.x<this.width+120&&screen.y>-80&&screen.y<this.height+80;
   label.hidden=!visible;if(!visible)continue;
   label.style.transform='translate('+screen.x+'px,'+screen.y+'px) translate(-50%,0)';
   const grade=careClass(farm.data),border=this.selected===farm.data.id?[.98,.97,.81]:CLASSES[grade].color;
   this.drawMesh(this.buffers.get(farm.data.cropAsset),translation(...p),this.careAt(farm,time),border);
  }
 }
 loop(time){if(!this.lost&&!document.hidden){const changing=[...this.farms.values()].some(f=>time-f.changedAt<1550&&f.from!==f.to);if(this.dirty||changing){this.render(time);this.dirty=false;}}this.frame=requestAnimationFrame(t=>this.loop(t));}
 destroy(){cancelAnimationFrame(this.frame);this.controller.abort();this.resizeObserver.disconnect();for(const mesh of this.buffers.values())this.gl.deleteBuffer(mesh.buffer);if(this.ground)this.gl.deleteBuffer(this.ground.buffer);this.gl.deleteProgram(this.program);this.labels.replaceChildren();}
}
