// Fetch-based SSE supports Bearer headers; no authentication token is placed in a URL.
export function parseEvents(buffer){
 const events=[];let end;buffer=buffer.replace(/\r\n/g,'\n');
 while((end=buffer.indexOf('\n\n'))>=0){const block=buffer.slice(0,end);buffer=buffer.slice(end+2);let event='message',data=[];
  for(const line of block.split('\n')){if(line.startsWith('event:'))event=line.slice(6).trim();if(line.startsWith('data:'))data.push(line.slice(5).trimStart());}
  if(data.length){try{events.push({event,data:JSON.parse(data.join('\n'))});}catch{throw new Error('Invalid live-update payload');}}
 }
 if(buffer.length>4000000)throw new Error('Live-update payload too large');
 return{events,rest:buffer};
}
export async function consumeLive(api,signal,onEvent,limit=200){
 if(!api.session)throw new Error('Sign in again');
 if(api.session.expiresAt-Date.now()<45000)await api.refreshToken();
 const response=await api.fetcher(api.baseUrl+'/world/events?limit='+limit,{headers:{Authorization:'Bearer '+api.session.idToken},cache:'no-store',signal});
 if(!response.ok||!response.body)throw Object.assign(new Error('Live updates unavailable'),{status:response.status});
 const reader=response.body.getReader(),decoder=new TextDecoder();let buffer='';
 try{while(!signal.aborted){const value=await reader.read();if(value.done)break;buffer+=decoder.decode(value.value,{stream:true});const parsed=parseEvents(buffer);buffer=parsed.rest;for(const event of parsed.events)onEvent(event);}}
 finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
}
