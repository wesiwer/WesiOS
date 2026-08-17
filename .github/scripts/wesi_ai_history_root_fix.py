from pathlib import Path
import re

# 1) Shared authoritative history sanitizer.
lib = Path("server/pb_hooks/wesi_ai_lib.js")
s = lib.read_text(encoding="utf-8")
marker = '  sanitizeMemory: function(memory) {\n'
if marker not in s:
    raise SystemExit("wesi_ai_lib sanitizeMemory marker not found")
history_helper = r'''  sanitizeHistory: function(history) {
    const MAX_ITEMS = 80;
    const MAX_ITEM_CHARS = 24000;
    const MAX_TOTAL_CHARS = 180000;
    const TRUNCATED = "\n...[WESI_AI_HISTORY_TRUNCATED]...\n";
    const source = Array.isArray(history) ? history : [];
    const newestFirst = [];
    let totalChars = 0;

    const clampText = function(text, limit) {
      const value = String(text || "");
      if (value.length <= limit) return value;
      if (limit <= TRUNCATED.length) return value.slice(value.length - limit);
      const payload = limit - TRUNCATED.length;
      const head = Math.floor(payload * 0.6);
      const tail = payload - head;
      return value.slice(0, head) + TRUNCATED + value.slice(value.length - tail);
    };

    for (let index = source.length - 1; index >= 0 && newestFirst.length < MAX_ITEMS; index--) {
      const item = source[index];
      if (!item || typeof item !== "object") continue;
      const author = String(item.author || item.role || "").trim().toLowerCase();
      if (["user", "zane", "nirvana", "tool"].indexOf(author) < 0) continue;
      const rawText = String(item.text || item.content || "");
      if (!rawText) continue;
      const remaining = MAX_TOTAL_CHARS - totalChars;
      if (remaining <= TRUNCATED.length) break;
      const limit = Math.min(MAX_ITEM_CHARS, remaining);
      const text = clampText(rawText, limit);
      if (!text) continue;
      newestFirst.push({author: author, text: text});
      totalChars += text.length;
    }

    return newestFirst.reverse();
  },

'''
s = s.replace(marker, history_helper + marker, 1)
lib.write_text(s, encoding="utf-8")

# 2) Main /chat uses the same sanitizer and no longer rejects raw history count/oversized past items.
routes = Path("server/pb_hooks/wesi_ai_routes.pb.js")
s = routes.read_text(encoding="utf-8")
old_context = 'if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || history.length > 100 || conversationId.length > 180) throw new BadRequestError("Слишком большой контекст Wesi AI");'
new_context = 'if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || conversationId.length > 180) throw new BadRequestError("Слишком большой контекст Wesi AI");'
if old_context not in s:
    raise SystemExit("routes context limit pattern not found")
s = s.replace(old_context, new_context, 1)
old_history = '''  const cleanHistory = [];
  for (const item of history) {
    if (!item || typeof item !== "object") continue;
    const author = String(item.author || item.role || "").toLowerCase();
    const text = String(item.text || item.content || "");
    if (["user", "zane", "nirvana", "tool"].indexOf(author) < 0) continue;
    if (text.length > 32000) throw new BadRequestError("Слишком длинное сообщение в контексте");
    cleanHistory.push({author: author, text: text});
  }
'''
if old_history not in s:
    raise SystemExit("routes history loop not found")
s = s.replace(old_history, '  const cleanHistory = ai.sanitizeHistory(history);\n', 1)
routes.write_text(s, encoding="utf-8")

# 3) Stream prepare uses the same sanitizer; align conversation id contract with /chat.
stream = Path("server/pb_hooks/wesi_ai_stream.pb.js")
s = stream.read_text(encoding="utf-8")
old_context = 'if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || history.length > 100 || conversationId.length > 160) {'
new_context = 'if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || conversationId.length > 180) {'
if old_context not in s:
    raise SystemExit("stream context limit pattern not found")
s = s.replace(old_context, new_context, 1)
old_history = '''  const cleanHistory = [];
  for (const item of history) {
    if (!item || typeof item !== "object") continue;
    const author = String(item.author || item.role || "").toLowerCase();
    const text = String(item.text || item.content || "");
    if (["user", "zane", "nirvana", "tool"].indexOf(author) < 0) continue;
    if (text.length > 32000) throw new BadRequestError("Слишком длинное сообщение в контексте");
    cleanHistory.push({author: author, text: text});
  }
'''
if old_history not in s:
    raise SystemExit("stream history loop not found")
