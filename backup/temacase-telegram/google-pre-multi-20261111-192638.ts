// TEMACASE_GOOGLE_AUTH_V1
import postgres from 'npm:postgres@3.4.7';
import {createRemoteJWKSet,jwtVerify} from 'npm:jose@6.1.0';
const env=(k:string)=>{const v=Deno.env.get(k);if(!v)throw new Error('config_'+k);return v;};
const db=postgres(env('TEMACASE_DATABASE_URL'),{max:1,connect_timeout:5,idle_timeout:10});
const enc=new TextEncoder();
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
async function accesso(id:string,a:string,azione='leggi',p:any={}){return await utente(id,async q=>(await q`SELECT temacase_test.crm_google_accesso(${a}::uuid,${azione},${q.json(p)}) AS r`)[0].r);}
const bottone=(text:string,callback_data:string)=>({text:text.slice(0,60),callback_data});
const risposta=(text:string,inline_keyboard:any[][]=[])=>({text,inline_keyboard});
async function google(url:string,init:RequestInit={}){
 const r=await fetch(url,{...init,signal:AbortSignal.timeout(15000)});const j=await r.json();
 if(!r.ok){const code=typeof j.error==='string'&&/^[a-z_]+$/.test(j.error)?j.error:String(r.status);throw new Error('google_'+code);}
 return j;
}
async function token(id:string,a:string){
 let c=await accesso(id,a);if(!c||c.stato!=='attivo')throw new Error('ricollega');
 let t=await decifra(c.token_cifrati,`conn:${a}:${id}`);
 if(Date.parse(c.accesso_scade_il)<=Date.now()+60000){
  let r:any;
  try {r=await google('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:env('TEMACASE_GOOGLE_CLIENT_ID'),client_secret:env('TEMACASE_GOOGLE_CLIENT_SECRET'),grant_type:'refresh_token',refresh_token:t.refresh_token})});}
  catch(e){if(e instanceof Error&&e.message==='google_invalid_grant')await accesso(id,a,'invalida',{sub:c.google_sub,precedente:c.token_cifrati});throw e;}
  if(typeof r.access_token!=='string'||!Number.isFinite(r.expires_in)||r.expires_in<=0)throw new Error('google_token');
  const nuovo={access_token:r.access_token,refresh_token:r.refresh_token||t.refresh_token};
  const aggiornato=await accesso(id,a,'refresh',{sub:c.google_sub,precedente:c.token_cifrati,token:await cifra(nuovo,`conn:${a}:${id}`),scadenza:new Date(Date.now()+r.expires_in*1000).toISOString()});
  c=aggiornato||await accesso(id,a);
  if(!c||c.stato!=='attivo')throw new Error('ricollega');
  t=await decifra(c.token_cifrati,`conn:${a}:${id}`);
 }
 return {c,access:t.access_token};
}
async function menu(id:string){
 const rows=await utente<any[]>(id,async q=>await q`
 SELECT a.id::text,a.nome,c.google_email,c.stato,c.calendario_id,c.lista_task_id
 FROM temacase_test.crm_membri_agenzia m JOIN temacase_test.crm_agenzie a ON a.id=m.agenzia_id
 LEFT JOIN temacase_test.crm_google_connessioni c ON c.agenzia_id=m.agenzia_id AND c.consulente_telegram_id=${id}::bigint
 WHERE m.consulente_telegram_id=${id}::bigint AND m.attivo ORDER BY a.nome LIMIT 20`);
 if(!rows.length)return risposta('Profilo senza agenzia attiva.');
 return risposta('Collegamenti Google\n\n'+rows.map(c=>`${String(c.nome).slice(0,100)}\n${c.google_email||'Google non collegato'}${c.stato?' · '+c.stato:''}\nCalendario: ${c.calendario_id?'selezionato':'da scegliere'} · Tasks: ${c.lista_task_id?'selezionata':'da scegliere'}`).join('\n\n'),
 rows.flatMap(c=>[[bottone(`${c.google_email?'Ricollega':'Collega'} Google · ${c.nome}`,`t:gg:c:${c.id}`)],...(c.stato==='attivo'?[[bottone('Scegli calendario',`t:gg:l:${c.id}`),bottone('Scegli lista Tasks',`t:gg:t:${c.id}`)]]:[])]));
}
async function avvia(id:string,a:string){
 const state=random(),verifier=random(),nonce=random();const h=Array.from(await hash(state),x=>x.toString(16).padStart(2,'0')).join('');
 const p=await cifra({verifier,nonce},`oauth:${h}`);
 await utente(id,async q=>await q`SELECT temacase_test.crm_google_oauth_avvia(${a}::uuid,${h},${q.json(p)})`);
 const url=new URL('https://accounts.google.com/o/oauth2/v2/auth');
 url.search=new URLSearchParams({client_id:env('TEMACASE_GOOGLE_CLIENT_ID'),redirect_uri:env('TEMACASE_GOOGLE_REDIRECT_URI'),response_type:'code',scope:scopes.join(' '),access_type:'offline',prompt:'consent select_account',state,nonce,code_challenge:b64(await hash(verifier)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''),code_challenge_method:'S256'}).toString();
 return risposta('Premi il pulsante e autorizza Google. Il link dura 10 minuti e sostituisce eventuali link precedenti. Se Google non permette l’accesso nel browser interno di Telegram, aprilo nel browser del telefono.\nNon inoltrare il link.',[[{text:'Autorizza Google',url:url.toString()}]]);
}
async function scegli(id:string,a:string,kind:string,page?:string){
 const {c,access}=await token(id,a);const scope=kind==='calendario'?scopes[2]:scopes[4];
 if(!c.scopes.includes(scope))return risposta('Permesso mancante per questa funzione. Usa /google e Ricollega Google, autorizzando il servizio.');
 const url=new URL(kind==='calendario'?'https://www.googleapis.com/calendar/v3/users/me/calendarList':'https://tasks.googleapis.com/tasks/v1/users/@me/lists');
 url.searchParams.set('maxResults','20');if(kind==='calendario')url.searchParams.set('minAccessRole','writer');if(page)url.searchParams.set('pageToken',page);
 const r=await google(url.toString(),{headers:{Authorization:'Bearer '+access}});
 const items=(r.items||[]).map((v:any)=>({id:v.id,label:String(v.summary||v.title||'Senza nome')}));const key=crypto.randomUUID();
 await utente(id,async q=>await q`
 INSERT INTO temacase_test.crm_sessioni_telegram(consulente_telegram_id,chiave,stato,scade_il)
 VALUES(${id}::bigint,${key}::uuid,${q.json({fase:'gg_scelta',valori:{agenzia:a,sub:c.google_sub,kind,items,next:r.nextPageToken||null}})},now()+interval '20 minutes')
 ON CONFLICT(consulente_telegram_id) DO UPDATE SET chiave=excluded.chiave,stato=excluded.stato,scade_il=excluded.scade_il`);
 return risposta(kind==='calendario'?'Scegli il calendario da usare per gli appuntamenti del CRM:':'Scegli la tua lista Google Tasks:',[
 ...items.map((v:any,j:number)=>[bottone(v.label,`t:gg:s:${key}:${j}`)]),
 ...(r.nextPageToken?[[bottone('Altri risultati',`t:gg:p:${key}`)]]:[]),[bottone('Torna a Google','t:gg:m')]]);
}
async function scelta(id:string,key:string,index?:number){
 return await utente(id,async q=>{
  const [r]=await q`SELECT stato FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${key}::uuid AND scade_il>now() FOR UPDATE`;
  if(r?.stato.fase!=='gg_scelta')return risposta('Scelta scaduta. Riapri /google.');
  const s=r.stato.valori;const item=s.items[index!];
  if(!Number.isInteger(index)||!item)return risposta('Scelta non valida.');
  await q`SELECT temacase_test.crm_google_accesso(${s.agenzia}::uuid,${s.kind},${q.json({sub:s.sub,id:item.id})})`;
  await q`DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${key}::uuid`;
  return risposta(`${s.kind==='calendario'?'Calendario':'Lista Tasks'} selezionato: ${item.label}\nLa sincronizzazione automatica delle attività CRM verrà attivata nel prossimo passaggio.`,[[bottone('Torna a Google','t:gg:m')]]);
 });
}
const html=(text:string)=>new Response(text+'\n\nTorna a Telegram e invia /google.',{headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'}});
Deno.serve(async req=>{
 let fase='inizio';
 try {
  if(req.method==='POST'){
   if(!await uguale(req.headers.get('X-Temacase-Internal')||'',env('TEMACASE_TELEGRAM_WEBHOOK_SECRET')))return new Response('Unauthorized',{status:401});
   if(Number(req.headers.get('content-length')||0)>4096)return new Response('Too large',{status:413});
   const raw=await req.text();if(raw.length>4096)return new Response('Too large',{status:413});const p=JSON.parse(raw);
   const id=String(p.utente||'');if(!/^[1-9]\d{0,18}$/.test(id)||BigInt(id)>9223372036854775807n)return new Response('Invalid user',{status:400});
   const valido=await utente(id,async q=>(await q`SELECT telegram_user_id FROM temacase_test.consulenti_telegram WHERE telegram_user_id=${id}::bigint AND attivo`)[0]);
   if(!valido)return new Response('Unauthorized',{status:401});
   const a=String(p.agenzia||'');let out:any;fase=String(p.azione);
   if(p.azione==='menu')out=await menu(id);
   else if(['connect','calendario','tasks'].includes(p.azione)&&/^[a-f0-9-]{36}$/.test(a))out=p.azione==='connect'?await avvia(id,a):await scegli(id,a,p.azione);
   else if(['pick','page'].includes(p.azione)&&/^[a-f0-9-]{36}$/.test(p.key||'')){
    if(p.azione==='pick')out=await scelta(id,p.key,p.index);
    else {
     const se=await utente(id,async q=>(await q`SELECT stato FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=${id}::bigint AND chiave=${p.key}::uuid AND scade_il>now()`)[0]);
     const s=se?.stato.fase==='gg_scelta'?se.stato.valori:null;
     const con=s?await accesso(id,s.agenzia):null;
     out=s?.next&&con?.google_sub===s.sub?await scegli(id,s.agenzia,s.kind,s.next):risposta('Scelta scaduta. Riapri /google.');
    }
   } else return new Response('Invalid action',{status:400});
   return Response.json(out,{headers:{'Cache-Control':'no-store'}});
  }
  if(req.method!=='GET')return new Response('Method not allowed',{status:405});
  const url=new URL(req.url),state=url.searchParams.get('state')||'';
  if(!/^[A-Za-z0-9_-]{43}$/.test(state))return html('Apri il collegamento dal bot: /google → Collega Google.');
  fase='verifica_link';const h=Array.from(await hash(state),x=>x.toString(16).padStart(2,'0')).join('');
  const s=(await db`SELECT temacase_test.crm_google_oauth_prendi(${h}) AS r`)[0].r;
  if(!s)return html('Link scaduto o già utilizzato. Genera un nuovo collegamento.');
  if(url.searchParams.has('error'))return html('Autorizzazione Google non completata. Puoi riprovare dal bot.');
  const code=url.searchParams.get('code');if(!code)return html('Codice Google mancante. Genera un nuovo collegamento.');
  const pkce=await decifra(s.pkce,`oauth:${h}`);fase='scambio_codice';
  const t=await google('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:env('TEMACASE_GOOGLE_CLIENT_ID'),client_secret:env('TEMACASE_GOOGLE_CLIENT_SECRET'),redirect_uri:env('TEMACASE_GOOGLE_REDIRECT_URI'),grant_type:'authorization_code',code,code_verifier:pkce.verifier})});
  fase='identita_google';
  const {payload}=await jwtVerify(t.id_token,jwks,{audience:env('TEMACASE_GOOGLE_CLIENT_ID'),issuer:['https://accounts.google.com','accounts.google.com'],algorithms:['RS256']});
  if(typeof payload.nonce!=='string'||!await uguale(payload.nonce,pkce.nonce)||!payload.sub||typeof payload.email!=='string'||payload.email_verified!==true||(payload.azp&&payload.azp!==env('TEMACASE_GOOGLE_CLIENT_ID')))throw new Error('identita_non_valida');
  if(typeof t.access_token!=='string'||typeof t.refresh_token!=='string'||!Number.isFinite(t.expires_in)||t.expires_in<=0)throw new Error('token_incompleto');
  const cipher=await cifra({access_token:t.access_token,refresh_token:t.refresh_token},`conn:${s.agenzia}:${s.utente}`);
  const granted=String(t.scope||'').split(/\s+/).filter(Boolean);fase='salvataggio';
  await db`SELECT temacase_test.crm_google_oauth_completa(${h},${payload.sub},${payload.email},${db.json(cipher)},${granted}::text[],${new Date(Date.now()+t.expires_in*1000).toISOString()}::timestamptz)`;
  try {await fetch(`https://api.telegram.org/bot${env('TEMACASE_TELEGRAM_BOT_TOKEN')}/sendMessage`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({chat_id:s.utente,text:`Google collegato: ${payload.email}\nInvia /google per scegliere calendario e lista Tasks.`}),signal:AbortSignal.timeout(5000)});}catch{}
  return new Response(null,{status:303,headers:{Location:'https://t.me/temacase_crm_bot?start=google','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
 } catch(e){
  const msg=e instanceof Error?e.message:'';
  const codice=/^(google_[a-z0-9_]+|config_[A-Z_]+|config_chiave|ricollega|token_incompleto|identita_non_valida)$/.test(msg)?msg:'errore';
  console.error('temacase_google',fase,codice);
  if(req.method==='POST')return Response.json(risposta(`Operazione Google non completata (${codice}). Riapri /google. Se si ripete, comunicami questo codice.`));
  return html(`Collegamento non completato (${codice}). Genera un nuovo link dal bot.`);
 }
});