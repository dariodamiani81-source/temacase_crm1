// TEMACASE_GOOGLE_MULTI_V2
import postgres from 'npm:postgres@3.4.7';
import {createRemoteJWKSet,jwtVerify} from 'npm:jose@6.1.0';
const env=(k:string)=>{const v=Deno.env.get(k);if(!v)throw new Error('config_'+k);return v;};
const db=postgres(env('TEMACASE_DATABASE_URL'),{max:1,connect_timeout:5,idle_timeout:10});
const enc=new TextEncoder(),uuid=/^[a-f0-9-]{36}$/;
const scopes=['openid','https://www.googleapis.com/auth/userinfo.email','https://www.googleapis.com/auth/calendar.calendarlist.readonly','https://www.googleapis.com/auth/calendar.events','https://www.googleapis.com/auth/tasks'];
const jwks=createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
const b64=(x:Uint8Array)=>btoa(String.fromCharCode(...x));
const un64=(s:string)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const random=()=>b64(crypto.getRandomValues(new Uint8Array(32))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
async function hash(s:string){return new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(s)));}
async function uguale(a:string,b:string){const x=await hash(a),y=await hash(b);let n=0;for(let j=0;j<x.length;j++)n|=x[j]^y[j];return n===0;}
async function chiave(){const raw=un64(env('TEMACASE_GOOGLE_TOKEN_KEY'));if(raw.length!==32)throw new Error('config_chiave');return await crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt','decrypt']);}
async function cifra(v:any,aad:string){const iv=crypto.getRandomValues(new Uint8Array(12));const data=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:enc.encode(aad)},await chiave(),enc.encode(JSON.stringify(v)));return {v:1,iv:b64(iv),data:b64(new Uint8Array(data))};}
async function decifra(v:any,aad:string){if(v?.v!==1)throw new Error('cifratura');const raw=await crypto.subtle.decrypt({name:'AES-GCM',iv:un64(v.iv),additionalData:enc.encode(aad)},await chiave(),un64(v.data));return JSON.parse(new TextDecoder().decode(raw));}
async function utente<T>(id:string,fn:(q:any)=>Promise<T>):Promise<T>{return await db.begin(async q=>{await q`SELECT set_config('temacase.telegram_user_id',${id},true)`;return await fn(q);}) as T;}
async function accesso(id:string,k:string,azione='leggi',p:any={}){return await utente(id,async q=>(await q`SELECT temacase_test.crm_google_v2_account(${k}::uuid,${azione},${q.json(p)}) AS r`)[0].r);}
async function invio(id:string,k:string,azione='leggi',p:any={}){return await utente(id,async q=>(await q`SELECT temacase_test.crm_google_v2_invio(${k}::uuid,${azione},${q.json(p)}) AS r`)[0].r);}
const btn=(text:string,a:string,b?:string,c?:string)=>({text:text.slice(0,60),callback_data:['t','gm',a,b,c].filter(x=>x!==undefined).join(':')});
const reply=(text:string,inline_keyboard:any[][]=[])=>({text,inline_keyboard});
const ora=(s:string)=>new Intl.DateTimeFormat('it-IT',{timeZone:'Europe/Rome',dateStyle:'short',timeStyle:'short'}).format(new Date(s));
class GError extends Error {status:number;constructor(status:number){super('google_'+status);this.status=status;}}
async function google(url:string,init:RequestInit={}){const r=await fetch(url,{...init,signal:AbortSignal.timeout(15000)});if(!r.ok)throw new GError(r.status);if(r.status===204)return null;return await r.json();}
const aad=(c:any,id:string)=>c.token_cifrati.ctx===2?`conn2:${c.agenzia_id}:${id}:${c.google_sub}`:`conn:${c.agenzia_id}:${id}`;
async function token(id:string,k:string){
 let c=await accesso(id,k);if(!c||c.stato!=='attivo')throw new Error('ricollega');let t=await decifra(c.token_cifrati,aad(c,id));
 if(Date.parse(c.accesso_scade_il)<=Date.now()+60000){
  let r:any;try{r=await google('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:env('TEMACASE_GOOGLE_CLIENT_ID'),client_secret:env('TEMACASE_GOOGLE_CLIENT_SECRET'),grant_type:'refresh_token',refresh_token:t.refresh_token})});}
  catch(e){if(e instanceof GError&&e.status===400)await accesso(id,k,'invalida',{precedente:c.token_cifrati});throw e;}
  if(typeof r.access_token!=='string'||!Number.isFinite(r.expires_in)||r.expires_in<=0)throw new Error('token_incompleto');
  const nuovo={access_token:r.access_token,refresh_token:r.refresh_token||t.refresh_token};
  c=await accesso(id,k,'refresh',{precedente:c.token_cifrati,token:{...await cifra(nuovo,`conn2:${c.agenzia_id}:${id}:${c.google_sub}`),ctx:2},scadenza:new Date(Date.now()+r.expires_in*1000).toISOString()})||await accesso(id,k);
  if(!c||c.stato!=='attivo')throw new Error('ricollega');t=await decifra(c.token_cifrati,aad(c,id));
 }
 return {c,access:t.access_token};
}
async function state(id:string,data:any){const k=crypto.randomUUID();await utente(id,async q=>await q`
 INSERT INTO temacase_test.crm_sessioni_telegram(consulente_telegram_id,chiave,stato,scade_il)
 VALUES(${id}::bigint,${k}::uuid,${q.json({fase:'gm_manage',valori:data})},now()+interval '20 minutes')
 ON CONFLICT(consulente_telegram_id) DO UPDATE SET chiave=excluded.chiave,stato=excluded.stato,scade_il=excluded.scade_il`);return k;}
async function readState(id:string,k:string){return await utente(id,async q=>{const [r]=await q`SELECT stato FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${k}::uuid AND scade_il>now()`;return r?.stato.fase==='gm_manage'?r.stato.valori:null;});}
async function menu(id:string){const rows=await utente<any[]>(id,async q=>await q`SELECT a.id::text,a.nome FROM temacase_test.crm_membri_agenzia m JOIN temacase_test.crm_agenzie a ON a.id=m.agenzia_id WHERE m.consulente_telegram_id=${id}::bigint AND m.attivo ORDER BY a.nome LIMIT 20`);if(rows.length===1)return accounts(id,rows[0].id);return reply('Scegli lagenzia per i collegamenti Google.',rows.map(a=>[btn(a.nome,'ag',a.id)]));}
async function accounts(id:string,a:string,before='ffffffff-ffff-ffff-ffff-ffffffffffff'){
 const rows=await utente<any[]>(id,async q=>await q`SELECT id::text,google_email,stato FROM temacase_test.crm_google_account WHERE agenzia_id=${a}::uuid AND id<${before}::uuid ORDER BY id DESC LIMIT 6`);const page=rows.slice(0,5);
 const k=rows.length>5?await state(id,{kind:'accounts',agency:a,before:page.at(-1).id}):'';
 return reply('Account Google collegati\n\n'+(page.map((c,j)=>`${j+1}. ${c.google_email} · ${c.stato}`).join('\n')||'Nessun account.')+'\n\nCollega altro account aggiunge un collegamento: quelli esistenti restano disponibili.',[
 [btn('Collega altro account Google','a',a)],...page.map((c,j)=>[btn(`${j+1}. ${c.google_email}`,'b',c.id)]),...(k?[[btn('Altri account','p',k)]]:[]),[btn('Prove e invii CRM','q')]]);
}
async function accountMenuBase30(id:string,k:string){const c=await accesso(id,k);if(!c)return reply('Account non disponibile.');return reply(c.google_email+' · '+c.stato,[[btn('Aggiungi / aggiorna calendario','dc',k)],[btn('Aggiungi / aggiorna lista Tasks','dt',k)],[btn('Destinazioni abilitate','ls',k)],[btn('Prove e invii CRM','q')],[btn('Sincronizzazione da Google','w')],[btn('Torna agli account','m')]]);}
async function avvia(id:string,a:string){const raw=random(),verifier=random(),nonce=random();const h=Array.from(await hash(raw),x=>x.toString(16).padStart(2,'0')).join('');await utente(id,async q=>await q`SELECT temacase_test.crm_google_oauth_avvia(${a}::uuid,${h},${q.json(await cifra({verifier,nonce},`oauth:${h}`))})`);const u=new URL('https://accounts.google.com/o/oauth2/v2/auth');u.search=new URLSearchParams({client_id:env('TEMACASE_GOOGLE_CLIENT_ID'),redirect_uri:env('TEMACASE_GOOGLE_REDIRECT_URI'),response_type:'code',scope:scopes.join(' '),access_type:'offline',prompt:'consent select_account',state:raw,nonce,code_challenge:b64(await hash(verifier)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''),code_challenge_method:'S256'}).toString();return reply('Scegli laccount Google da aggiungere o ricollegare. Il link dura 10 minuti. Non inoltrarlo; se necessario aprilo nel browser di sistema.',[[{text:'Autorizza account Google',url:u.toString()}]]);}
async function discover(id:string,k:string,kind:string,page?:string){
 const {c,access}=await token(id,k);if(!c.scopes.includes(kind==='calendario'?scopes[2]:scopes[4]))return reply('Permesso mancante. Ricollega questo account autorizzando il servizio.');
 const u=new URL(kind==='calendario'?'https://www.googleapis.com/calendar/v3/users/me/calendarList':'https://tasks.googleapis.com/tasks/v1/users/@me/lists');u.searchParams.set('maxResults','8');if(kind==='calendario')u.searchParams.set('minAccessRole','writer');if(page)u.searchParams.set('pageToken',page);
 const r=await google(u.toString(),{headers:{Authorization:'Bearer '+access}});const items=(r.items||[]).map((x:any)=>({id:x.id,label:String(x.summary||x.title||'Senza nome').slice(0,300)}));const key=await state(id,{kind:'discover',conn:k,sub:c.google_sub,tipo:kind,items,next:r.nextPageToken||null});
 return reply(c.google_email+'\nScegli una destinazione da abilitare. Puoi abilitarne più di una.\n\n'+items.map((x:any,j:number)=>`${j+1}. ${x.label}`).join('\n'),[...items.map((x:any,j:number)=>[btn(`${j+1}. ${x.label}`,'s',key,String(j))]),...(r.nextPageToken?[[btn('Altri risultati','p',key)]]:[]),[btn('Torna allaccount','b',k)]]);
}
async function selectDest(id:string,k:string,j:number){const s=await readState(id,k);if(s?.kind!=='discover'||!Number.isInteger(j)||!s.items[j])return reply('Scelta scaduta. Riapri /google.');const c=await accesso(id,s.conn);if(c?.google_sub!==s.sub)return reply('Account cambiato. Riapri /google.');const x=s.items[j];const dest=await utente<string>(id,async q=>(await q`SELECT temacase_test.crm_google_v2_dest(${s.conn}::uuid,${s.tipo},${x.id},${x.label}) AS id`)[0].id);return destMenu(id,dest);}
async function destinations(id:string,k:string,before='ffffffff-ffff-ffff-ffff-ffffffffffff'){const rows=await utente<any[]>(id,async q=>await q`SELECT id::text,nome,tipo FROM temacase_test.crm_google_destinazioni WHERE connessione_id=${k}::uuid AND attiva AND id<${before}::uuid ORDER BY id DESC LIMIT 21`);const page=rows.slice(0,20);const key=rows.length>20?await state(id,{kind:'destinations',conn:k,before:page.at(-1).id}):'';return reply('Destinazioni abilitate\nScegli una destinazione per una prova. Il tuo account predefinito si configura dal menu account.',[...page.map(d=>[btn((d.tipo==='tasks'?'Task · ':'Calendario · ')+d.nome,'z',d.id)]),...(key?[[btn('Altre destinazioni','p',key)]]:[]),[btn('Torna allaccount','b',k)]]);}
async function destMenu(id:string,k:string){const d=await utente<any>(id,async q=>(await q`SELECT d.*,c.google_email FROM temacase_test.crm_google_destinazioni d JOIN temacase_test.crm_google_account c ON c.id=d.connessione_id WHERE d.id=${k}::uuid AND d.attiva`)[0]);if(!d)return reply('Destinazione non disponibile.');return reply(`${d.tipo==='tasks'?'Lista Tasks':'Calendario'}: ${d.nome}\nAccount: ${d.google_email}`,[[btn('Configura account predefinito','pa',d.connessione_id)],[btn('Crea elemento di prova','e',k)],[btn('Torna allaccount','b',d.connessione_id)],[btn('Prove e invii CRM','q')]]);}
const marker=(k:string)=>'Riferimento CRM: '+k;
const eventId=(k:string)=>'tc'+k.replace(/-/g,'');
function base(o:any){return o.tipo==='calendario'?'https://www.googleapis.com/calendar/v3/calendars/'+encodeURIComponent(o.google_dest)+'/events':'https://tasks.googleapis.com/tasks/v1/lists/'+encodeURIComponent(o.google_dest)+'/tasks';}
async function detail(id:string,k:string){const o=await invio(id,k);if(!o)return reply('Invio non disponibile.');const c=await accesso(id,o.connessione);const p=o.payload;return reply(`${o.fonte==='test'?'PROVA GOOGLE':'Invio CRM'} · ${o.stato}\n${o.dest_nome} · ${c?.google_email||''}\n${p.summary||p.title}\n`+(p.start?`${ora(p.start.dateTime)} → ${ora(p.end.dateTime)}\n`:p.due?`Giorno: ${p.due.slice(0,10)} · Google Tasks non registra lora\n`:'')+(o.errore?'Esito: '+o.errore+'\n':'')+(o.stato==='da_verificare'?'Google potrebbe aver già creato il task. Usa Verifica senza ricreare lattività.\n':'')+((o.stato==='bozza')?'Confermi la creazione di questo elemento di prova?':''),[
 ...(o.stato==='bozza'?[[btn('Conferma prova','y',k),btn('Annulla','n',k)]]:[]),
 ...(['in_coda','errore'].includes(o.stato)?[[btn('Invia / riprova','r',k)]]:[]),
 ...(['in_corso','da_verificare'].includes(o.stato)?[[btn(o.tipo==='tasks'?'Verifica senza duplicare':'Controlla invio','v',k)]]:[]),
 ...(o.stato==='sincronizzato'&&o.fonte!=='test'&&o.google_id?[[btn('Aggiorna descrizione da scheda','rp37',k)]]:[]),
 ...(o.google_url&&/^https:\/\//.test(o.google_url)?[[{text:'Apri su Google',url:o.google_url}]]:[]),
 ...(o.fonte==='test'&&o.stato==='sincronizzato'?[[btn('Elimina elemento di prova','x',k)]]:[]),[btn('Prove e invii CRM','q')]]);
}
async function sync(id:string,k:string){
 const o=await invio(id,k,'claim');if(!o)return detail(id,k);let attempted=false;
 try {
  const {c,access}=await token(id,o.connessione);const needed=o.tipo==='calendario'?scopes[3]:scopes[4];if(!c.scopes.includes(needed))throw new Error('permesso_mancante');const headers={Authorization:'Bearer '+access,'Content-Type':'application/json'};let r:any;const out37=(await descrizione37(id,o)).payload;
  if(o.tipo==='calendario'){
   const eid=eventId(o.id);try{r=await google(base(o)+'/'+eid,{headers});}catch(e){if(!(e instanceof GError)||e.status!==404)throw e;}
   if(r&&r.extendedProperties?.private?.crm_invio!==o.id)throw new Error('evento_non_corrispondente');
   if(!r){try{r=await google(base(o)+'?sendUpdates=none',{method:'POST',headers,body:JSON.stringify({...out37,id:eid,extendedProperties:{private:{crm_invio:o.id}}})});}catch(e){if(!(e instanceof GError)||e.status!==409)throw e;r=await google(base(o)+'/'+eid,{headers});if(r.extendedProperties?.private?.crm_invio!==o.id)throw new Error('evento_non_corrispondente');}}
  } else {attempted=true;r=await google(base(o),{method:'POST',headers,body:JSON.stringify({...out37,notes:(out37.notes||'')+'\n\n'+marker(o.id)})});}
  if(typeof r?.id!=='string')throw new Error('risposta_incompleta');
  await invio(id,k,'ok',{lease:o.lease,id:r.id,url:r.htmlLink||r.webViewLink||null});
 } catch(e){const uncertain=o.tipo==='tasks'&&attempted&&(!(e instanceof GError)||e.status>=500||e.status===408);const error=e instanceof GError?'google_'+e.status:e instanceof Error&&/^[a-z_]+$/.test(e.message)?e.message:'invio_non_confermato';try{await invio(id,k,uncertain?'incerto':'errore',{lease:o.lease,errore:error});}catch{}}
 return detail(id,k);
}
async function verify(id:string,k:string){const o=await invio(id,k);if(!o)return reply('Invio non disponibile.');if(o.tipo==='calendario')return sync(id,k);if(o.stato==='in_corso'&&Date.parse(o.preso_il)>Date.now()-120000)return reply('Invio ancora in corso. Attendi e poi riapri Prove e invii CRM.',[[btn('Prove e invii CRM','q')]]);if(!['in_corso','da_verificare'].includes(o.stato))return detail(id,k);const {access}=await token(id,o.connessione);let page='';const until=Date.now()+20000;
 for(let n=0;n<20;n++){const u=new URL(base(o));u.search=new URLSearchParams({maxResults:'100',showCompleted:'true',showHidden:'true',...(page?{pageToken:page}:{})}).toString();const r=await google(u.toString(),{headers:{Authorization:'Bearer '+access}});const found=(r.items||[]).find((t:any)=>String(t.notes||'').split('\n').includes(marker(o.id)));if(found){await invio(id,k,'verificato',{id:found.id,url:found.webViewLink||null});return detail(id,k);}page=r.nextPageToken||'';if(!page||Date.now()>until)break;}
 return reply('Non ho trovato un task riconoscibile entro la verifica. Non ne creo un altro, per evitare duplicati. Controlla la lista Google prima di ripetere manualmente lattività.',[[btn('Dettagli invio','o',k)]]);
}
async function chiudiAttivita(id:string,k:string,modo:string){
 if(!['completa','elimina'].includes(modo))return reply('google_non_valida');
 const o=await invio(id,k);
 if(!o||o.fonte==='test'||o.stato!=='sincronizzato'||typeof o.google_id!=='string'||!o.google_id)return reply('google_assente');
 if(modo==='completa'&&o.tipo==='calendario')return reply('google_ok');
 const {access}=await token(id,o.connessione);
 const headers={Authorization:'Bearer '+access,'Content-Type':'application/json'};
 const u=base(o)+'/'+encodeURIComponent(o.google_id);
 let item:any;
 try{item=await google(u,{headers});}
 catch(e){if(e instanceof GError&&e.status===404)return reply('google_assente');throw e;}
 const corrisponde=o.tipo==='calendario'
  ?item?.extendedProperties?.private?.crm_invio===o.id
  :String(item?.notes||'').split('\n').includes(marker(o.id));
 if(!corrisponde)return reply('google_non_corrispondente');
 if(modo==='elimina'){
  try{await google(u+(o.tipo==='calendario'?'?sendUpdates=none':''),{method:'DELETE',headers});}
  catch(e){if(!(e instanceof GError)||e.status!==404)throw e;}
  return reply('google_ok');
 }
 if(item.status==='completed')return reply('google_ok');
 await google(u,{method:'PATCH',headers,body:JSON.stringify({id:item.id,status:'completed'})});
 return reply('google_ok');
}
async function removeTest(id:string,k:string,confirmed=false){const o=await invio(id,k);if(!o||o.fonte!=='test'||o.stato!=='sincronizzato')return reply('Puoi eliminare da qui soltanto una prova sincronizzata.');if(!confirmed)return reply(`Eliminare da Google la prova “${o.payload.summary||o.payload.title}” in ${o.dest_nome}?`,[[btn('Elimina la prova','k',k),btn('Annulla','o',k)]]);
 const {access}=await token(id,o.connessione);const headers={Authorization:'Bearer '+access};const u=base(o)+'/'+encodeURIComponent(o.google_id);let item:any;try{item=await google(u,{headers});}catch(e){if(!(e instanceof GError)||e.status!==404)throw e;}
 if(item){if(o.tipo==='calendario'?item.extendedProperties?.private?.crm_invio!==o.id:!String(item.notes||'').split('\n').includes(marker(o.id)))throw new Error('prova_non_corrispondente');try{await google(u+(o.tipo==='calendario'?'?sendUpdates=none':''),{method:'DELETE',headers});}catch(e){if(!(e instanceof GError)||e.status!==404)throw e;}}
 await invio(id,k,'eliminato');return reply('Elemento di prova eliminato da Google.',[[btn('Prove e invii CRM','q')]]);
}
async function operations(id:string,before='ffffffff-ffff-ffff-ffff-ffffffffffff'){const rows=await utente<any[]>(id,async q=>await q`SELECT o.id::text,o.stato,o.fonte,d.nome FROM temacase_test.crm_google_invii o JOIN temacase_test.crm_google_destinazioni d ON d.id=o.destinazione WHERE o.id<${before}::uuid ORDER BY o.id DESC LIMIT 21`);const page=rows.slice(0,20);const k=rows.length>20?await state(id,{kind:'operations',before:page.at(-1).id}):'';return reply('Prove e invii CRM\nGli invii non confermati restano qui per riprovare o verificare senza duplicati.',[...page.map(o=>[btn(`${o.fonte} · ${o.stato} · ${o.nome}`,'o',o.id)]),...(k?[[btn('Altri invii','p',k)]]:[]),[btn('Account Google','m')]]);}
async function page(id:string,k:string){const s=await readState(id,k);if(!s)return reply('Elenco scaduto. Riapri /google.');if(s.kind==='prefs30'&&s.next)return pref30Mostra(id,s.conn,s.tipo,s.cal,s.page+1);if(s.kind==='accounts')return accounts(id,s.agency,s.before);if(s.kind==='destinations')return destinations(id,s.conn,s.before);if(s.kind==='operations')return operations(id,s.before);if(s.kind==='discover'&&s.next){const c=await accesso(id,s.conn);if(c?.google_sub===s.sub)return discover(id,s.conn,s.tipo,s.next);}return reply('Elenco scaduto.');}
async function action(id:string,p:any){if(String(p.azione).startsWith('prefs_'))return pref30Azione(id,p);if(String(p.azione).startsWith('return_'))return ritornoAzione(id,p);const k=String(p.id||'');if(!['menu','ops'].includes(p.azione)&&!uuid.test(k))throw new Error('scelta_non_valida');switch(p.azione){case 'description_preview':return anteprimaDescrizione37(id,k);case 'description_confirm':return confermaDescrizione37(id,k);case 'menu':return menu(id);case 'accounts':return accounts(id,k);case 'account':return accountMenu(id,k);case 'connect':return avvia(id,k);case 'discover':if(!['calendario','tasks'].includes(p.tipo))throw new Error('scelta_non_valida');return discover(id,k,p.tipo);case 'select':return selectDest(id,k,p.index);case 'page':return page(id,k);case 'destinations':return destinations(id,k);case 'dest':return destMenu(id,k);case 'default':{const [d]=await utente<any[]>(id,async q=>await q`SELECT connessione_id::text AS conn FROM temacase_test.crm_google_destinazioni WHERE id=${k}::uuid AND consulente_telegram_id=${id}::bigint AND attiva`);return d?pref30Mostra(id,d.conn):reply('Destinazione non disponibile.');}case 'test':return detail(id,await utente<string>(id,async q=>(await q`SELECT temacase_test.crm_google_v2_test(${k}::uuid) AS id`)[0].id));case 'confirm':await invio(id,k,'conferma');return sync(id,k);case 'cancel':await invio(id,k,'annulla');return detail(id,k);case 'sync':return sync(id,k);case 'verify':return verify(id,k);case 'op':return detail(id,k);case 'ops':return operations(id);case 'delete':return removeTest(id,k);case 'delete_confirm':return removeTest(id,k,true);case 'chiudi':return chiudiAttivita(id,k,String(p.modo||''));default:return reply('Comando aggiornato. Riapri /google.');}}
const plain=(text:string)=>new Response(text+'\n\nTorna a Telegram e invia /google.',{headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
Deno.serve(async req=>{
 let fase='inizio';
 try {
  if(req.method==='POST') {
   if(req.headers.has('X-Temacase-Sync')){
    const s=await ritornoSegreto();
    if(!await uguale(req.headers.get('X-Temacase-Sync')||'',s))return new Response('Unauthorized',{status:401});
    return Response.json(await ritornoEsegui(undefined,s));
   }
   if(!await uguale(req.headers.get('X-Temacase-Internal')||'',env('TEMACASE_TELEGRAM_WEBHOOK_SECRET')))return new Response('Unauthorized',{status:401});
   const raw=await req.text();if(raw.length>4096)return new Response('Too large',{status:413});const p=JSON.parse(raw);const id=String(p.utente||'');
   if(!/^[1-9]\d{0,18}$/.test(id)||BigInt(id)>9223372036854775807n)return new Response('Invalid user',{status:400});
   const allowed=await utente(id,async q=>(await q`SELECT temacase_test.crm_google_v2_utente() AS id`)[0]);if(!allowed)return new Response('Unauthorized',{status:401});
   fase=String(p.azione);return Response.json(await action(id,p),{headers:{'Cache-Control':'no-store'}});
  }
  if(req.method!=='GET')return new Response('Method not allowed',{status:405});
  const url=new URL(req.url),state=url.searchParams.get('state')||'';
  if(!/^[A-Za-z0-9_-]{43}$/.test(state))return plain('Apri il collegamento dal bot: /google → Collega Google.');
  fase='verifica_link';const h=Array.from(await hash(state),x=>x.toString(16).padStart(2,'0')).join('');
  const s=(await db`SELECT temacase_test.crm_google_oauth_prendi(${h}) AS r`)[0].r;
  if(!s)return plain('Link scaduto o già utilizzato. Genera un nuovo collegamento.');
  if(url.searchParams.has('error'))return plain('Autorizzazione Google non completata. Puoi riprovare dal bot.');
  const code=url.searchParams.get('code');if(!code)return plain('Codice Google mancante. Genera un nuovo collegamento.');
  const pkce=await decifra(s.pkce,`oauth:${h}`);fase='scambio_codice';
  const t=await google('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:env('TEMACASE_GOOGLE_CLIENT_ID'),client_secret:env('TEMACASE_GOOGLE_CLIENT_SECRET'),redirect_uri:env('TEMACASE_GOOGLE_REDIRECT_URI'),grant_type:'authorization_code',code,code_verifier:pkce.verifier})});
  fase='identita_google';
  const {payload}=await jwtVerify(t.id_token,jwks,{audience:env('TEMACASE_GOOGLE_CLIENT_ID'),issuer:['https://accounts.google.com','accounts.google.com'],algorithms:['RS256']});
  if(typeof payload.nonce!=='string'||!await uguale(payload.nonce,pkce.nonce)||!payload.sub||typeof payload.email!=='string'||payload.email_verified!==true||(payload.azp&&payload.azp!==env('TEMACASE_GOOGLE_CLIENT_ID')))throw new Error('identita_non_valida');
  if(typeof t.access_token!=='string'||typeof t.refresh_token!=='string'||!Number.isFinite(t.expires_in)||t.expires_in<=0)throw new Error('token_incompleto');
  const cipher={...await cifra({access_token:t.access_token,refresh_token:t.refresh_token},`conn2:${s.agenzia}:${s.utente}:${payload.sub}`),ctx:2};
  const granted=String(t.scope||'').split(/\s+/).filter(Boolean);fase='salvataggio';
  await db`SELECT temacase_test.crm_google_v2_completa(${h},${payload.sub},${payload.email},${db.json(cipher)},${granted}::text[],${new Date(Date.now()+t.expires_in*1000).toISOString()}::timestamptz)`;
  try {await fetch(`https://api.telegram.org/bot${env('TEMACASE_TELEGRAM_BOT_TOKEN')}/sendMessage`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({chat_id:s.utente,text:`Google collegato: ${payload.email}\nInvia /google per scegliere calendario e lista Tasks.`}),signal:AbortSignal.timeout(5000)});}catch{}
  return new Response(null,{status:303,headers:{Location:'https://t.me/temacase_crm_bot?start=google','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
 } catch(e) {
  const msg=e instanceof Error?e.message:'';
  const codice=e instanceof GError?'google_'+e.status:/^(config_[A-Z_]+|config_chiave|ricollega|token_incompleto|identita_non_valida|prova_non_corrispondente|scelta_non_valida)$/.test(msg)?msg:'errore';
  console.error('temacase_google_multi',fase,codice);
  if(req.method==='POST')return Response.json(reply(`Operazione Google non completata (${codice}). Riapri /google.`,[[btn('Prove e invii CRM','q')]]));
  return plain(`Collegamento non completato (${codice}). Genera un nuovo link dal bot.`);
 }
});
// TEMACASE_GOOGLE_RETURN_V27
async function ritornoSegreto(){
 return Array.from(await hash('temacase-google-return-v27:'+env('TEMACASE_TELEGRAM_WEBHOOK_SECRET')),x=>x.toString(16).padStart(2,'0')).join('');
}
async function ritornoUno(o:any){
 const id=o.utente;let p:any;
 try {
  const {access}=await token(id,o.connessione);
  const h={Authorization:'Bearer '+access};
  try {
   p=await google(base(o)+'/'+encodeURIComponent(o.google_id),{headers:h});
  }
  catch(e){
   if(!(e instanceof GError)||![404,410].includes(e.status))throw e;
   const container=o.tipo==='tasks'
    ?'https://tasks.googleapis.com/tasks/v1/users/@me/lists/'+encodeURIComponent(o.google_dest)
    :'https://www.googleapis.com/calendar/v3/users/me/calendarList/'+encodeURIComponent(o.google_dest);
   await google(container,{headers:h});
   p={mancante:true};
  }
  if(!p||typeof p!=='object')throw new Error('risposta_non_valida');
 }
 catch(e){
  p={errore:e instanceof GError?'google_'+e.status:'lettura_non_confermata'};
 }
 return await utente<string>(id,async q=>(await q`
 SELECT temacase_test.crm27_applica(${o.id}::uuid,${o.lease}::uuid,${q.json(p)}) AS r`)[0].r);
}
async function ritornoEsegui(id?:string,segreto?:string){
 const esiti:Record<string,number>={};
 const fino=Date.now()+20000;
 for(let n=0;n<10&&Date.now()<fino;n++){
  const prendi=async(q:any)=>(await q`
   SELECT temacase_test.crm27_prossimo(${segreto||null}) AS r`)[0].r;
  const o=id?await utente<any>(id,prendi):await prendi(db);
  if(!o)break;
  let esito:string;
  try{esito=await ritornoUno(o);}
  catch{esito='errore';}
  esiti[esito]=(esiti[esito]||0)+1;
 }
 return esiti;
}
async function ritornoStato(id:string){
 const rows=await utente<any[]>(id,async q=>{await q`SELECT set_config('temacase.includi_archiviate','true',true),set_config('temacase.includi_cestino','true',true)`;return q`
 SELECT x.invio::text,x.verificato_il,x.applicato_il,x.conflitto,x.errore,
 o.fonte,d.nome,c.google_email,
 CASE WHEN o.fonte='personale' THEN (
  SELECT p.stato FROM temacase_test.crm_attivita_personali p WHERE p.id=o.fonte_id AND p.consulente_telegram_id=o.consulente_telegram_id
 ) WHEN o.fonte='notizia' THEN (
  SELECT f.stato FROM temacase_test.followup_acquisizione f
  JOIN temacase_test.notizie_acquisizione n ON n.id=f.notizia_id
  WHERE f.id=o.fonte_id AND n.consulente_telegram_id=o.consulente_telegram_id
 ) WHEN o.fonte='followup' THEN (
  SELECT a.stato FROM temacase_test.crm_attivita_operative a
  WHERE a.id=o.fonte_id
 ) ELSE (
  SELECT v.stato FROM temacase_test.visite v WHERE v.id=o.fonte_id
 ) END AS stato_crm,
 coalesce(x.remoto->>'title',o.payload->>'summary',o.payload->>'title') AS titolo
 FROM temacase_test.crm_google_ritorni x
 JOIN temacase_test.crm_google_invii o ON o.id=x.invio
 JOIN temacase_test.crm_google_destinazioni d ON d.id=o.destinazione
 JOIN temacase_test.crm_google_account c ON c.id=d.connessione_id
 ORDER BY x.conflitto DESC,(x.errore IS NOT NULL) DESC,
 x.verificato_il DESC NULLS FIRST LIMIT 15`;});
 return reply('Ritorno Google → CRM\n'+(rows.length?rows.map((r,j)=>
 `${j+1}. ${r.titolo||r.fonte}\n${r.nome} · ${r.google_email}\nStato CRM: ${r.stato_crm||'non disponibile'}\n`+
 (r.conflitto
  ?'CONFLITTO: modifiche anche nel CRM. Nessuna sovrascrittura.'
  :r.errore
   ?'Da controllare: '+r.errore
   :r.verificato_il
    ?'Controllato: '+ora(r.verificato_il)
    :'In attesa del primo controllo.')+
 (r.applicato_il?'\nUltimo aggiornamento CRM: '+ora(r.applicato_il):'')
 ).join('\n\n'):
 'Nessuna attività reale collegata. Le prove Google sono escluse.'),[
 [btn('Aggiorna da Google adesso','h')],
 [btn('Attiva controllo automatico','j')],
 ...rows.filter(r=>r.conflitto).map(r=>[
  btn('Risolvi conflitto · '+String(r.titolo||r.fonte).slice(0,30),'u',r.invio)
 ]),
 [btn('Torna agli account','m')]
 ]);
}
async function ritornoAzione(id:string,p:any){
 if(p.azione==='return_enable'){
  const s=await ritornoSegreto();
  await utente(id,async q=>await q`
   SELECT temacase_test.crm27_attiva(${s})`);
  const r=await ritornoStato(id);
  return {...r,text:'Controllo automatico attivato: un lotto ogni minuto.\n'+r.text};
 }
 if(p.azione==='return_pull'){
  const e=await ritornoEsegui(id);
  const r=await ritornoStato(id);
  return {...r,text:'Controllo eseguito. '+
   Object.entries(e).map(([k,v])=>k+': '+v).join(', ')+'\n\n'+r.text};
 }
 if(p.azione==='return_accept'){
  if(!uuid.test(String(p.id||'')))return reply('Scelta non valida.');
  return reply(
   'Confermi di usare la versione Google di questa attività? Le modifiche locali in conflitto saranno sostituite nei campi sincronizzati. Contatto, immobile e descrizione CRM originale restano conservati.',
   [
    [btn('Conferma: usa versione Google','v27',p.id)],
    [btn('Annulla','w')]
   ]
  );
 }
 if(p.azione==='return_accept_confirm'){
  if(!uuid.test(String(p.id||'')))return reply('Scelta non valida.');
  await utente(id,async q=>await q`
   SELECT temacase_test.crm27_accetta(${p.id}::uuid)`);
  await ritornoEsegui(id);
  return ritornoStato(id);
 }
 return ritornoStato(id);
}
// TEMACASE_GOOGLE_PREFERITI_V29

// TEMACASE_GOOGLE_ACCOUNT_V30
async function accountMenu(id:string,k:string){
 const r=await accountMenuBase30(id,k);const c=await accesso(id,k);
 if(!c)return r;
 const p=await utente<any>(id,async q=>(await q`
 SELECT d.nome AS calendario,t.nome AS tasks
 FROM temacase_test.crm_google_account_preferito p
 JOIN temacase_test.crm_google_destinazioni d ON d.id=p.calendario
 JOIN temacase_test.crm_google_destinazioni t ON t.id=p.tasks
 WHERE p.consulente_telegram_id=${id}::bigint AND p.account_id=${k}::uuid`)[0]);
 return {...r,text:r.text+(p?`\n\nACCOUNT PREDEFINITO\nEventi: ${p.calendario}\nTasks: ${p.tasks}`:''),
 inline_keyboard:[[btn(p?'Modifica account predefinito':'Usa questo account come predefinito','pa',k)],...r.inline_keyboard]};
}
async function pref30Mostra(id:string,k:string,tipo='calendario',cal?:string,page=0){
 const c=await accesso(id,k);if(!c||c.stato!=='attivo')return reply('Account non disponibile. Ricollegalo da /google.');
 const rows=await utente<any[]>(id,async q=>await q`
 SELECT id::text,nome FROM temacase_test.crm_google_destinazioni
 WHERE connessione_id=${k}::uuid AND consulente_telegram_id=${id}::bigint
 AND tipo=${tipo} AND attiva ORDER BY nome,id LIMIT 9 OFFSET ${page*8}`);
 if(!rows.length)return reply(`Account: ${c.google_email}\nPrima abilita ${tipo==='calendario'?'un calendario':'una lista Tasks'} di questo account, poi ripeti la configurazione.`,
 [[btn(tipo==='calendario'?'Aggiungi calendario':'Aggiungi lista Tasks',tipo==='calendario'?'dc':'dt',k)],[btn('Torna al tuo account','b',k)]]);
 const items=rows.slice(0,8);const key=await state(id,{kind:'prefs30',conn:k,sub:c.google_sub,tipo,cal,page,next:rows.length>8,items});
 return reply(`Account predefinito: ${c.google_email}\n${tipo==='calendario'?'1/2 - Scegli il calendario per eventi e visite.':'2/2 - Scegli la lista Tasks.'}\nLa scelta verra salvata insieme alla conferma finale.\n\n`+
 items.map((x,j)=>`${j+1}. ${x.nome}`).join('\n'),[
 ...items.map((x,j)=>[btn(`${j+1}. ${x.nome}`,tipo==='calendario'?'pc':'pt',key,String(j))]),
 ...(rows.length>8?[[btn('Altri risultati','p',key)]]:[]),[btn('Annulla configurazione','px',key)]]);
}
async function pref30Azione(id:string,p:any){
 const k=String(p.id||'');if(!uuid.test(k))return reply('Scelta scaduta. Riapri /google.');
 if(p.azione==='prefs_account')return pref30Mostra(id,k);
 const s=await readState(id,k);if(!s||!['prefs30','prefs30_confirm'].includes(s.kind))return reply('Configurazione scaduta. Riapri /google.');
 const c=await accesso(id,s.conn);if(!c||c.google_sub!==s.sub||c.stato!=='attivo')return reply('Account non disponibile. Riapri /google.');
 if(p.azione==='prefs_cancel'){
  await utente(id,async q=>await q`DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${k}::uuid`);
  return accountMenu(id,s.conn);
 }
 if(p.azione==='prefs_confirm'&&s.kind==='prefs30_confirm'){
  const r=await utente<any>(id,async q=>(await q`SELECT temacase_test.crm30_account_preferito(${s.conn}::uuid,${s.cal}::uuid,${s.task}::uuid) AS r`)[0].r);
  await utente(id,async q=>await q`DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${k}::uuid`);
  return reply(`Account predefinito impostato: ${r.email}\nEventi e visite: ${r.calendario}\nTasks: ${r.tasks}\n\nNei nuovi riepiloghi troverai questa destinazione e il pulsante Cambia destinazione.`,[[btn('Torna al tuo account','b',s.conn)]]);
 }
 if(s.kind!=='prefs30'||!Number.isInteger(p.index)||!s.items?.[p.index])return reply('Scelta scaduta. Riapri /google.');
 const x=s.items[p.index];
 const [d]=await utente<any[]>(id,async q=>await q`SELECT id::text,nome FROM temacase_test.crm_google_destinazioni
 WHERE id=${x.id}::uuid AND connessione_id=${s.conn}::uuid AND consulente_telegram_id=${id}::bigint AND attiva AND tipo=${s.tipo}`);
 if(!d)return reply('Destinazione non disponibile. Ripeti la configurazione.');
 if(p.azione==='prefs_calendar'&&s.tipo==='calendario')return pref30Mostra(id,s.conn,'tasks',d.id);
 if(p.azione==='prefs_tasks'&&s.tipo==='tasks'){
  const [cal]=await utente<any[]>(id,async q=>await q`SELECT nome FROM temacase_test.crm_google_destinazioni
   WHERE id=${s.cal}::uuid AND connessione_id=${s.conn}::uuid AND attiva AND tipo='calendario'`);
  if(!cal)return reply('Calendario non disponibile. Ripeti la configurazione.');
  const key=await state(id,{kind:'prefs30_confirm',conn:s.conn,sub:s.sub,cal:s.cal,task:d.id});
  return reply(`Conferma account predefinito\n${c.google_email}\nEventi e visite: ${cal.nome}\nTasks: ${d.nome}`,
   [[btn('Conferma account predefinito','pf',key)],[btn('Annulla configurazione','px',key)]]);
 }
 return reply('Scelta non valida. Ripeti la configurazione.');
}

// TEMACASE_AI_INTERPRETE_V31

// TEMACASE_NOTIZIE_IMMOBILI_V32

// TEMACASE_DESCRIZIONI_GOOGLE_V37
const inizio37='--- INIZIO SCHEDA TEMACASE ---',fine37='--- FINE SCHEDA TEMACASE ---';
const html37=(s:string)=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
function telefoni37(line:string){return /telefono/i.test(line.split(':',1)[0])?[...line.matchAll(/\+?\d[\d .()/-]{5,}\d/g)].map(m=>({testo:m[0],numero:m[0].replace(/[^\d+]/g,'').replace(/^00/,'+')})):[];}
function testoMobile37(s:string){return s.split('\n').map(line=>line+telefoni37(line).map(t=>'\nChiama: tel:'+t.numero).join('')+(/email/i.test(line.split(':',1)[0])?[...line.matchAll(/[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi)].map(m=>'\nScrivi: mailto:'+m[0]).join(''):'')).join('\n');}
function calendario37(s:string){
 return s.split('\n').map(line=>{
  const tokens:{start:number;end:number;value:string}[]=[];
  const add=(raw:string,href:string,start:number)=>tokens.push({start,end:start+raw.length,value:'<a href="'+html37(href)+'">'+html37(raw)+'</a>'});
  for(const m of line.matchAll(/https:\/\/[^\s<>"']+/g))add(m[0],m[0],m.index!);
  for(const m of line.matchAll(/[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi))add(m[0],'mailto:'+encodeURIComponent(m[0]),m.index!);
  for(const t of telefoni37(line)){const at=line.indexOf(t.testo);add(t.testo,'tel:'+t.numero,at);}
  let pos=0,out='';for(const token of tokens.sort((a,b)=>a.start-b.start)){if(token.start<pos)continue;out+=html37(line.slice(pos,token.start))+token.value;pos=token.end;}return out+html37(line.slice(pos));
 }).join('<br>');
}
async function descrizione37(id:string,o:any){
 if(o.fonte==='test')return {payload:o.payload,testo:o.payload.description||o.payload.notes||''};
 const ctx=await utente<any>(id,async q=>(await q`SELECT temacase_test.crm37_testo(${o.id}::uuid) AS r`)[0].r);
 if(!ctx||typeof ctx.testo!=='string')throw new Error('scheda_non_disponibile');
 const full=(o.tipo==='tasks'?testoMobile37(ctx.testo):ctx.testo).trim();const link=ctx.link?'\n\nScheda completa in Telegram: '+ctx.link:'';
 // Tasks notes max 8192; reserve marker and block delimiters. Never cut user notes.
 const max=o.tipo==='tasks'?7600:60000;
 let body=full;const available=max-link.length-inizio37.length-fine37.length-8;
 if(body.length>available)body=body.slice(0,Math.max(0,available-125))+'\n[Descrizione abbreviata per il limite Google. Apri la scheda completa dal link.]';
 const testo=inizio37+'\n'+body+link+'\n'+fine37;
 const payload={...o.payload,[o.tipo==='tasks'?'notes':'description']:o.tipo==='tasks'?testo:calendario37(testo)};
 return {payload,testo};
}
async function remoto37(id:string,o:any){
 const {access}=await token(id,o.connessione),headers={Authorization:'Bearer '+access,'Content-Type':'application/json'};
 const url=base(o)+'/'+encodeURIComponent(o.google_id);
 const r=await fetch(url,{headers,signal:AbortSignal.timeout(15000)});if(!r.ok)throw new GError(r.status);
 const item=await r.json();const etag=r.headers.get('etag')||item.etag;
 if(item.id!==o.google_id||(o.tipo==='calendario'?item.extendedProperties?.private?.crm_invio!==o.id:!String(item.notes||'').split('\n').includes(marker(o.id))))throw new Error('elemento_non_corrispondente');
 if(item.deleted||item.status==='cancelled')throw new Error('elemento_eliminato');
 if(typeof etag!=='string'||!etag)throw new Error('versione_google_non_disponibile');
 return {item,etag,url,headers};
}
async function anteprimaDescrizione37(id:string,k:string){
 const o=await invio(id,k);if(!o||o.stato!=='sincronizzato'||!o.google_id||o.fonte==='test')return reply('Elemento non disponibile per aggiornare la descrizione.');
 const generated=await descrizione37(id,o),remote=await remoto37(id,o);
 const key=await state(id,{kind:'description37',op:k,google_id:o.google_id,etag:remote.etag,body:generated.payload[o.tipo==='tasks'?'notes':'description'],tipo:o.tipo});
 return reply('Aggiorna la descrizione dell’elemento Google esistente con i dati compilati della scheda e i recapiti. Le note esterne alla sezione Temacase restano conservate. Stato, titolo e data non cambiano.\n\nAnteprima'+(generated.testo.length>2400?' (prime righe)':'')+':\n'+generated.testo.slice(0,2400),[[btn('Conferma aggiorna descrizione','rc37',key)],[btn('Annulla','o',k)]]);
}
async function confermaDescrizione37(id:string,k:string){
 const s=await readState(id,k);if(s?.kind!=='description37')return reply('Conferma scaduta. Riapri i dettagli dell’invio.');
 const o=await invio(id,s.op);if(!o||o.stato!=='sincronizzato'||o.google_id!==s.google_id||o.tipo!==s.tipo)return reply('Collegamento Google cambiato. Riapri l’anteprima.');
 // Recheck CRM permission as well as Google ownership at final confirmation.
 await descrizione37(id,o);
 const r=await remoto37(id,o);if(r.etag!==s.etag)return reply('L’elemento e stato modificato su Google. Riapri l’anteprima per aggiornare i dati senza perdere modifiche.',[[btn('Riapri anteprima','rp37',o.id)]]);
 const campo=o.tipo==='tasks'?'notes':'description',old=String(r.item[campo]||'');
 let extra=old;const start=extra.indexOf(inizio37),end=extra.indexOf(fine37,start);
 if(start>=0&&end>=start)extra=extra.slice(0,start)+extra.slice(end+fine37.length);
 if(o.tipo==='tasks')extra=extra.split('\n').filter(line=>line!==marker(o.id)).join('\n');
 extra=extra.trim();const merged=(extra?extra+(o.tipo==='tasks'?'\n\n':'<br><br>'):'')+s.body+(o.tipo==='tasks'?'\n\n'+marker(o.id):'');
 if(o.tipo==='tasks'&&merged.length>8192)return reply('Le note esistenti e la scheda superano il limite di Google Tasks. Nessuna modifica eseguita: abbrevia le note su Google e riapri l’anteprima.');
 await google(r.url+(o.tipo==='calendario'?'?sendUpdates=none':''),{method:'PATCH',headers:{...r.headers,'If-Match':r.etag},body:JSON.stringify({[campo]:merged})});
 await utente(id,async q=>await q`DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${k}::uuid`);
 return reply('Descrizione aggiornata sull’elemento Google esistente.',[[btn('Dettagli invio','o',o.id)]]);
}