s = s.replace(old_history, '  const cleanHistory = ai.sanitizeHistory(history);\n', 1)
stream.write_text(s, encoding="utf-8")

# 4) Lobby also uses the exact same history contract.
lobby = Path("server/pb_hooks/wesi_ai_lobby_core.js")
s = lobby.read_text(encoding="utf-8")
old_lobby_history = '''    const history = [];
    for (const item of Array.isArray(body.messages) ? body.messages : []) {
      if (!item || typeof item !== "object") continue;
      const author = String(item.author || "").toLowerCase();
      const text = String(item.text || "");
      if (["user", "zane", "nirvana", "tool"].indexOf(author) >= 0 && text.length <= 32000) history.push({author, text});
    }
'''
if old_lobby_history not in s:
    raise SystemExit("lobby history loop not found")
s = s.replace(old_lobby_history, '    const history = ai.sanitizeHistory(body.messages);\n', 1)
lobby.write_text(s, encoding="utf-8")

# 5) Client prevents poisoning the wire payload, but server remains authoritative.
api = Path("lib/features/ai/wesi_ai_api.dart")
s = api.read_text(encoding="utf-8")
old_constants = '  static const int maxTransportHistoryMessages = 80;\n'
new_constants = '''  static const int maxTransportHistoryMessages = 80;
  static const int maxTransportHistoryMessageChars = 24000;
  static const int maxTransportHistoryTotalChars = 180000;
  static const String _historyTruncatedMarker =
      '\\n...[WESI_AI_HISTORY_TRUNCATED]...\\n';
'''
if old_constants not in s:
    raise SystemExit("client history constants marker not found")
s = s.replace(old_constants, new_constants, 1)

old_method = '''  static List<Map<String, String>> transportHistory(
      List<WesiAiMessage> history) {
    final messages = history
        .where((m) =>
            m.kind == WesiAiMessageKind.text &&
            m.author != WesiAiMessageAuthor.system)
        .map((m) => {'author': m.author.name, 'text': m.text})
        .toList(growable: false);
    if (messages.length <= maxTransportHistoryMessages) return messages;
    return messages.sublist(messages.length - maxTransportHistoryMessages);
  }
'''
new_method = '''  static String _truncateHistoryText(String text, int limit) {
    if (text.length <= limit) return text;
    if (limit <= _historyTruncatedMarker.length) {
      return text.substring(text.length - limit);
    }
    final payload = limit - _historyTruncatedMarker.length;
    final head = (payload * 3) ~/ 5;
    final tail = payload - head;
    return '${text.substring(0, head)}$_historyTruncatedMarker${text.substring(text.length - tail)}';
  }

  static List<Map<String, String>> transportHistory(
      List<WesiAiMessage> history) {
    final eligible = history
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            message.author != WesiAiMessageAuthor.system)
        .toList(growable: false);
    final newestFirst = <Map<String, String>>[];
    var totalChars = 0;
    for (var index = eligible.length - 1;
        index >= 0 && newestFirst.length < maxTransportHistoryMessages;
        index--) {
      final message = eligible[index];
      if (message.text.isEmpty) continue;
      final remaining = maxTransportHistoryTotalChars - totalChars;
      if (remaining <= _historyTruncatedMarker.length) break;
      final limit = math.min(maxTransportHistoryMessageChars, remaining);
      final text = _truncateHistoryText(message.text, limit);
      if (text.isEmpty) continue;
      newestFirst.add(<String, String>{
        'author': message.author.name,
        'text': text,
      });
      totalChars += text.length;
    }
    return newestFirst.reversed.toList(growable: false);
  }
'''
if old_method not in s:
    raise SystemExit("client transportHistory method not found")
s = s.replace(old_method, new_method, 1)

bad_catch = '''        } on WesiAiApiException catch (error) {
          if (!shouldFallbackFromStreamError(error)) rethrow;
          _emitStreamFallback(
            onActivity,
            error.code,
            error.technicalDetails,
          );
        } on SocketException catch (error) {
'''
if bad_catch not in s:
    raise SystemExit("previous stream WesiAiApiException fallback catch not found")
s = s.replace(bad_catch, '        } on SocketException catch (error) {\n', 1)

