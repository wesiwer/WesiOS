module.exports = {
  load: function(persona) {
    try {
      const raw = $os.readFile(__hooks + "/.wesi-ai-personas.json");
      const text = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
      const cfg = JSON.parse(text || "{}");
      const personas = cfg.personas && typeof cfg.personas === "object" ? cfg.personas : {};
      if (persona === "zane" || persona === "nirvana") {
        const prompt = String(personas[persona] || "").trim();
        return {ready: prompt.length >= 200, prompt: prompt};
      }
      if (persona === "lobby") {
        const zane = String(personas.zane || "").trim();
        const nirvana = String(personas.nirvana || "").trim();
        return {
          ready: zane.length >= 200 && nirvana.length >= 200,
          prompt: "WESI_AI_LOBBY\n\n[ZANE]\n" + zane + "\n\n[NIRVANA]\n" + nirvana
        };
      }
    } catch (_) {}
    return {ready: false, prompt: ""};
  }
};
