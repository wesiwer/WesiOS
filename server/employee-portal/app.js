(() => {
  'use strict';
  const API=location.origin,TOKEN_KEY='wesi_portal_token',USER_KEY='wesi_portal_user',TIMEOUT=8000;
  const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)];
  const state={token:sessionStorage.getItem(TOKEN_KEY)||'',user:json(sessionStorage.getItem(USER_KEY)),manifest:null};
  const els={boot:$('#boot'),app:$('#app'),loginView:$('#loginView'),dashboardView:$('#dashboardView'),loginForm:$('#loginForm'),identity:$('#identity'),password:$('#password'),passwordToggle:$('#passwordToggle'),loginButton:$('#loginButton'),loginMessage:$('#loginMessage'),logoutButton:$('#logoutButton'),systemStatus:$('#systemStatus'),employeeName:$('#employeeName'),heroVersion:$('#heroVersion'),heroBuild:$('#heroBuild'),releaseVersion:$('#releaseVersion'),releaseBuild:$('#releaseBuild'),publishedAt:$('#publishedAt'),changelog:$('#changelog p'),windowsSize:$('#windowsSize'),androidSize:$('#androidSize'),footerStatus:$('#footerStatus'),toastStack:$('#toastStack'),activationOpen:$('#activationOpen'),activationModal:$('#activationModal'),activationClose:$('#activationClose'),activationForm:$('#activationForm'),activationMessage:$('#activationMessage'),activationButton:$('#activationButton'),ownerEmail:$('#ownerEmail'),ownerPassword:$('#ownerPassword'),activateLogin:$('#activateLogin'),activatePassword:$('#activatePassword'),ember:$('#ember'),emberTrail:$('#emberTrail')};

  function json(v){try{return v?JSON.parse(v):null}catch(_){return null}}
  function clearSession(){state.token='';state.user=null;state.manifest=null;sessionStorage.removeItem(TOKEN_KEY);sessionStorage.removeItem(USER_KEY)}
  function headers(extra={}){return state.token?{...extra,Authorization:state.token}:extra}
  async function fetchTimeout(url,options={},timeout=TIMEOUT){const c=new AbortController(),t=setTimeout(()=>c.abort(),timeout);try{return await fetch(url,{...options,signal:c.signal})}finally{clearTimeout(t)}}
  async function request(path,options={},timeout=TIMEOUT){const r=await fetchTimeout(`${API}${path}`,{cache:'no-store',...options,headers:headers(options.headers||{})},timeout);let body=null;try{body=await r.json()}catch(_){}if(!r.ok){const e=new Error(body?.message||`HTTP ${r.status}`);e.status=r.status;e.payload=body;throw e}return body}
  function showView(next){$('.view.active')?.classList.remove('active');next?.classList.add('active');scrollTo(0,0)}
  function showLogin(){els.logoutButton?.classList.add('hidden');showView(els.loginView)}
  function setLoading(btn,on,text=''){if(!btn)return;btn.dataset.label||=$('span',btn)?.textContent||'';btn.disabled=on;const s=$('span',btn);if(s)s.textContent=on?text:btn.dataset.label}
  function nameOf(r){return(r?.name||r?.username||r?.email||'сотрудник').replace(/@wesi\.local$/i,'')}

  async function authCandidate(identity,password,collection='users'){
    const r=await fetchTimeout(`${API}/api/collections/${collection}/auth-with-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({identity,password}),cache:'no-store'});
    const body=await r.json().catch(()=>null);return{r,body};
  }
  async function signIn(identity,password){
    const raw=identity.trim(),candidates=[raw];if(raw&&!raw.includes('@'))candidates.push(`${raw.toLowerCase()}@wesi.local`);
    let status=400;for(const candidate of [...new Set(candidates)]){const {r,body}=await authCandidate(candidate,password);status=r.status;if(r.ok&&body?.token){state.token=body.token;state.user=body.record||{};sessionStorage.setItem(TOKEN_KEY,state.token);sessionStorage.setItem(USER_KEY,JSON.stringify(state.user));return}}
    const e=new Error(status===400?'Учётная запись не активирована на сервере':'Неверный логин или пароль');e.status=status;throw e;
  }
  async function verifySession(){if(!state.token)return false;try{const body=await request('/api/collections/users/auth-refresh',{method:'POST'},2400);state.token=body.token||state.token;state.user=body.record||state.user;sessionStorage.setItem(TOKEN_KEY,state.token);sessionStorage.setItem(USER_KEY,JSON.stringify(state.user));return true}catch(_){clearSession();return false}}

  async function activateLegacy(){
    const ownerEmail=els.ownerEmail.value.trim(),ownerPassword=els.ownerPassword.value,login=els.activateLogin.value.trim(),password=els.activatePassword.value;
    if(!ownerEmail||!ownerPassword||!login||!password)throw new Error('Заполните все поля');
    let ownerAuth=await authCandidate(ownerEmail,ownerPassword,'_superusers');
    if(!ownerAuth.r.ok||!ownerAuth.body?.token)ownerAuth=await authCandidate(ownerEmail,ownerPassword,'users');
    if(!ownerAuth.r.ok||!ownerAuth.body?.token)throw new Error('Не удалось подтвердить администратора PocketBase');
    const r=await fetchTimeout(`${API}/api/wesi/portal/employees/provision`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:ownerAuth.body.token},body:JSON.stringify({login,name:login,password})},12000);
    const body=await r.json().catch(()=>null);if(!r.ok)throw new Error(body?.message||`Активация не выполнена: HTTP ${r.status}`);
    els.identity.value=login;els.password.value=password;els.ownerPassword.value='';els.activatePassword.value='';closeActivation();toast('Учётная запись активирована. Выполняю вход…','success');await signIn(login,password);await enterDashboard();
  }

  function platform(m,p){return m?.[p]&&typeof m[p]==='object'?m[p]:null}
  function size(v){const n=Number(v);if(!n)return'—';const m=n/1048576;return m>=1024?`${(m/1024).toFixed(1)} ГБ`:`${m.toFixed(m>=10?0:1)} МБ`}
  function date(v){const d=new Date(v);return Number.isNaN(d.getTime())?'Дата не указана':new Intl.DateTimeFormat('ru-RU',{day:'2-digit',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(d)}
  function renderManifest(m){const v=m.version||m.windows?.version||m.android?.version||'—',b=m.build??m.windows?.build??m.android?.build??'—',w=platform(m,'windows'),a=platform(m,'android');els.heroVersion.textContent=`v${v}`;els.heroBuild.textContent=`build ${b}`;els.releaseVersion.textContent=`v${v}`;els.releaseBuild.textContent=b;els.publishedAt.textContent=date(m.publishedAt);els.changelog.textContent=w?.notes||a?.notes||m.notes||'Актуальная корпоративная сборка WesiOS.';els.windowsSize.textContent=size(w?.sizeBytes);els.androidSize.textContent=size(a?.sizeBytes);$$('[data-download]').forEach(x=>x.disabled=!platform(m,x.dataset.download));els.systemStatus.textContent='Сервер отвечает';els.footerStatus.textContent=`Релиз v${v} доступен`}
  async function enterDashboard(){els.employeeName.textContent=nameOf(state.user);els.logoutButton?.classList.remove('hidden');showView(els.dashboardView);try{state.manifest=await request('/api/wesi/portal/manifest');renderManifest(state.manifest)}catch(e){els.footerStatus.textContent=e.message;toast('Список сборок пока недоступен','error')}}
  async function download(p,btn){const item=platform(state.manifest,p);if(!item)return;setLoading(btn,true,'Подготавливаем…');try{const r=await fetchTimeout(`${API}/api/wesi/portal/download/${p}`,{headers:headers()},30000);if(!r.ok)throw new Error();const blob=await r.blob(),u=URL.createObjectURL(blob),a=document.createElement('a');a.href=u;a.download=item.asset||(p==='windows'?'wesios-windows.zip':'wesios.apk');a.click();setTimeout(()=>URL.revokeObjectURL(u),30000)}catch(_){toast('Не удалось скачать сборку','error')}finally{setLoading(btn,false)}}
  function toast(text,type=''){const n=document.createElement('div');n.className=`toast ${type}`;n.textContent=text;els.toastStack?.appendChild(n);setTimeout(()=>n.remove(),4400)}

  function openActivation(){els.activateLogin.value=els.identity.value.trim();els.activatePassword.value=els.password.value;els.activationMessage.textContent='';els.activationModal.classList.remove('hidden');document.body.style.overflow='hidden'}
  function closeActivation(){els.activationModal.classList.add('hidden');document.body.style.overflow=''}

  function initMotion(){
    if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;
    const observer=new IntersectionObserver(entries=>entries.forEach(e=>e.isIntersecting&&e.target.classList.add('visible')),{threshold:.14});$$('[data-scroll-reveal]').forEach(n=>observer.observe(n));
    let lastX=innerWidth*.12,lastY=innerHeight*.45,ticking=false;
    const render=()=>{
      const y=scrollY,max=Math.max(1,document.documentElement.scrollHeight-innerHeight),p=Math.max(0,Math.min(1,y/max));
      $$('[data-parallax]').forEach(n=>n.style.transform=`translate3d(0,${y*Number(n.dataset.parallax||0)}px,0)`);
      const stage=$('.module-stage');if(stage){const r=stage.getBoundingClientRect(),stageP=Math.max(0,Math.min(1,(innerHeight-r.top)/(innerHeight+r.height)));$$('[data-float]').forEach((n,i)=>{const a=(i+1)*1.17+stageP*5.4,amp=8+i*3,dy=Math.sin(a)*amp,dx=Math.cos(a*.8)*amp*.55,rot=Math.sin(a*.6)*3;n.style.transform=`translate3d(${dx}px,${dy}px,0) rotate(${rot}deg)`})}
      const points=[
        [innerWidth*.12,innerHeight*.46],
        [innerWidth*.82,innerHeight*.22],
        [innerWidth*.72,innerHeight*.72],
        [innerWidth*.24,innerHeight*.35],
        [innerWidth*.56,innerHeight*.58],
        [innerWidth*.88,innerHeight*.44]
      ];
      const span=1/(points.length-1),idx=Math.min(points.length-2,Math.floor(p/span)),local=(p-idx*span)/span,ease=local*local*(3-2*local),a=points[idx],b=points[idx+1],x=a[0]+(b[0]-a[0])*ease+Math.sin(p*32)*8,yPos=a[1]+(b[1]-a[1])*ease+Math.cos(p*25)*7;
      const dx=x-lastX,dy=yPos-lastY,angle=Math.atan2(dy,dx)*180/Math.PI,len=Math.min(120,Math.hypot(dx,dy)*4+30);lastX=x;lastY=yPos;
      els.ember.style.transform=`translate3d(${x}px,${yPos}px,0) translate(-50%,-50%) scale(${1+Math.sin(p*50)*.16})`;
      els.emberTrail.style.left=`${x-len}px`;els.emberTrail.style.top=`${yPos}px`;els.emberTrail.style.width=`${len}px`;els.emberTrail.style.transform=`rotate(${angle}deg)`;
      const behind=(idx===1||idx===3);$('.ember-layer').style.zIndex=behind?'3':'8';els.ember.style.opacity=behind?'.62':'1';
      document.documentElement.style.setProperty('--scroll',p.toFixed(4));ticking=false;
    };
    addEventListener('scroll',()=>{if(!ticking){requestAnimationFrame(render);ticking=true}},{passive:true});addEventListener('resize',render,{passive:true});render();
    $$('[data-tilt-card]').forEach(card=>{card.addEventListener('pointermove',e=>{if(innerWidth<900)return;const r=card.getBoundingClientRect(),x=(e.clientX-r.left)/r.width-.5,y=(e.clientY-r.top)/r.height-.5;card.style.transform=`perspective(900px) rotateX(${-y*3}deg) rotateY(${x*4}deg) translateY(-2px)`});card.addEventListener('pointerleave',()=>card.style.transform='')});
  }

  function preventZoom(){document.addEventListener('gesturestart',e=>e.preventDefault(),{passive:false});document.addEventListener('touchstart',e=>{if(e.touches.length>1)e.preventDefault()},{passive:false});let last=0;document.addEventListener('touchend',e=>{const now=Date.now();if(now-last<300)e.preventDefault();last=now},{passive:false})}
  function bind(){
    preventZoom();els.passwordToggle?.addEventListener('click',()=>els.password.type=els.password.type==='password'?'text':'password');
    els.loginForm?.addEventListener('submit',async e=>{e.preventDefault();els.loginMessage.textContent='';els.activationOpen.classList.add('hidden');if(!els.identity.value.trim()||!els.password.value){els.loginMessage.textContent='Введите логин и пароль';return}setLoading(els.loginButton,true,'Проверяем доступ…');try{await signIn(els.identity.value,els.password.value);els.password.value='';await enterDashboard()}catch(err){els.loginMessage.textContent=err.name==='AbortError'?'Сервер не ответил. Повторите попытку.':err.message;if(err.status===400)els.activationOpen.classList.remove('hidden')}finally{setLoading(els.loginButton,false)}});
    els.activationOpen?.addEventListener('click',openActivation);els.activationClose?.addEventListener('click',closeActivation);els.activationModal?.addEventListener('click',e=>{if(e.target===els.activationModal)closeActivation()});
    els.activationForm?.addEventListener('submit',async e=>{e.preventDefault();els.activationMessage.textContent='';setLoading(els.activationButton,true,'Активируем…');try{await activateLegacy()}catch(err){els.activationMessage.textContent=err.message}finally{setLoading(els.activationButton,false)}});
    els.logoutButton?.addEventListener('click',()=>{clearSession();showLogin()});$$('[data-download]').forEach(b=>b.addEventListener('click',()=>download(b.dataset.download,b)));
  }
  async function boot(){bind();initMotion();setTimeout(()=>{els.boot?.classList.add('done');els.app?.classList.add('ready')},900);const valid=await verifySession();if(valid)await enterDashboard();else showLogin()}
  boot().catch(()=>showLogin());
})();