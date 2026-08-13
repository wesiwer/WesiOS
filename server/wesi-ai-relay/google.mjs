export function parseGoogleRoute(route) {
  const match = /^google\/([A-Za-z0-9._-]{2,100})$/.exec(String(route || '').trim());
  return match ? {model: match[1]} : null;
}

export async function callGoogleText(model, input, apiKey) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const history = [];
  for (const item of Array.isArray(input.history) ? input.history : []) {
    const text = String(item?.text || '');
    if (text) history.push({role: String(item?.author || '') === 'user' ? 'user' : 'model', parts: [{text}]});
  }
  history.push({role: 'user', parts: [{text: String(input.message || '')}]});
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: 'POST',
    headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
    body: JSON.stringify({systemInstruction: {parts: [{text: String(input.system || '')}]}, contents: history}),
    signal: AbortSignal.timeout(120000),
  });
  let data = {};
  try { data = await response.json(); } catch {}
  if (!response.ok) return {ok: false, status: response.status === 429 ? 429 : 502, code: response.status === 429 ? 'WAI_PROVIDER_RATE_LIMIT' : 'WAI_PROVIDER_REJECTED'};
  const parts = data?.candidates?.[0]?.content?.parts;
  const answer = Array.isArray(parts) ? parts.map((p) => typeof p?.text === 'string' ? p.text : '').join('').trim() : '';
  return answer ? {ok: true, answer} : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
}
