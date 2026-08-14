routerAdd("GET", "/api/wesi/ai/media/file/{jobId}", (e) => {
  const media = require(`${__hooks}/wesi_ai_media_lib.js`);
  const jobId = String(e.request.pathValue("jobId") || "");
  const token = String(e.request.url.query().get("token") || "");
  return media.serveFile(e, jobId, token);
});

routerAdd("GET", "/api/wesi/ai/media/jobs/{jobId}", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const media = require(`${__hooks}/wesi_ai_media_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);

  const jobId = String(e.request.pathValue("jobId") || "");
  const record = media.findJob(jobId);
  if (!record || !media.canAccess(ctx, record)) throw new NotFoundError("Медиазадача не найдена");

  let payload = media.payloadOf(record);
  if (String(payload.kind || "") === "video" && String(payload.status || "") === "running") {
    const last = Date.parse(String(payload.lastCheckedAt || ""));
    const due = !Number.isFinite(last) || Date.now() - last >= 4000;
    if (due) {
      const cfg = ai.readRelayConfig();
      if (!cfg.ready) {
        payload = media.failJob(record, "WAI_RELAY_NOT_CONFIGURED");
      } else {
        const operationName = String(payload.providerOperationName || "");
        if (!/^[A-Za-z0-9._\/-]{4,300}$/.test(operationName) || operationName.indexOf("..") >= 0) {
          payload = media.failJob(record, "WAI_MEDIA_JOB_INVALID");
        } else {
          const requestId = "wai_vstat_" + Date.now() + "_" + $security.randomString(12);
          const relay = ai.callRelayJson(cfg, {
            requestId: requestId,
            operation: "video.status",
            input: {operationName: operationName}
          }, requestId, 210);
          if (!relay.ok) {
            // Provider/network errors are retriable for an existing async job.
            payload.lastCheckedAt = new Date().toISOString();
            payload.lastErrorCode = String(relay.code || "WAI_PROVIDER_UNAVAILABLE");
            media.savePayload(record, payload);
          } else {
            const job = relay.result && relay.result.job && typeof relay.result.job === "object" ? relay.result.job : {};
            if (job.done === true && job.failed === true) {
              payload = media.failJob(record, String(job.code || "WAI_MEDIA_JOB_FAILED"));
            } else if (job.done === true && job.media && typeof job.media === "object") {
              const saved = media.persistRelayArtifact(ai, cfg, record, job.media);
              payload = saved.ok ? saved.payload : media.failJob(record, saved.code);
            } else {
              payload.lastCheckedAt = new Date().toISOString();
              delete payload.lastErrorCode;
              media.savePayload(record, payload);
            }
          }
        }
      }
    }
  }

  payload = media.payloadOf(record);
  return e.json(200, {
    ok: true,
    jobId: String(payload.jobId || jobId),
    status: String(payload.status || "pending"),
    contentBlock: media.makeContentBlock(payload)
  });
}, $apis.requireAuth("users"));
