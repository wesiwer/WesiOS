module.exports = {
  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson) {
    const parts = [profile.prompt, "[WESI_AI_LOBBY]\nYou are in shared Lobby. Speak only as yourself; never write lines for the other participant."];
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
    if (projectContext) parts.push("[WESI_AI_PROJECT_CONTEXT]\n" + projectContext);
    if (taskStateJson && taskStateJson !== "{}") parts.push("[WESI_AI_TASK_STATE]\n" + taskStateJson);
    if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\n" + sharedMemory.join("\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
    if (projectMemory.length) parts.push("[WESI_AI_PROJECT_MEMORY]\n" + projectMemory.join("\n"));
    if (priorTurns.length) parts.push("[WESI_AI_CURRENT_LOBBY_TURNS]\n" + JSON.stringify(priorTurns));
    const payload = {requestId, route, operation: "lobby", input: {
      system: parts.join("\n\n"), history: history.concat(priorTurns), message
    }};
    return ai.callRelay(cfg, payload, requestId);
  }
};
