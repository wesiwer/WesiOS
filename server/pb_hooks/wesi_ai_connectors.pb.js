function statusFor(code) {
  if (code === "CONNECTOR_CREDENTIAL_INVALID") return 401;
  if (code === "CONNECTOR_FORBIDDEN" || code === "CONNECTOR_SCOPE_MISSING") return 403;
  if (code === "GITHUB_OAUTH_FLOW_EXPIRED") return 410;
  if (code === "CONNECTOR_RATE_LIMITED") return 429;
  if (code === "CONNECTOR_VAULT_NOT_CONFIGURED" || code === "CONNECTOR_VAULT_NOT_MIGRATED" || code === "GITHUB_OAUTH_NOT_CONFIGURED" || code === "CONNECTOR_NETWORK") return 503;
  return 400;
}
function fail(e, err) {
  const code=String(err&&err.code||"CONNECTOR_FAILED");
  return e.json(statusFor(code),{ok:false,code,message:String(err&&err.message||"Connector request failed").slice(0,500)});
}
function context(e) {
  const ai=require(`${__hooks}/wesi_ai_lib.js`); const ctx=ai.resolveIdentity(e); ai.requireAiModule(ctx); return ctx;
}

routerAdd("GET", "/api/wesi/ai/connectors", (e) => {
  const github=require(`${__hooks}/wesi_ai_github_connector.js`), vault=require(`${__hooks}/wesi_ai_connector_vault.js`); const ctx=context(e);
  let accounts=[]; try{accounts=github.listMetadata(e,ctx);}catch(err){if(err&&err.code!=="CONNECTOR_VAULT_NOT_CONFIGURED")return fail(e,err);}
  let oauthReady=false; try{oauthReady=/^[A-Za-z0-9_-]{8,200}$/.test(String($os.getenv("WESI_GITHUB_OAUTH_CLIENT_ID")||"").trim());}catch(_){}
  return e.json(200,{ok:true,providers:[{id:"github",title:"GitHub",connected:accounts.some((x)=>x.status==="active"),accounts,available:vault.ready()&&oauthReady}]});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/connectors/github/device/start", (e) => {
  const github=require(`${__hooks}/wesi_ai_github_connector.js`); const ctx=context(e); try{return e.json(200,{ok:true,flow:github.startDeviceFlow(e,ctx)});}catch(err){return fail(e,err);}
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/connectors/github/device/poll", (e) => {
  const github=require(`${__hooks}/wesi_ai_github_connector.js`); const ctx=context(e), body=e.requestInfo().body||{}, flowId=String(body.flowId||"").trim();
  if(!/^wai_conn_flow_[A-Za-z0-9_-]{20,80}$/.test(flowId)) return e.json(400,{ok:false,code:"GITHUB_OAUTH_FLOW_INVALID"});
  try{return e.json(200,{ok:true,...github.pollDeviceFlow(e,ctx,flowId)});}catch(err){return fail(e,err);}
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/connectors/disconnect", (e) => {
  const github=require(`${__hooks}/wesi_ai_github_connector.js`); const ctx=context(e), body=e.requestInfo().body||{}, provider=String(body.provider||""), credentialId=String(body.credentialId||"").trim();
  if(provider!=="github"||!/^wai_conn_github_[A-Za-z0-9_-]{20,80}$/.test(credentialId)) return e.json(400,{ok:false,code:"CONNECTOR_CREDENTIAL_INVALID"});
  try{github.disconnect(e,ctx,credentialId);return e.json(200,{ok:true});}catch(err){return fail(e,err);}
}, $apis.requireAuth("users"));
