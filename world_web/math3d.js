export const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
export function multiply(a,b){const out=new Float32Array(16);for(let c=0;c<4;c++)for(let r=0;r<4;r++)for(let k=0;k<4;k++)out[c*4+r]+=a[k*4+r]*b[c*4+k];return out;}
export function perspective(fov,aspect,near,far){const f=1/Math.tan(fov/2),n=1/(near-far);return new Float32Array([f/aspect,0,0,0,0,f,0,0,0,0,(far+near)*n,-1,0,0,2*far*near*n,0]);}
const dot=(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2];
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const norm=v=>{const n=Math.hypot(...v)||1;return v.map(x=>x/n);};
export function lookAt(eye,target){const z=norm(eye.map((v,i)=>v-target[i])),x=norm(cross([0,1,0],z)),y=cross(z,x);return new Float32Array([x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dot(x,eye),-dot(y,eye),-dot(z,eye),1]);}
export function translation(x,y,z){return new Float32Array([1,0,0,0,0,1,0,0,0,0,1,0,x,y,z,1]);}
export function project(point,matrix,width,height){const p=[...point,1],clip=[0,0,0,0];for(let r=0;r<4;r++)for(let k=0;k<4;k++)clip[r]+=matrix[k*4+r]*p[k];if(clip[3]<=0)return null;return{x:(clip[0]/clip[3]*.5+.5)*width,y:(.5-clip[1]/clip[3]*.5)*height,depth:clip[2]/clip[3]};}
export function inPolygon(x,y,points){if(points.some(p=>!p))return false;let inside=false;for(let i=0,j=points.length-1;i<points.length;j=i++){const a=points[i],b=points[j];if((a.y>y)!==(b.y>y)&&x<(b.x-a.x)*(y-a.y)/(b.y-a.y)+a.x)inside=!inside;}return inside;}
export function regionPosition(slot){const n=Number(slot)-1;return[(n%6)*14,0,Math.floor(n/6)*12];}
export function transitionValue(from,to,elapsed,duration=1500){const t=clamp(elapsed/duration,0,1);return from+(to-from)*t*t*(3-2*t);}
