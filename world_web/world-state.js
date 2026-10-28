export const CLASSES={A:{label:'Routine follow-up',color:[.30,.57,.39],care:.04},B:{label:'One check needed',color:[.83,.62,.22],care:.38},C:{label:'Multiple checks needed',color:[.72,.35,.25],care:.88},U:{label:'Not yet verified',color:[.53,.61,.58],care:.15}};
export const STATUS={pending:'Survey requested',approved:'Visit approved',in_progress:'Team on site',awaiting_review:'Report to review',completed:'Report delivered',rejected:'Request declined'};
export const careClass=farm=>farm.assessment?.grade||'U';
export function matchingFarms(farms,search='',grade='all'){
 const term=search.trim().toLocaleLowerCase();
 return farms.filter(f=>(grade==='all'||careClass(f)===grade)&&[f.farmName,f.farmerName,f.city,f.id].some(value=>String(value||'').toLocaleLowerCase().includes(term)));
}
export function newerSnapshot(current,incoming){const previous=new Map(current.map(f=>[f.id,f]));return incoming.map(f=>{const old=previous.get(f.id);return old&&Number(old.version)>Number(f.version)?old:f;});}
export function canApprove(role,survey){return role==='admin'&&survey?.status==='pending';}
export function canRelease(role,survey){return role==='admin'&&survey?.status==='awaiting_review';}
