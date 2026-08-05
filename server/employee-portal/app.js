(() => {
  'use strict';
  const API=location.origin,TOKEN_KEY='wesi_portal_token',USER_KEY='wesi_portal_user',TIMEOUT=8000;
  const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)];
  const state={token:sessionStorage.getItem(TOKEN_KEY)||'',user:json(sessionStorage.getItem(USER_KEY)),manifest:null};
  const els={boot:$('#boot'),app:$('#app'),loginView:$('#loginView'),dashboardView:$('#dashboardView'),loginForm:$('#loginForm'),identity:$('#identity'),password:$('#password'),passwordToggle:$('#passwordToggle'),loginButton:$('#loginButton'),loginMessage:$('#loginMessage'),logoutButton:$('#logoutButton'),employeeName:$('#employeeName'),heroVersion:$('#heroVersion'),heroBuild:$('#heroBuild'),releaseVersion:$('#releaseVersion'),releaseBuild:$('#releaseBuild'),publishedAt:$('#publishedAt'),changelog:$('#changelog p'),windowsSize:$('#windowsSize'),androidSize:$('#androidSize'),footerStatus:$('#footerStatus'),toastStack:$('#toastStack'),runner:$('#runnerSegment'),runnerTail:$('#runnerTail')};

  function json(v){try{return v?JSON.parse(v):null}catch(_){return null}}
  function clearSession(){state.token='';state.user=null;state.manifest=null;sessionStorage.removeItem(TOKEN_KEY);sessionStorage.removeItem(USER_KEY)}
  function headers(extra={}){return state.token?{...extra,Authorization:state.token}:extra}
  async function fetchTimeout(url,options={},timeout=TIMEOUT){const c=new AbortController(),t=setTimeout(()=>c.abort(),timeout);try{return await fetch(url,{...options,signal:c.signal})}finally{clearTimeout(t)}}
  async function request(path,options={},timeout=TIMEOUT){const r=await fetchTimeout(`${API}${path}`,{cache:'no-store',...options,headers:headers(options.headers||{})},timeout);let body=null;try{body=await r.json()}catch(_){}if(!r.ok){const e=new Error(body?.message||`HTTP ${r.status}`);e.status=r.status;throw e}return body}
  function showView(next){$('.view.active')?.classList.remove('active');next?.classList.add('active');scrollTo(0,0)}
  function showLogin(){els.logoutButton?.classList.add('hidden');showView(els.loginView)}
  function setLoading(btn,on,text=''){if(!btn)return;btn.dataset.label||=$('span',btn)?.textContent||'';btn.disabled=on;const s=$('span',btn);if(s)s.textContent=on?text:btn.dataset.label}
  function nameOf(r){return(r?.name||r?.username||r?.email||'сотрудник').replace(/@wesi\.local$/i,'')}

  async function authCandidate(identity,password){const r=await fetchTimeout(`${API}/api/collections/users/auth-with-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({identity,password}),cache:'no-store'});const body=await r.json().catch(()=>null);return{r,body}}
  async function signIn(identity,password){
    const raw=identity.trim(),candidates=[raw];if(raw&&!raw.includes('@'))candidates.push(`${raw.toLowerCase()}@wesi.local`);
    for(const candidate of [...new Set(candidates)]){const {r,body}=await authCandidate(candidate,password);if(r.ok&&body?.token){state.token=body.token;state.user=body.record||{};sessionStorage.setItem(TOKEN_KEY,state.token);sessionStorage.setItem(USER_KEY,JSON.stringify(state.user));return}}
    const e=new Error('Неверный логин или пароль');e.status=401;throw e;
  }
  async function verifySession(){if(!state.token)return false;try{const body=await request('/api/collections/users/auth-refresh',{method:'POST'},2400);state.token=body.token||state.token;state.user=body.record||state.user;sessionStorage.setItem(TOKEN_KEY,state.token);sessionStorage.setItem(USER_KEY,JSON.stringify(state.user));return true}catch(_){clearSession();return false}}

  function platform(m,p){return m?.[p]&&typeof m[p]==='object'?m[p]:null}
  function size(v){const n=Number(v);if(!n)return'—';const m=n/1048576;return m>=1024?`${(m/1024).toFixed(1)} ГБ`:`${m.toFixed(m>=10?0:1)} МБ`}
  function date(v){const d=new Date(v);return Number.isNaN(d.getTime())?'Дата не указана':new Intl.DateTimeFormat('ru-RU',{day:'2-digit',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(d)}
  function renderManifest(m){const v=m.version||m.windows?.version||m.android?.version||'—',b=m.build??m.windows?.build??m.android?.build??'—',w=platform(m,'windows'),a=platform(m,'android');els.heroVersion.textContent=`v${v}`;els.heroBuild.textContent=`build ${b}`;els.releaseVersion.textContent=`v${v}`;els.releaseBuild.textContent=b;els.publishedAt.textContent=date(m.publishedAt);els.changelog.textContent=w?.notes||a?.notes||m.notes||'Актуальная корпоративная сборка WesiOS.';els.windowsSize.textContent=size(w?.sizeBytes);els.androidSize.textContent=size(a?.sizeBytes);$$('[data-download]').forEach(x=>x.disabled=!platform(m,x.dataset.download));els.footerStatus.textContent=`Релиз v${v} доступен`}
  async function enterDashboard(){els.employeeName.textContent=nameOf(state.user);els.logoutButton?.classList.remove('hidden');showView(els.dashboardView);try{state.manifest=await request('/api/wesi/portal/manifest');renderManifest(state.manifest)}catch(e){els.footerStatus.textContent=e.message;toast('Список сборок пока недоступен','error')}}
  async function download(p,btn){const item=platform(state.manifest,p);if(!item)return;setLoading(btn,true,'Подготавливаем…');try{const r=await fetchTimeout(`${API}/api/wesi/portal/download/${p}`,{headers:headers()},30000);if(!r.ok)throw new Error();const blob=await r.blob(),u=URL.createObjectURL(blob),a=document.createElement('a');a.href=u;a.download=item.asset||(p==='windows'?'wesios-windows.zip':'wesios.apk');a.click();setTimeout(()=>URL.revokeObjectURL(u),30000)}catch(_){toast('Не удалось скачать сборку','error')}finally{setLoading(btn,false)}}
  function toast(text,type=''){const n=document.createElement('div');n.className=`toast ${type}`;n.textContent=text;els.toastStack?.appendChild(n);setTimeout(()=>n.remove(),4400)}

  function pointOf(node,rx=.5,ry=.5){const r=node.getBoundingClientRect();return{x:r.left+r.width*rx,y:r.top+r.height*ry}}
  function initMotion(){
    if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;
    const observer=new IntersectionObserver(entries=>entries.forEach(e=>e.isIntersecting&&e.target.classList.add('visible')),{threshold:.14});$$('[data-scroll-reveal]').forEach(n=>observer.observe(n));
    let ticking=false,last={x:0,y:0};
    const render=()=>{
      const sy=scrollY;
      $$('[data-parallax]').forEach(n=>n.style.transform=`translate3d(0,${sy*Number(n.dataset.parallax||0)}px,0)`);

      const stage=$('#moduleStage');
      if(stage){const r=stage.getBoundingClientRect(),progress=Math.max(0,Math.min(1,(innerHeight-r.top)/(innerHeight+r.height)));$$('[data-float]').forEach((n,i)=>{const phase=progress*7+i*1.35;const dx=Math.sin(phase*.9)*(8+i*2.2);const dy=Math.cos(phase)*(12+i*2.8);const rot=Math.sin(phase*.55)*(2.2+i*.35);n.style.transform=`translate3d(${dx}px,${dy}px,0) rotate(${rot}deg)`;n.style.opacity=`${.78+Math.sin(phase*.7)*.12}`})}

      const origin=$('#runnerOrigin'),core=$('#orbitCore'),flow=$('#flowSection'),rail=$('#motionRail');
      if(origin&&core&&flow&&rail&&els.runner){
        const anchors=[pointOf(origin,.02,.5),pointOf(core,.5,.18),pointOf(stage,.82,.22),pointOf(stage,.18,.78),pointOf(flow,.78,.34),pointOf(flow,.24,.72),pointOf(rail,.08,.2),pointOf(rail,.12,.86)];
        const start=origin.getBoundingClientRect().top+scrollY-innerHeight*.7,end=rail.getBoundingClientRect().bottom+scrollY-innerHeight*.35,p=Math.max(0,Math.min(1,(sy-start)/Math.max(1,end-start)));const seg=1/(anchors.length-1),idx=Math.min(anchors.length-2,Math.floor(p/seg)),local=(p-idx*seg)/seg,ease=local*local*(3-2*local),a=anchors[idx],b=anchors[idx+1],x=a.x+(b.x-a.x)*ease,y=a.y+(b.y-a.y)*ease,dx=x-last.x,dy=y-last.y,angle=Math.atan2(dy,dx)*180/Math.PI;last={x,y};
        els.runner.style.transform=`translate3d(${x}px,${y}px,0) translate(-10%,-50%) rotate(${angle}deg)`;
        els.runnerTail.style.transform=`translate3d(${x-44}px,${y}px,0) translateY(-50%) rotate(${angle}deg)`;
        const behind=idx===1||idx===2||idx===4;$('.runner-layer').style.zIndex=behind?'2':'9';els.runner.style.opacity=p<=0||p>=1?'0':'1';els.runnerTail.style.opacity=p<=0||p>=1?'0':'.78';
      }
      document.documentElement.style.setProperty('--scroll',Math.min(1,sy/Math.max(1,document.documentElement.scrollHeight-innerHeight)).toFixed(4));ticking=false;
    };
    addEventListener('scroll',()=>{if(!ticking){requestAnimationFrame(render);ticking=true}},{passive:true});addEventListener('resize',render,{passive:true});render();
    $$('[data-tilt-card]').forEach(card=>{card.addEventListener('pointermove',e=>{if(innerWidth<900)return;const r=card.getBoundingClientRect(),x=(e.clientX-r.left)/r.width-.5,y=(e.clientY-r.top)/r.height-.5;card.style.transform=`perspective(900px) rotateX(${-y*3}deg) rotateY(${x*4}deg) translateY(-2px)`});card.addEventListener('pointerleave',()=>card.style.transform='')});
  }

  function preventZoom(){document.addEventListener('gesturestart',e=>e.preventDefault(),{passive:false});document.addEventListener('touchstart',e=>{if(e.touches.length>1)e.preventDefault()},{passive:false});let last=0;document.addEventListener('touchend',e=>{const now=Date.now();if(now-last<300)e.preventDefault();last=now},{passive:false})}
  function bind(){preventZoom();els.passwordToggle?.addEventListener('click',()=>els.password.type=els.password.type==='password'?'text':'password');els.loginForm?.addEventListener('submit',async e=>{e.preventDefault();els.loginMessage.textContent='';if(!els.identity.value.trim()||!els.password.value){els.loginMessage.textContent='Введите логин и пароль';return}setLoading(els.loginButton,true,'Проверяем доступ…');try{await signIn(els.identity.value,els.password.value);els.password.value='';await enterDashboard()}catch(err){els.loginMessage.textContent=err.name==='AbortError'?'Сервер не ответил. Повторите попытку.':'Неверный логин или пароль'}finally{setLoading(els.loginButton,false)}});els.logoutButton?.addEventListener('click',()=>{clearSession();showLogin()});$$('[data-download]').forEach(b=>b.addEventListener('click',()=>download(b.dataset.download,b)))}
  async function boot(){bind();initMotion();setTimeout(()=>{els.boot?.classList.add('done');els.app?.classList.add('ready')},900);const valid=await verifySession();if(valid)await enterDashboard();else showLogin()}
  boot().catch(()=>showLogin());
})();