// Кто что сказал — это часть смысла истории, а не служебное поле.
//
// Раньше и Gemini-, и OpenAI-путь сворачивали любого автора, кроме "user", в
// одну роль: `role: 'model'` / `assistant`. Имя автора выбрасывалось.
//
// В Lobby это ломает разговор напрямую. Зейн отвечает первым, его реплика
// уходит в историю следующего вызова — и Нирвана получает её как СВОЙ
// предыдущий ответ. Дальше она продолжает начатую мысль в чужой манере, и на
// экране под именем Нирваны говорит Зейн. Никакая инструкция в системном
// промпте это не перебивает: история весит больше, потому что выглядит как
// собственная речь.
//
// То же и с результатами инструментов: помеченные как речь модели, они
// превращаются в «я сам это сказал» вместо «сервер вернул данные».
//
// Правило простое: своей речью считается только речь текущей персоны.
// Реплика другого участника — это входящая речь, а не своя.

const PERSONA_LABELS = {zane: 'Зейн', nirvana: 'Нирвана'};

function labelFor(author) {
  return PERSONA_LABELS[author] || author;
}

/**
 * Приводит историю к списку {role: 'user'|'model', text}.
 * Роли те же, что понимает провайдер; личность сохраняется в тексте.
 */
export function speakerTurns(input) {
  const speaker = String(input?.persona || '').trim().toLowerCase();
  const turns = [];
  for (const item of Array.isArray(input?.history) ? input.history : []) {
    const text = String(item?.text ?? '').trim();
    if (!text) continue;
    const author = String(item?.author ?? '').trim().toLowerCase();

    if (author === 'user') {
      turns.push({role: 'user', text});
      continue;
    }
    if (author === 'tool') {
      turns.push({role: 'user', text: `[Результат инструмента]\n${text}`});
      continue;
    }
    // Пустой speaker — обычный одиночный чат: делить некого, вся прошлая
    // речь модели остаётся своей.
    if (!speaker || !author || author === speaker) {
      turns.push({role: 'model', text});
      continue;
    }
    turns.push({role: 'user', text: `[${labelFor(author)}]: ${text}`});
  }
  return turns;
}

/**
 * Склеивает подряд идущие реплики одной роли. Провайдеры допускают
 * чередование ролей и на длинной цепочке одинаковых ролей ведут себя
 * по-разному; склейка убирает эту зависимость.
 */
export function mergeAdjacent(turns) {
  const merged = [];
  for (const turn of turns) {
    const last = merged[merged.length - 1];
    if (last && last.role === turn.role) last.text = `${last.text}\n\n${turn.text}`;
    else merged.push({role: turn.role, text: turn.text});
  }
  return merged;
}

export function geminiContents(input) {
  return mergeAdjacent(speakerTurns(input)).map((turn) => ({role: turn.role, parts: [{text: turn.text}]}));
}

export function openAiHistory(input) {
  return mergeAdjacent(speakerTurns(input)).map((turn) => ({
    role: turn.role === 'model' ? 'assistant' : 'user',
    content: turn.text,
  }));
}