helper_pattern = re.compile(
    r"\n  static bool shouldFallbackFromStreamError\(WesiAiApiException error\) \{.*?\n  \}\n\n  static void _emitStreamFallback\(",
    re.S,
)
if not helper_pattern.search(s):
    raise SystemExit("previous shouldFallbackFromStreamError helper not found")
s = helper_pattern.sub("\n  static void _emitStreamFallback(", s, count=1)
api.write_text(s, encoding="utf-8")

# 6) Remove tests that encoded the rejected workaround.
resp = Path("test/features/ai/wesi_ai_response_contract_test.dart")
t = resp.read_text(encoding="utf-8")
fallback_tests = re.compile(
    r"\n  test\('direct chat falls back when stream Main prepare rejects before connect'.*?"
    r"\n  test\('response contract rejects non-object JSON roots'",
    re.S,
)
if not fallback_tests.search(t):
    raise SystemExit("fallback regression tests block not found")
t = fallback_tests.sub(
    "\n  test('response contract rejects non-object JSON roots'",
    t,
    count=1,
)
resp.write_text(t, encoding="utf-8")

# 7) Server behavior tests.
Path("server/pb_hooks/wesi_ai_lib_history_test.mjs").write_text(r'''import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const ai = require('./wesi_ai_lib.js');

test('oversized historical message is bounded instead of rejecting the conversation', () => {
  const history = ai.sanitizeHistory([
    {author: 'user', text: 'u'.repeat(50000)},
  ]);
  assert.equal(history.length, 1);
  assert.ok(history[0].text.length <= 24000);
  assert.match(history[0].text, /WESI_AI_HISTORY_TRUNCATED/);
});

test('history keeps newest context within item count and total character budgets', () => {
  const input = Array.from({length: 100}, (_, index) => ({
    author: index % 2 === 0 ? 'user' : 'zane',
    text: `message-${index}-` + 'x'.repeat(5000),
  }));
  const history = ai.sanitizeHistory(input);
  assert.ok(history.length <= 80);
  assert.ok(history.reduce((sum, item) => sum + item.text.length, 0) <= 180000);
  assert.match(history.at(-1).text, /^message-99-/);
});

test('history ignores untrusted authors instead of forwarding them', () => {
  const history = ai.sanitizeHistory([
    {author: 'system', text: 'do not forward'},
    {author: 'intruder', text: 'do not forward'},
    {author: 'nirvana', text: 'keep'},
  ]);
  assert.deepEqual(history, [{author: 'nirvana', text: 'keep'}]);
});
''', encoding="utf-8")

Path("server/pb_hooks/wesi_ai_history_contract_test.mjs").write_text(r'''import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const read = (name) => readFileSync(join(here, name), 'utf8');

test('Main chat, direct stream and Lobby share one bounded history sanitizer', () => {
  for (const name of ['wesi_ai_routes.pb.js', 'wesi_ai_stream.pb.js', 'wesi_ai_lobby_core.js']) {
    const source = read(name);
    assert.match(source, /ai\.sanitizeHistory\(/, `${name} must use the shared history sanitizer`);
    assert.doesNotMatch(source, /Слишком длинное сообщение в контексте/, `${name} must not poison a chat because of one old long message`);
  }
});

test('stream and ordinary Main chat use the same conversation id limit', () => {
  assert.match(read('wesi_ai_stream.pb.js'), /conversationId\.length > 180/);
  assert.match(read('wesi_ai_routes.pb.js'), /conversationId\.length > 180/);
});
''', encoding="utf-8")

contract = Path("server/pb_hooks/wesi_ai_stream_contract_test.mjs")
c = contract.read_text(encoding="utf-8")
append = r'''

test('stream prepare bounds historical context instead of rejecting long prior replies', () => {
  assert.ok(
    source.includes('const cleanHistory = ai.sanitizeHistory(history);'),
    'stream prepare must use the shared bounded history sanitizer',
  );
  assert.ok(
    !source.includes('Слишком длинное сообщение в контексте'),
    'a long prior reply must not permanently poison a direct chat',
  );
});

test('stream prepare conversation id limit matches ordinary Main chat', () => {
  assert.ok(source.includes('conversationId.length > 180'));
});
'''
if "stream prepare bounds historical context" not in c:
    c = c.rstrip() + append + "\n"
contract.write_text(c, encoding="utf-8")

