// Что именно ушло в инструмент и что он вернул.
//
// Раньше клиент получал только имя, признак успеха и пару полей сводки:
// «Инструмент · finance_summary» — и всё. Развернуть шаг и посмотреть, с
// какими аргументами его звали и что пришло в ответ, было нельзя, а без
// этого длинный проход невозможно проверить: человек видит два десятка
// строк и обязан верить им на слово.
//
// Модуль отдельный, а не внутри шлюза, потому что тем же занят оркестратор
// субагентов, а шлюз его уже импортирует — общий код в шлюзе замкнул бы
// импорты в кольцо.
//
// Обрезка жёсткая: это ход мыслей, а не хранилище. Полный результат и так
// уходит модели; здесь ровно столько, чтобы человек мог убедиться.
export const MAX_STEP_IO_CHARS = 4000;

function stepPayloadText(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value.slice(0, MAX_STEP_IO_CHARS);
  try {
    const text = JSON.stringify(value, null, 2);
    return typeof text === 'string' ? text.slice(0, MAX_STEP_IO_CHARS) : '';
  } catch (_) {
    // Циклические ссылки и прочая экзотика не должны ронять весь проход.
    return '';
  }
}

export function stepIo(toolRequest, toolResult) {
  const input = stepPayloadText(toolRequest && toolRequest.arguments);
  // Результат инструмента лежит в result; если его нет, показываем сам ответ
  // без служебной обёртки, иначе человек увидит только {ok:false}.
  const rawOutput = toolResult && typeof toolResult === 'object' && 'result' in toolResult
    ? toolResult.result
    : toolResult;
  const output = stepPayloadText(rawOutput);
  const io = {};
  if (input) io.input = input;
  if (output) io.output = output;
  return io;
}
