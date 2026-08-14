module.exports = {
  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, priorTurns, summary, emotionalState) {
    const parts = [
      profile.prompt,
      "[WESI_AI_LOBBY]\nYou are in shared Lobby. Speak only as yourself; never write lines for the other participant."
    ];
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
    if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\n" + sharedMemory.join("\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
    if (emotionalState) {
      parts.push(
        "[WESI_AI_EMOTIONAL_STATE]\n" + JSON.stringify(emotionalState) + "\n" +
        "Это внутреннее состояние персонажа. Мягко отражай его в тоне, инициативе, юморе и дистанции. " +
        "Не перечисляй эмоции без причины, не переигрывай и не манипулируй пользователем. " +
        "Незакрытые эмоциональные следы можно помнить, но время, извинения и позитивное взаимодействие должны естественно их смягчать."
      );
    }
    if (priorTurns.length) parts.push("[WESI_AI_CURRENT_LOBBY_TURNS]\n" + JSON.stringify(priorTurns));
    const payload = {requestId, route, operation: "lobby", input: {
      system: parts.join("\n\n"), history: history.concat(priorTurns), message
    }};
    return ai.callRelay(cfg, payload, requestId);
  }
};