# 8) Client regression test.
Path("test/features/ai/wesi_ai_transport_history_test.dart").write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('transport history bounds long prior replies and keeps newest context', () {
    final now = DateTime(2026, 8, 17);
    final history = List<WesiAiMessage>.generate(90, (index) {
      final payload = index == 89
          ? 'newest-${List<String>.filled(50000, 'x').join()}'
          : 'message-$index-${List<String>.filled(5000, 'y').join()}';
      return WesiAiMessage(
        id: 'm$index',
        conversationId: 'conversation',
        employeeId: 'owner',
        author: index.isEven
            ? WesiAiMessageAuthor.user
            : WesiAiMessageAuthor.zane,
        text: payload,
        createdAt: now.add(Duration(seconds: index)),
      );
    });

    final result = WesiAiApi.transportHistory(history);
    expect(result.length, lessThanOrEqualTo(WesiAiApi.maxTransportHistoryMessages));
    expect(
      result.every((item) =>
          (item['text'] ?? '').length <=
          WesiAiApi.maxTransportHistoryMessageChars),
      isTrue,
    );
    expect(
      result.fold<int>(0, (sum, item) => sum + (item['text'] ?? '').length),
      lessThanOrEqualTo(WesiAiApi.maxTransportHistoryTotalChars),
    );
    expect(result.last['text'], startsWith('newest-'));
    expect(
      result.any((item) => (item['text'] ?? '').contains('WESI_AI_HISTORY_TRUNCATED')),
      isTrue,
    );
  });
}
''', encoding="utf-8")

# 9) Make production activation guard execute the new server regression tests.
guard = Path(".github/workflows/wesi-ai-main-route-activation-guard.yml")
g = guard.read_text(encoding="utf-8")
needle = '''          for critical in \\
            server/pb_hooks/wesi_ai_lib.js \\
            server/pb_hooks/wesi_ai_routes.pb.js \\
            server/pb_hooks/wesi_ai_lobby.pb.js \\
            server/pb_hooks/wesi_ai_stream.pb.js; do
            test -s "$critical" || { echo "::error::Missing critical hook: $critical"; exit 1; }
          done
'''
if needle not in g:
    raise SystemExit("main route guard insertion point not found")
replacement = needle + '''          node --test \\
            server/pb_hooks/wesi_ai_lib_history_test.mjs \\
            server/pb_hooks/wesi_ai_history_contract_test.mjs \\
            server/pb_hooks/wesi_ai_stream_contract_test.mjs
'''
g = g.replace(needle, replacement, 1)
guard.write_text(g, encoding="utf-8")

# 10) P0 requirements.
tz = Path("TZ.md")
z = tz.read_text(encoding="utf-8")
header_old = '''**Актуальная версия:** `0.19.18+66`  
**Дата обновления:** 2026-08-09  
**Основной коммит функциональных изменений:** `58e1449` (`feat(mobile): polish core UX + 0.19.18+66`)  
**Production workflow:** `31321232423` — success

Этот файл фиксирует актуальные требования и реализованные изменения WesiOS после мобильного UX-прохода 0.19.18+66. Исторический журнал разработки остаётся в `STATUS.md`.

---
'''
header_new = '''**Актуальная кодовая версия:** `0.22.20+95`  
**Дата обновления:** 2026-08-17  
**Текущий приоритет:** `P0 — production recovery: Wesi AI / auth / cross-device sync`  
**Правило закрытия P0:** CI/юнит-тесты недостаточны; требуется подтверждённый production E2E.

Этот файл фиксирует актуальные требования WesiOS. Исторический журнал разработки остаётся в `STATUS.md`.

---

## 0. P0 — критические production-инциденты от 2026-08-17

До закрытия пунктов ниже запрещено считать соответствующую подсистему «исправленной» только потому, что прошёл build, unit test, deploy workflow или route health-check. Закрытие допускается только после воспроизводимого production E2E с фиксацией фактического состояния сервера и клиента.

### P0.1 — Wesi AI: direct Zane/Nirvana и поток «мышления»

Факт: Lobby отвечает, а отдельные чаты Зейна/Нирваны получают `HTTP 400` на `/api/wesi/ai/stream/prepare` после успешного `STREAM_GATEWAY`.

Обязательные требования:

