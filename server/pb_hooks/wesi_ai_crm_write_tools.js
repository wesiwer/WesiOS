const ROOT_ORG = "org_wesi_inc";

function payload(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}
function rows(e, ctx, coll) {
  try { return e.app.findRecordsByFilter("wesios_records", "owner={:owner} && coll={:coll} && deleted=false", "-stamp", 0, 0, {owner: ctx.ownerId, coll}); }
  catch (_) { return []; }
}
function recordById(e, ctx, coll, id) {
  try { return e.app.findFirstRecordByFilter("wesios_records", "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false", {owner: ctx.ownerId, coll, rid: id}); }
  catch (_) { return null; }
}
function access(e, ctx) {
  let permissions = {};
  if (!ctx.isOwner) {
    let employee = null;
    try { employee = e.app.findFirstRecordByFilter("wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false", {owner: ctx.ownerId, rid: ctx.employeeId}); } catch (_) {}
    const p = payload(employee); permissions = p.permissions && typeof p.permissions === "object" ? p.permissions : {};
  }
  const orgs = {}, parents = {};
  for (const row of rows(e, ctx, "organizations")) { const p = payload(row); const id = String(p.id || row.getString("rid") || ""); if (!id || String(p.status || "active") === "archived") continue; orgs[id] = p; parents[id] = p.parentId == null ? null : String(p.parentId); }
  const grants = ctx.isOwner ? [] : rows(e, ctx, "organization_grants").map(payload).filter((g) => String(g.employeeId || "") === ctx.employeeId);
  const allowed = {};
  for (const id of Object.keys(orgs)) {
    if (ctx.isOwner) { allowed[id] = true; continue; }
    let cursor = id, first = true;
    while (cursor) {
      const ok = grants.some((g) => { if (String(g.organizationId || "") !== cursor) return false; if (!first && g.includeSubtree !== true) return false; const ps = Array.isArray(g.permissions) ? g.permissions.map(String) : []; return ps.indexOf("view") >= 0; });
      if (ok) { allowed[id] = true; break; } first = false; cursor = parents[cursor];
    }
  }
  return {allowed, manager: ctx.isOwner || permissions.canManageTeam === true};
}
function visibleClient(a, ctx, p) { return a.allowed[String(p.organizationId || ROOT_ORG)] === true && (a.manager || String(p.ownerEmployeeId || "") === ctx.employeeId); }
function visibleDeal(e, ctx, a, p) {
  if (a.allowed[String(p.organizationId || ROOT_ORG)] !== true) return false;
  if (a.manager || String(p.responsibleEmployeeId || "") === ctx.employeeId) return true;
  const client = recordById(e, ctx, "crm_clients", String(p.clientId || ""));
  return !!client && String(payload(client).ownerEmployeeId || "") === ctx.employeeId;
}
function dateOrNull(v) { if (v == null || String(v).trim() === "") return {ok: true, value: null}; const d = new Date(String(v)); return Number.isFinite(d.getTime()) ? {ok: true, value: d.toISOString()} : {ok: false}; }
function saveNew(e, ctx, coll, id, value) { const now = new Date().toISOString(); const c = e.app.findCollectionByNameOrId("wesios_records"); const r = new Record(c); r.set("owner", ctx.ownerId); r.set("org", "wesi-inc"); r.set("coll", coll); r.set("rid", id); r.set("payload", value); r.set("stamp", now); r.set("deleted", false); e.app.save(r); }

