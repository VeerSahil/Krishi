// Original reusable low-poly assets, generated locally without third-party downloads.
export const CROP_ASSETS=[
{id:'potato',name:'Potato',note:'Leafy ridges',icon:'◒'},
{id:'wheat',name:'Wheat',note:'Grain rows',icon:'♧'},
{id:'maize',name:'Maize',note:'Tall stalks',icon:'♧'},
{id:'rice',name:'Rice',note:'Bunded beds',icon:'≋'},
{id:'cotton',name:'Cotton',note:'Cotton shrubs',icon:'✿'},
{id:'vegetables',name:'Vegetables',note:'Leafy beds',icon:'❋'}];
export function seedRandom(seed=17){let n=seed>>>0;return()=>{n=(1664525*n+1013904223)>>>0;return n/4294967296;};}
const norm=v=>{const n=Math.hypot(...v)||1;return v.map(x=>x/n);};
export class Geometry{
 constructor(){this.values=[];}
 triangle(a,b,c,color,kind=0){const u=b.map((v,i)=>v-a[i]),v=c.map((v,i)=>v-a[i]);const n=norm([u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]);for(const p of[a,b,c])this.values.push(...p,...n,...color,kind);}
 box(x,y,z,w,h,d,color,kind=0){const p=[[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]].map(v=>[x+v[0]*w/2,y+v[1]*h/2,z+v[2]*d/2]);for(const[a,b,c,e]of[[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]){this.triangle(p[a],p[b],p[c],color,kind);this.triangle(p[a],p[c],p[e],color,kind);}}
 sphere(x,y,z,rx,ry,rz,color,kind=1){const p=(a,b)=>[x+rx*Math.cos(a)*Math.sin(b),y+ry*Math.cos(b),z+rz*Math.sin(a)*Math.sin(b)];for(let r=0;r<4;r++)for(let s=0;s<6;s++){const a=s*Math.PI/3,b=(s+1)*Math.PI/3,c=r*Math.PI/4,d=(r+1)*Math.PI/4;this.triangle(p(a,c),p(a,d),p(b,d),color,kind);this.triangle(p(a,c),p(b,d),p(b,c),color,kind);}}
 leaf(x,y,z,dx,dy,dz,width,color){const side=norm([dz,0,-dx]).map(v=>v*width);this.triangle([x,y,z],[x+dx*.5+side[0],y+dy*.7,z+dz*.5+side[2]],[x+dx,y+dy,z+dz],color,1);this.triangle([x,y,z],[x+dx,y+dy,z+dz],[x+dx*.5-side[0],y+dy*.7,z+dz*.5-side[2]],color,1);}
 array(){return new Float32Array(this.values);}
}
export function cropGeometry(asset){
 if(!CROP_ASSETS.some(a=>a.id===asset))throw new Error('Unknown crop asset');
 const m=new Geometry(),random=seedRandom(asset.length*97+asset.charCodeAt(0)),soil=[.40,.27,.16],green=[.27,.49,.22],light=[.43,.63,.29];
 m.box(0,-.04,0,11.6,.6,9.2,[.51,.39,.25]);m.box(0,.28,0,11.3,.12,8.9,[.49,.35,.21]);
 for(const z of[-4.5,4.5])m.box(0,.35,z,11.5,.08,.1,[1,1,1],2);
 for(const x of[-5.7,5.7])m.box(x,.35,0,.1,.08,9.1,[1,1,1],2);
 for(let row=0;row<5;row++){const z=-3.25+row*1.6;m.box(0,.4,z,10.3,.16,.62,asset==='rice'?[.29,.44,.38]:soil);
  for(let col=0;col<8;col++){const x=-4.5+col*1.27+(random()-.5)*.13,zz=z+(random()-.5)*.15,c=col%2?green:light;
   if(asset==='potato'||asset==='vegetables'){m.box(x,.58,zz,.065,.5,.065,[.30,.39,.16],1);m.sphere(x,.77,zz,.38,.28,.34,c);m.sphere(x-.18,.64,zz+.15,.25,.20,.26,green);if(asset==='potato')m.sphere(x+.16,.97,zz-.06,.055,.05,.055,[.83,.73,.86]);}
   else if(asset==='wheat'){for(let s=0;s<3;s++){const xx=x+(s-1)*.11,h=.9+random()*.3;m.box(xx,.35+h/2,zz,.035,h,.035,[.58,.62,.25],1);m.sphere(xx,h+.35,zz,.075,.22,.07,[.81,.72,.38]);m.leaf(xx,.7,zz,.22,.22,.08,.05,c);}}
   else if(asset==='maize'){const h=1.65+random()*.25;m.box(x,.4+h/2,zz,.075,h,.075,[.35,.50,.19],1);for(let l=0;l<4;l++){const side=l%2?1:-1;m.leaf(x,.78+l*.24,zz,side*.63,.3,(l%3-1)*.35,.13,c);}m.sphere(x+.12,1.25,zz,.09,.22,.08,[.87,.72,.27]);}
   else if(asset==='rice'){for(let l=0;l<5;l++){const a=l*1.25;m.leaf(x,.45,zz,Math.cos(a)*.3,.8+random()*.3,Math.sin(a)*.3,.055,c);}}
   else{m.box(x,.83,zz,.06,.9,.06,[.37,.31,.20],1);m.sphere(x,.95,zz,.28,.32,.26,c);m.sphere(x-.23,1.05,zz+.14,.13,.13,.12,[.94,.92,.81]);m.sphere(x+.20,1.21,zz-.1,.13,.13,.12,[.96,.95,.87]);}
  }
 }
 for(let i=0;i<7;i++)m.box(-5.9,.8,-4+i*1.35,.10,1,.10,[.57,.45,.30]);
 for(const y of[.65,.98])m.box(-5.9,y,0,.06,.07,8.6,[.68,.54,.35]);m.box(5.1,.74,4.7,.13,.9,.13,[.57,.45,.30]);return m.array();
}
export function groundGeometry(farms){const m=new Geometry(),maxRow=Math.max(1,...farms.map(f=>Math.floor((f.slot-1)/6))),length=maxRow*12+29;
 m.box(35,-.8,(length-24)/2,99,1.1,length,[.64,.75,.49]);m.box(35,-.21,(length-24)/2,99,.09,length,[.71,.80,.56]);
 for(let col=0;col<5;col++)m.box(col*14+7,-.13,(length-24)/2,1.15,.03,length,[.86,.83,.67]);
 for(let row=0;row<=maxRow;row++)m.box(35,-.12,row*12+6,97,.03,1.1,[.86,.83,.67]);
 const random=seedRandom(91);for(let i=0;i<22;i++){const x=i%2?-12:83,z=-8+random()*Math.min(length,140),h=2+random()*1.2;m.box(x,h*.36,z,.30,h*.8,.30,[.42,.31,.19]);m.sphere(x,h,z,1.25,1.55,1.15,[.32+random()*.10,.48+random()*.08,.26],0);}
 m.box(-10,.65,-9,3.1,1.8,2.5,[.89,.85,.69]);m.box(-10,1.74,-9,3.7,.25,3,[.30,.43,.34]);m.box(-10,.5,-7.72,.65,1.35,.05,[.37,.33,.23]);return m.array();}
