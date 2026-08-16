const RISK_READ = "READ";

const TECHNICAL_SIGNALS = [
  /\b(architecture|backend|api|database|db|sql|code|coding|flutter|dart|bug|debug|server|security|build|gradle|cmake|devops|ci|cd|test|tests|algorithm|integration|automation|performance|latency|cache|network|protocol|release)\b/i,
  /(архитектур|бэкенд|бекенд|апи|баз[аы] данных|код|программир|флаттер|ошибк|баг|дебаг|сервер|безопасн|сборк|градл|тест|алгоритм|интеграц|автоматизац|производительн|релиз|депло|данн|расч[её]т)/i,
];

const CREATIVE_SIGNALS = [
  /\b(ux|ui|design|interface|visual|layout|typography|color|motion|animation|graphic|image|video|media|presentation|storytelling|cover|creative|branding|brand)\b/i,
  /(дизайн|интерфейс|визуал|композиц|типограф|цвет|анимац|график|изображен|видео|медиа|презентац|сторител|обложк|креатив|бренд|юзабилит|пользовательск.*опыт)/i,
];

const BROAD_PRODUCT_SIGNALS = [
  /\b(app|application|product|website|dashboard|platform|service|mobile app|desktop app)\b/i,
  /(приложен|продукт|сайт|дашборд|панел[ьи]|платформ|сервис|мобильн.*прилож|десктоп)/i,
];

function cleanText(value, max) {
  const text = String(value || "").replace(/\u0000/g, "").trim();
  return text.length <= max ? text : text.slice(0, max);
}

function countSignals(text, patterns) {
  let count = 0;
  for (const pattern of patterns) {
    if (pattern.test(text)) count += 1;
  }
  return count;
}

function unique(values) {
  const out = [];
  const seen = {};
  for (const raw of Array.isArray(values) ? values : []) {
    const value = String(raw || "").trim();
    if (!value || seen[value]) continue;
    seen[value] = true;
    out.push(value);
  }
  return out;
}

function toolScopes(toolDefinitions) {
  const read = [];
  const sideEffects = [];
  for (const item of Array.isArray(toolDefinitions) ? toolDefinitions : []) {
    const name = String(item && item.name || "").trim();
    if (!name) continue;
    const risk = String(item && item.wesiCapability && item.wesiCapability.risk || "").trim().toUpperCase();
    if (risk === RISK_READ) read.push(name);
    else sideEffects.push(name);
  }
  return {read: unique(read), sideEffects: unique(sideEffects)};
}

function conversationExcerpt(history) {
  const items = Array.isArray(history) ? history.slice(-4) : [];
  const lines = [];
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const author = cleanText(item.author || item.role, 40);
    const text = cleanText(item.text || item.content, 1200);
    if (text) lines.push((author || "message") + ": " + text);
  }
  return cleanText(lines.join("\n"), 3600);
}

function memoryExcerpt(memory, coagentPersona) {
  const chunks = [];
  const safe = memory && typeof memory === "object" ? memory : {};
  const shared = Array.isArray(safe.shared) ? safe.shared : [];
  const project = Array.isArray(safe.project) ? safe.project : [];
  const persona = coagentPersona === "zane"
    ? (Array.isArray(safe.zane) ? safe.zane : [])
    : (Array.isArray(safe.nirvana) ? safe.nirvana : []);
  for (const item of shared.slice(0, 4)) chunks.push(String(item || ""));
  for (const item of project.slice(0, 4)) chunks.push(String(item || ""));
  for (const item of persona.slice(0, 3)) chunks.push(String(item || ""));
  return cleanText(chunks.filter(Boolean).join("\n"), 3000);
}

function attachmentSummary(attachments) {
  const lines = [];
  for (const item of Array.isArray(attachments) ? attachments : []) {
    if (!item || typeof item !== "object") continue;
    const name = cleanText(item.name, 180);
    const mimeType = cleanText(item.mimeType, 120);
    const byteSize = Math.max(0, Number(item.byteSize || 0) || 0);
    lines.push([name || "file", mimeType || "application/octet-stream", String(byteSize) + " bytes"].join(" | "));
  }
  return cleanText(lines.join("\n"), 1600);
}