module.exports = {
  definitions: function(e, ctx) {
    if (!ctx.isOwner && ctx.modules.indexOf("crm") < 0) return [];
    return [
      {name:"crm_client_create",description:"Создать CRM-клиента WesiOS в доступной организации.",parameters:{type:"object",required:["name"],properties:{name:{type:"string"},company:{type:"string"},phone:{type:"string"},email:{type:"string"},website:{type:"string"},address:{type:"string"},source:{type:"string"},notes:{type:"string"},status:{type:"string",enum:["lead","active","paused"]},tags:{type:"array",items:{type:"string"}},nextContactAt:{type:["string","null"]},organizationId:{type:"string"}}}},
      {name:"crm_client_update",description:"Изменить доступного CRM-клиента WesiOS.",parameters:{type:"object",required:["clientId"],properties:{clientId:{type:"string"},name:{type:"string"},company:{type:"string"},phone:{type:"string"},email:{type:"string"},website:{type:"string"},address:{type:"string"},source:{type:"string"},notes:{type:"string"},status:{type:"string",enum:["lead","active","paused"]},tags:{type:"array",items:{type:"string"}},nextContactAt:{type:["string","null"]}}}},
      {name:"crm_client_archive",description:"Архивировать CRM-клиента. DESTRUCTIVE: требуется подтверждение.",parameters:{type:"object",required:["clientId"],properties:{clientId:{type:"string"}}}},
      {name:"crm_deal_create",description:"Создать CRM-сделку для доступного клиента.",parameters:{type:"object",required:["clientId","title"],properties:{clientId:{type:"string"},title:{type:"string"},amount:{type:"number"},currency:{type:"string"},stage:{type:"string",enum:["newLead","qualification","proposal","negotiation","won","lost"]},probability:{type:"integer",minimum:0,maximum:100},notes:{type:"string"},expectedCloseAt:{type:["string","null"]}}}},
      {name:"crm_deal_update",description:"Изменить доступную CRM-сделку.",parameters:{type:"object",required:["dealId"],properties:{dealId:{type:"string"},title:{type:"string"},amount:{type:"number"},currency:{type:"string"},stage:{type:"string",enum:["newLead","qualification","proposal","negotiation","won","lost"]},probability:{type:"integer",minimum:0,maximum:100},notes:{type:"string"},expectedCloseAt:{type:["string","null"]}}}},
      {name:"crm_deal_archive",description:"Архивировать CRM-сделку. DESTRUCTIVE: требуется подтверждение.",parameters:{type:"object",required:["dealId"],properties:{dealId:{type:"string"}}}},
      {name:"crm_interaction_create",description:"Добавить реальное взаимодействие/заметку CRM по доступному клиенту/сделке.",parameters:{type:"object",required:["clientId","title"],properties:{clientId:{type:"string"},dealId:{type:["string","null"]},kind:{type:"string",enum:["note","call","email","meeting","message"]},title:{type:"string"},details:{type:"string"},at:{type:"string"},nextActionAt:{type:["string","null"]}}}},
    ];
  },
  context: function(){return {};},
  execute: function(e, ctx, name, args) {
    if (!ctx.isOwner && ctx.modules.indexOf("crm") < 0) return {ok:false,code:"FORBIDDEN",message:"Нет доступа к CRM"};
    const input=args&&typeof args==="object"&&!Array.isArray(args)?args:{}; const a=access(e,ctx); const now=new Date().toISOString();
    if(name==="crm_client_create"){
      const org=String(input.organizationId||ROOT_ORG); if(a.allowed[org]!==true)return{ok:false,code:"FORBIDDEN",message:"Нет доступа к этой организации"};
      const title=String(input.name||"").trim(); if(!title||title.length>500)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректное имя клиента"};
      const nextContact=dateOrNull(input.nextContactAt); if(!nextContact.ok)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная дата контакта"};
      const id="wai_crm_client_"+Date.now()+"_"+$security.randomString(8); const status=["lead","active","paused"].includes(String(input.status||"lead"))?String(input.status||"lead"):"lead";
      const value={id,name:title,company:String(input.company||"").slice(0,500),phone:String(input.phone||"").slice(0,100),email:String(input.email||"").slice(0,320),website:String(input.website||"").slice(0,1000),address:String(input.address||"").slice(0,1000),source:String(input.source||"").slice(0,500),owner:"",notes:String(input.notes||"").slice(0,20000),status,tags:Array.isArray(input.tags)?input.tags.slice(0,30).map(String):[],createdAt:now,updatedAt:now,nextContactAt:nextContact.value,organizationId:org,ownerEmployeeId:ctx.employeeId}; saveNew(e,ctx,"crm_clients",id,value); return{ok:true,result:{client:{id,name:title,organizationId:org}}};
    }
    if(name.startsWith("crm_client_")){
      const id=String(input.clientId||"").trim(), r=recordById(e,ctx,"crm_clients",id); if(!r)return{ok:false,code:"NOT_FOUND",message:"CRM-клиент не найден"}; const before=payload(r); if(!visibleClient(a,ctx,before))return{ok:false,code:"FORBIDDEN",message:"Нет права менять этого клиента"};
      if(name==="crm_client_archive"){r.set("deleted",true);r.set("stamp",now);e.app.save(r);return{ok:true,result:{client:{id,archived:true}}};}
      const next=Object.assign({},before); const fields=["company","phone","email","website","address","source","notes"]; for(const f of fields)if(Object.prototype.hasOwnProperty.call(input,f))next[f]=String(input[f]||"").slice(0,f==="notes"?20000:1000);
      if(Object.prototype.hasOwnProperty.call(input,"name")){const v=String(input.name||"").trim();if(!v||v.length>500)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректное имя клиента"};next.name=v;}
      if(Object.prototype.hasOwnProperty.call(input,"status")){const v=String(input.status||"");if(!["lead","active","paused"].includes(v))return{ok:false,code:"VALIDATION_ERROR",message:"Некорректный статус"};next.status=v;}
      if(Object.prototype.hasOwnProperty.call(input,"tags"))next.tags=Array.isArray(input.tags)?input.tags.slice(0,30).map(String):[];
      if(Object.prototype.hasOwnProperty.call(input,"nextContactAt")){const d=dateOrNull(input.nextContactAt);if(!d.ok)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная дата контакта"};next.nextContactAt=d.value;}
      next.updatedAt=now;r.set("payload",next);r.set("stamp",now);e.app.save(r);return{ok:true,result:{client:{id,name:String(next.name||""),status:String(next.status||"lead")}}};
    }
    if(name==="crm_deal_create"){
      const clientId=String(input.clientId||"").trim(), cr=recordById(e,ctx,"crm_clients",clientId); if(!cr)return{ok:false,code:"NOT_FOUND",message:"CRM-клиент не найден"}; const cp=payload(cr); if(!visibleClient(a,ctx,cp))return{ok:false,code:"FORBIDDEN",message:"Нет доступа к клиенту"};
      const title=String(input.title||"").trim();if(!title||title.length>500)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректное название сделки"}; const amount=Number(input.amount||0);if(!Number.isFinite(amount)||amount<0)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная сумма"}; const stage=String(input.stage||"newLead");if(!["newLead","qualification","proposal","negotiation","won","lost"].includes(stage))return{ok:false,code:"VALIDATION_ERROR",message:"Некорректный этап"}; const expected=dateOrNull(input.expectedCloseAt);if(!expected.ok)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная дата закрытия"}; const probability=Math.max(0,Math.min(100,Math.trunc(Number(input.probability==null?10:input.probability)))); const id="wai_crm_deal_"+Date.now()+"_"+$security.randomString(8); const value={id,clientId,title,amount,currency:String(input.currency||"RUB").toUpperCase().slice(0,12),stage,probability,notes:String(input.notes||"").slice(0,20000),transactionId:"",tags:[],createdAt:now,updatedAt:now,expectedCloseAt:expected.value,closedAt:(stage==="won"||stage==="lost")?now:null,organizationId:String(cp.organizationId||ROOT_ORG),responsibleEmployeeId:ctx.employeeId};saveNew(e,ctx,"crm_deals",id,value);return{ok:true,result:{deal:{id,clientId,title,stage,amount}}};
    }
    if(name.startsWith("crm_deal_")){
      const id=String(input.dealId||"").trim(),r=recordById(e,ctx,"crm_deals",id);if(!r)return{ok:false,code:"NOT_FOUND",message:"CRM-сделка не найдена"};const before=payload(r);if(!visibleDeal(e,ctx,a,before))return{ok:false,code:"FORBIDDEN",message:"Нет права менять эту сделку"};if(name==="crm_deal_archive"){r.set("deleted",true);r.set("stamp",now);e.app.save(r);return{ok:true,result:{deal:{id,archived:true}}};} const next=Object.assign({},before);
      if(Object.prototype.hasOwnProperty.call(input,"title")){const v=String(input.title||"").trim();if(!v||v.length>500)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректное название сделки"};next.title=v;} if(Object.prototype.hasOwnProperty.call(input,"amount")){const v=Number(input.amount);if(!Number.isFinite(v)||v<0)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная сумма"};next.amount=v;} if(Object.prototype.hasOwnProperty.call(input,"currency"))next.currency=String(input.currency||"RUB").toUpperCase().slice(0,12); if(Object.prototype.hasOwnProperty.call(input,"probability")){const v=Number(input.probability);if(!Number.isFinite(v)||v<0||v>100)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная вероятность"};next.probability=Math.trunc(v);} if(Object.prototype.hasOwnProperty.call(input,"notes"))next.notes=String(input.notes||"").slice(0,20000); if(Object.prototype.hasOwnProperty.call(input,"expectedCloseAt")){const d=dateOrNull(input.expectedCloseAt);if(!d.ok)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная дата"};next.expectedCloseAt=d.value;} if(Object.prototype.hasOwnProperty.call(input,"stage")){const v=String(input.stage||"");if(!["newLead","qualification","proposal","negotiation","won","lost"].includes(v))return{ok:false,code:"VALIDATION_ERROR",message:"Некорректный этап"};next.stage=v;if(v==="won"||v==="lost")next.closedAt=now;else next.closedAt=null;} next.updatedAt=now;r.set("payload",next);r.set("stamp",now);e.app.save(r);return{ok:true,result:{deal:{id,title:String(next.title||""),stage:String(next.stage||"newLead"),amount:Number(next.amount||0)}}};
    }
    if(name==="crm_interaction_create"){
      const clientId=String(input.clientId||"").trim(),cr=recordById(e,ctx,"crm_clients",clientId);if(!cr||!visibleClient(a,ctx,payload(cr)))return{ok:false,code:"FORBIDDEN",message:"Нет доступа к CRM-клиенту"};const dealId=input.dealId==null?"":String(input.dealId).trim();if(dealId){const dr=recordById(e,ctx,"crm_deals",dealId);if(!dr||!visibleDeal(e,ctx,a,payload(dr))||String(payload(dr).clientId||"")!==clientId)return{ok:false,code:"FORBIDDEN",message:"Нет доступа к указанной сделке"};}const title=String(input.title||"").trim();if(!title||title.length>500)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректный заголовок взаимодействия"};const kind=String(input.kind||"note");if(!["note","call","email","meeting","message"].includes(kind))return{ok:false,code:"VALIDATION_ERROR",message:"Некорректный тип взаимодействия"};const at=input.at?dateOrNull(input.at):{ok:true,value:now};const next=dateOrNull(input.nextActionAt);if(!at.ok||!at.value||!next.ok)return{ok:false,code:"VALIDATION_ERROR",message:"Некорректная дата взаимодействия"};const id="wai_crm_interaction_"+Date.now()+"_"+$security.randomString(8);const value={id,clientId,dealId:dealId||null,kind,title,details:String(input.details||"").slice(0,20000),author:ctx.employeeId,at:at.value,nextActionAt:next.value};saveNew(e,ctx,"crm_interactions",id,value);return{ok:true,result:{interaction:{id,clientId,dealId:dealId||null,kind,title}}};
    }
    return{ok:false,code:"UNKNOWN_TOOL",message:"Неизвестный CRM-инструмент"};
  }
};
