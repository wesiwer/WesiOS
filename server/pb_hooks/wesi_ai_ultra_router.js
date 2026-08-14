module.exports = {
  plan: function(message, routes) {
    const text = String(message || '').trim();
    const words = text ? text.split(/\s+/).length : 0;
    const lower = text.toLowerCase();
    let score = 0;

    if (text.length > 800) score += 2;
    else if (text.length > 280) score += 1;
    if (words > 140) score += 2;
    else if (words > 50) score += 1;
    if (/```|\b(code|код|архитектур|рефактор|debug|ошибк|stack trace|sql|api|flutter|dart|javascript|python)\b/i.test(text)) score += 2;
    if (/\b(проанализ|сравни|стратег|докажи|обоснуй|исслед|рассуж|планирован|многошаг|оптимиз|аудит)\b/i.test(lower)) score += 2;
    if (/\b(привет|спасибо|как дела|который час|переведи|исправь опечатку|кратко|одно слово)\b/i.test(lower) && text.length < 180) score -= 2;

    const level = score >= 4 ? 'high' : score >= 2 ? 'medium' : 'low';
    const orderedLevels = level === 'high'
      ? ['high', 'medium', 'low']
      : level === 'medium'
        ? ['medium', 'low', 'high']
        : ['low', 'medium', 'high'];
    const seen = {};
    const candidates = [];
    for (const item of orderedLevels) {
      const route = String(routes && routes[item] || '').trim();
      if (!route || seen[route]) continue;
      seen[route] = true;
      candidates.push({level: item, route: route});
    }
    return {complexity: level, candidates: candidates};
  },

  shouldFallback: function(result) {
    if (!result || result.ok === true) return false;
    const code = String(result.code || '');
    return result.status === 429 ||
      result.status === 503 ||
      code === 'WAI_PROVIDER_RATE_LIMIT' ||
      code === 'WAI_PROVIDER_UNAVAILABLE' ||
      code === 'WAI_PROVIDER_TIMEOUT' ||
      code === 'WAI_PROVIDER_NOT_CONFIGURED' ||
      code === 'WAI_PROVIDER_MODEL_NOT_FOUND';
  }
};