function buildContext(input, coagentPersona) {
  const context = [];
  const message = cleanText(input.message, 6000);
  if (message) context.push({kind: "user_request", label: "Текущий запрос", text: message});
  const excerpt = conversationExcerpt(input.history);
  if (excerpt) context.push({kind: "conversation_excerpt", label: "Последний контекст диалога", text: excerpt});
  const projectContext = cleanText(input.projectContext, 3500);
  if (projectContext) context.push({kind: "project_context", label: "Контекст проекта", text: projectContext});
  const memory = memoryExcerpt(input.memory, coagentPersona);
  if (memory) context.push({kind: "memory_excerpt", label: "Разрешённая память", text: memory});
  const attachments = attachmentSummary(input.attachments);
  if (attachments) context.push({kind: "attachment_summary", label: "Вложения", text: attachments});
  return context;
}

function taskFor(leadPersona, message) {
  const request = cleanText(message, 2600);
  if (leadPersona === "zane") {
    return "Проведи независимую UX/UI/visual/creative проверку части задачи, где твоя специализация реально улучшает результат. " +
      "Верни только структурированные выводы, риски, рекомендации и критерии приёмки для Lead Зейна. Не формируй финальный ответ пользователю. Запрос: " + request;
  }
  return "Проведи независимую technical/analytical проверку архитектуры, данных, интеграций, безопасности, производительности, build/test ограничений задачи. " +
    "Верни только структурированные выводы, риски, рекомендации и критерии приёмки для Lead Нирваны. Не формируй финальный ответ пользователю. Запрос: " + request;
}

function evaluate(input) {
  const leadPersona = String(input.leadPersona || "").trim().toLowerCase();
  const coagentPersona = leadPersona === "zane" ? "nirvana" : leadPersona === "nirvana" ? "zane" : "";
  if (!coagentPersona) return {enabled: false, reason: "invalid_lead"};

  const tier = String(input.tier || "fast").trim().toLowerCase();
  const lobbyMode = String(input.lobbyMode || "smart").trim().toLowerCase();
  const message = cleanText(input.message, 12000);
  const projectContext = cleanText(input.projectContext, 6000);
  const text = (message + "\n" + projectContext).trim();
  const technicalScore = countSignals(text, TECHNICAL_SIGNALS);
  const creativeScore = countSignals(text, CREATIVE_SIGNALS);
  const broadProduct = BROAD_PRODUCT_SIGNALS.some(function(pattern) { return pattern.test(text); });
  const crossScore = leadPersona === "zane" ? creativeScore : technicalScore;
  const threshold = tier === "fast" ? 2 : 1;
  const forced = lobbyMode === "both";
  const mixed = technicalScore > 0 && creativeScore > 0;
  const enabled = forced || broadProduct || mixed || crossScore >= threshold;

  let reason = "single_persona_sufficient";
  if (forced) reason = "joint_mode";
  else if (broadProduct) reason = "cross_domain_product";
  else if (mixed) reason = "mixed_specializations";
  else if (crossScore >= threshold) reason = leadPersona === "zane" ? "creative_review_needed" : "technical_review_needed";

  const scopes = toolScopes(input.toolDefinitions);
  return {
    enabled: enabled,
    reason: reason,
    leadPersona: leadPersona,
    coagentPersona: coagentPersona,
    task: enabled ? taskFor(leadPersona, message) : "",
    context: enabled ? buildContext(input, coagentPersona) : [],
    requestedCapabilities: scopes.read,
    grantedCapabilities: scopes.read,
    allowlistedCapabilities: scopes.read,
    sideEffectCapabilities: scopes.sideEffects,
    allowedToolNames: scopes.read,
    maxReviewRounds: 1,
    maxToolTurns: scopes.read.length ? 2 : 0,
    score: {technical: technicalScore, creative: creativeScore, cross: crossScore},
  };
}

module.exports = {
  evaluate: evaluate,
  toolScopes: toolScopes,
  _countSignals: countSignals,
};
