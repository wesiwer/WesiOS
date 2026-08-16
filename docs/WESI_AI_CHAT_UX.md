# Wesi AI — observable chat UX

Этот слой отвечает только за представление и наблюдаемость работы Wesi AI.

## Контент ответа

- fenced code рендерится отдельным code block с названием языка, быстрым копированием и полноэкранным просмотром;
- blockquote и fenced `text/message/email/draft/letter` рендерятся как переносимый текст с вертикальной линией и copy;
- inline `**bold**`, `*italic*`, `` `code` `` не показывают служебные markdown-маркеры;
- копирование полного ответа использует plain-text представление без markdown-обвязки.

## Ход работы

WesiOS не показывает скрытую chain-of-thought модели. В режиме «Думающий» UI показывает фактический work log: подготовку контекста, выбранный маршрут, инструментальные вызовы, агентов, проверки и статусы, которые реально известны WesiOS. Пока ответ выполняется, блок раскрыт автоматически; после завершения его можно раскрыть вручную. В режиме «Классический» плашка «Ход работы» не рендерится вообще.

Прямой streaming transport добавляет промежуточные `meta/tool/agent/activity` события по мере выполнения. Если streaming gateway недоступен, клиент безопасно откатывается на основной `/api/wesi/ai/chat`: в «Думающем» work log фактически показывает переключение на основной маршрут, ожидание verified ответа и подтверждение получения ответа, а после результата добавляет реальные tool results. Такой fallback не изображает скрытые мысли модели и не выдаётся за token-by-token reasoning.

`tool` / `agent` activity хранит `textOffset`, поэтому renderer может вставлять событие в ту позицию ответа, в которой оно произошло. События сохраняются вместе с сообщением и переживают перезапуск приложения.

## Навигация и служебные настройки

Коннекторы, память и бэкап/перенос находятся в боковой панели Wesi AI рядом с проектами и чатами. В верхней панели эти действия не дублируются, чтобы не загромождать основной экран диалога. На узком экране тот же блок доступен через drawer.

## Diff stats

Зелёное `+N` и красное `-N` — число добавленных/удалённых строк. Статистика хранится отдельно для каждого tool/agent event и агрегируется в message diff badge. Для `github_file_upsert` цифры берутся из GitHub commit detail после успешного PUT, а не вычисляются приблизительно на клиенте.

## Действия сообщения

Под завершённым ответом доступны: copy, сохранить/убрать из архива текущего чата, создать conversation branch от выбранного сообщения, открыть diff review. Архив не глобальный: сохранённые сообщения фильтруются только в пределах текущей conversation.

## Камера

Камера Wesi AI открывается модальным окном с ограниченной шириной/высотой. Внутренний `CameraPreview` продолжает использовать аппаратный aspect ratio, поэтому изображение не растягивается на весь экран и не деформируется.

## Contextual follow-ups and clarification

Post-Stage-10 UX/persona hardening: stable PR #181, main merge `95cdbb9c6a4f50b22636ea6eabaed093bbb1dec0`. Старый рабочий PR #180 закрыт как superseded и не должен использоваться как source of truth.

- follow-up chips derive their topic from the latest user turn/current answer and must not be a fixed repeated list;
- follow-ups are also intent-aware: debugging/errors, planning/implementation, comparison/choice, finance/calculation, creative work and explanatory questions receive different continuation actions rather than the same three generic templates;
- a valid fenced `question` JSON block renders 2–5 quick answers and optional `Свой ответ`;
- selecting an option is an ordinary user turn; malformed question JSON fails back to code rendering;
- a pending clarification suppresses generic follow-up chips;
- Zane/Nirvana identity/company/platform facts are contextual and are not injected into unrelated answers;
- creator/Wesi Inc./Wesi AI/WesiOS may be mentioned when the user asks about identity, origin, creator, company/owner, platform/ecosystem or when objectively required by the task;
- a newly opened chat is a transient draft and enters durable history only after the first accepted user turn;
- opening another blank new chat abandons the previous blank draft instead of accumulating empty conversations;
- queue/attachment context remains durable for conversations that have already been materialized by an accepted turn.

Эта механика дополнительно прошла интеграционные gates уже поверх следующего visual/persona PR #182 (`817f23f8d7d1712c3373db33403f646c01d3bcba`, main merge `fbc2fc2beca6581d090845d8e7542dd7c063b612`): persona validation, analyze, полный Flutter test, Android debug APK и Windows release — green.

## Таблицы и графики в ответах

- Markdown-таблицы рендерятся как отдельные горизонтально прокручиваемые таблицы с быстрым копированием TSV.
- Для числовых визуализаций поддерживается fenced-блок `wesi-chart` с bounded JSON-spec и типами `bar`, `line`, `pie`, `scatter`.
- Chart renderer не исполняет JS/HTML/Flutter-код; malformed или oversized spec fail-closed показывается как обычный code block.
- Визуализация хранится прямо в тексте сообщения, поэтому сохраняется в истории, архиве и ветках без отдельного серверного состояния.
