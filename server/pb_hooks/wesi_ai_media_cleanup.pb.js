cronAdd("wesi_ai_media_cleanup", "17 3 * * *", () => {
  const root = $app.dataDir().replace(/\/$/, "") + "/wesi_ai_media";
  let records = [];
  try {
    records = $app.findRecordsByFilter(
      "wesios_records",
      "coll='ai_media' && deleted=false",
      "stamp",
      500,
      0
    );
  } catch (error) {
    $app.logger().error("Wesi AI media cleanup query failed", "error", String(error));
    return;
  }

  const now = Date.now();
  let cleaned = 0;
  for (const record of records) {
    let payload = {};
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object" && !Array.isArray(raw)) payload = raw;
      else if (typeof raw === "string" && raw.trim()) payload = JSON.parse(raw);
    } catch (_) { continue; }

    if (String(payload.status || "") !== "ready") continue;
    const expires = Date.parse(String(payload.expiresAt || ""));
    if (!Number.isFinite(expires) || expires > now) continue;

    const filename = String(payload.filename || "");
    if (/^wam_[A-Za-z0-9]{24,64}\.(png|jpg|webp|mp3|wav|ogg|flac|mp4|webm|bin)$/.test(filename)) {
      try { $os.remove(root + "/" + filename); } catch (_) {}
    }

    payload.status = "expired";
    payload.expiredAt = new Date().toISOString();
    delete payload.filename;
    delete payload.fileToken;
    delete payload.byteSize;
    const stamp = new Date().toISOString();
    record.set("payload", payload);
    record.set("stamp", stamp);
    try {
      $app.save(record);
      cleaned++;
    } catch (error) {
      $app.logger().error("Wesi AI media cleanup save failed", "jobId", String(payload.jobId || ""), "error", String(error));
    }
  }

  if (cleaned > 0) {
    $app.logger().info("Wesi AI expired media cleaned", "count", cleaned);
  }
});