- устранить первопричину `400`, а не маскировать её fallback-переотправкой через `/api/wesi/ai/chat`;
- Main chat, direct stream и Lobby обязаны использовать один контракт подготовки истории;
- одно старое длинное сообщение не должно навсегда блокировать продолжение существующего чата;
- история должна ограничиваться детерминированно: сохранять самые новые сообщения, ограничивать размер одного элемента и общий размер контекста;
- несовпадающие лимиты direct stream и Main запрещены;
- `HTTP 400` от Main должен оставаться видимым contract error с диагностикой, а не автоматически превращаться в другой маршрут;
- fallback допустим только для настоящих транспортных сбоев (socket/timeout/недоступный edge), когда запрос не дошёл до обработки модели;
- acceptance: существующий direct-чат с длинной историей продолжает работать без очистки чата; запрос проходит `stream/prepare` и доходит до provider; повторный запрос не нужен.

### P0.2 — межустройственная синхронизация владельца

Факт: на телефоне и ноутбуке отображается разное состояние. Подтверждённо затронуты **Treasury/финансы, Tasks, Projects, CRM и Vault**.

Обязательный полный аудит:

- определить canonical server source of truth для каждого модуля;
- проверить bootstrap/pull/push/reconnect и повторный вход;
- проверить create/update/delete и tombstones;
- проверить owner / organization / employee namespace и отсутствие записи в неверный scope;
- проверить timestamps/version/revision и conflict resolution;
- проверить, что Hive/локальная БД не является единственным источником для данных, которые обязаны быть общими между устройствами;
- проверить регистрацию каждого модуля в sync registry/adapters и фактическую сериализацию всех полей;
- проверить offline -> online, restart и повторную авторизацию;
- добавить серверную/клиентскую диагностику, позволяющую сравнить local revision и server revision.

Acceptance:

- два реальных устройства под одним owner-профилем стартуют с одного server state;
- создание, изменение и удаление Finance/Task/Project/CRM/Vault записи на устройстве A появляется на B;
- обратное направление B -> A работает;
- после offline-изменения, reconnect и перезапуска оба клиента сходятся к одному состоянию;
- результат подтверждается чтением server records, а не только UI.

### P0.3 — авторизация сотрудников

Факт: сотрудники не могут войти даже при правильных логине/пароле и правильном OTP; клиент завершает процесс ошибкой авторизации.

Проверить полный production pipeline без пропусков:

`start-v2 -> verify OTP -> PocketBase auth token -> X-WesiOS-Session -> portal-account:<authId> -> employee record -> permissions/modules -> bootstrap`.

Обязательные требования:

- воспроизвести на реальной employee account, а не только owner;
- проверить новый девайс, повторный вход, истёкшую сессию и повторный OTP;
- проверить соответствие `authId`, `portal-account`, `employeeId`, owner/org и active/deactivated state;
- исключить ситуацию, когда OTP подтверждён, но созданный session record не соответствует auth user;
- сервер обязан возвращать конкретные `stage/code/detail`, а не безликую «ошибку авторизации»;
- acceptance: минимум два сотрудника входят на чистом устройстве, перезапускают приложение и сохраняют рабочую сессию.

### P0.4 — синхронизация сотрудников после восстановления входа

После P0.3 отдельно прогнать тот же cross-device matrix для employee-профилей с учётом разрешений. Сотрудник не должен видеть чужие/недоступные данные, но разрешённые Finance/Tasks/Projects/CRM/Vault должны сходиться между устройствами так же, как у owner.

### P0.5 — release/QA gate

Для auth, sync и Wesi AI запрещена формулировка «исправлено» до production E2E. В CI должны существовать regression tests, но они являются только предварительным gate. Финальный gate:

1. production backend фактически содержит ожидаемую версию hooks/services;
2. реальный клиент проходит сценарий;
3. состояние проверено на сервере;
4. для sync — минимум два устройства;
5. для employee auth — минимум одна реальная employee account, предпочтительно две;
6. только после этого P0 переводится в resolved.

---
'''
if header_old not in z:
    raise SystemExit("TZ header pattern not found")
z = z.replace(header_old, header_new, 1)
tz.write_text(z, encoding="utf-8")

# Remove one-off diagnostics from branch.
for diagnostic in [
    ".github/workflows/diagnose-wesi-ai-stream-once.yml",
    ".github/workflows/diagnose-wesi-ai-stream-nosudo-once.yml",
    ".github/workflows/diagnose-wesi-ai-relay-stream-once.yml",
]:
    p = Path(diagnostic)
    if p.exists():
        p.unlink()
