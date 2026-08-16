function clean(value) {
  return String(value || "").trim().toLowerCase().replace(/ё/g, "е");
}

function personaIdentity(personaName) {
  if (personaName === "nirvana") {
    return {
      self: "Нирвана",
      other: "Зейн",
      boundary: [
        "[WESI_AI_LOBBY_IDENTITY_V2]",
        "Твоя неизменяемая личность: Нирвана. Ты говоришь только от первого лица Нирваны.",
        "Зейн — отдельный участник. Никогда не пиши реплики от его лица, не изображай его, не подписывай его слова собой и не говори о себе как о Нирване в третьем лице.",
        "Если пользователь хочет позвать Зейна, это делает маршрутизатор Lobby; не симулируй его ответ самостоятельно.",
        "Сохраняй именно собственный профиль Нирваны. Не копируй резкую, циничную или ворчливую манеру Зейна только потому, что она встречалась в истории.",
        "Не добавляй метки 'Зейн:' или 'Нирвана:' — UI уже знает автора сообщения."
      ].join("\n")
    };
  }
  return {
    self: "Зейн",
    other: "Нирвана",
    boundary: [
      "[WESI_AI_LOBBY_IDENTITY_V2]",
      "Твоя неизменяемая личность: Зейн. Ты говоришь только от первого лица Зейна.",
      "Нирвана — отдельный участник. Никогда не пиши реплики от её лица, не изображай её, не подписывай её слова собой и не говори о себе как о Зейне в третьем лице.",
      "Если пользователь хочет позвать Нирвану, это делает маршрутизатор Lobby; не симулируй её ответ самостоятельно.",
      "Сохраняй именно собственный профиль Зейна и не перенимай голос Нирваны из предыдущих сообщений.",
      "Не добавляй метки 'Зейн:' или 'Нирвана:' — UI уже знает автора сообщения."
    ].join("\n")
  };
}

function identityViolation(personaName, answer) {
  const text = clean(answer);
  if (!text) return "empty";

  if (personaName === "nirvana") {
    if (text.indexOf("зейн:") === 0 || text.indexOf("zane:") === 0) return "other_label";
    if (text.indexOf("я зейн") >= 0 || text.indexOf("я — зейн") >= 0 || text.indexOf("i am zane") >= 0) return "other_identity";
    if (text.indexOf("позову нирвану") >= 0 || text.indexOf("позвать нирвану") >= 0 || text.indexOf("сейчас позову нирвану") >= 0) return "self_summon";
    if (text.indexOf("нирвана б ") >= 0 || text.indexOf("нирвана бы ") >= 0 || text.indexOf("нирвана говорит") >= 0 || text.indexOf("нирвана думает") >= 0) return "self_third_person";
    return "";
  }

  if (text.indexOf("нирвана:") === 0 || text.indexOf("nirvana:") === 0) return "other_label";
  if (text.indexOf("я нирвана") >= 0 || text.indexOf("я — нирвана") >= 0 || text.indexOf("i am nirvana") >= 0) return "other_identity";
  if (text.indexOf("позову зейна") >= 0 || text.indexOf("позвать зейна") >= 0 || text.indexOf("сейчас позову зейна") >= 0) return "self_summon";
  if (text.indexOf("зейн б ") >= 0 || text.indexOf("зейн бы ") >= 0 || text.indexOf("зейн говорит") >= 0 || text.indexOf("зейн думает") >= 0) return "self_third_person";
  return "";
}

function buildSystem(personaName, profile, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson, repairReason) {
  const identity = personaIdentity(personaName);
  const parts = [
    profile.prompt,
    identity.boundary,
    "[WESI_AI_LOBBY]\nТы участник общего Lobby. Отвечай только своей репликой и только как " + identity.self + ". Реплики другого участника формирует отдельный вызов."
  ];
  if (repairReason) {
    parts.push(
      "[WESI_AI_LOBBY_REPAIR]\nПредыдущий черновик отклонён сервером из-за смешения личностей (" + repairReason + "). Сгенерируй ответ заново строго от лица " + identity.self + ". Не обсуждай сам факт проверки."
    );
  }
  if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
  if (projectContext) parts.push("[WESI_AI_PROJECT_CONTEXT]\n" + projectContext);
  if (taskStateJson && taskStateJson !== "{}") parts.push("[WESI_AI_TASK_STATE]\n" + taskStateJson);
  if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\n" + sharedMemory.join("\n"));
  if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
  if (projectMemory.length) parts.push("[WESI_AI_PROJECT_MEMORY]\n" + projectMemory.join("\n"));
  if (priorTurns.length) parts.push("[WESI_AI_CURRENT_LOBBY_TURNS]\n" + JSON.stringify(priorTurns));
  return parts.join("\n\n");
}

function invoke(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson, repairReason) {
  const payload = {requestId, route, operation: "lobby", input: {
    system: buildSystem(personaName, profile, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson, repairReason),
    history: history.concat(priorTurns),
    message
  }};
  return ai.callRelay(cfg, payload, requestId);
}

module.exports = {
  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson) {
    let result = invoke(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson, "");
    if (!result.ok) return result;

    const violation = identityViolation(personaName, result.answer);
    if (!violation) return result;

    const repaired = invoke(ai, cfg, route, requestId + "_repair", personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson, violation);
    if (!repaired.ok) return repaired;
    const secondViolation = identityViolation(personaName, repaired.answer);
    if (!secondViolation) return repaired;

    return {
      ok: false,
      status: 502,
      code: "WAI_LOBBY_PERSONA_CONFLICT",
      answer: ""
    };
  },
  _test: {
    identityViolation,
    personaIdentity
  }
};
