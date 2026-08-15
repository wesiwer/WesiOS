# Wesi AI — observable chat UX

Этот слой отвечает только за представление и наблюдаемость работы Wesi AI.

## Контент ответа

- fenced code рендерится отдельным code block с названием языка, быстрым копированием и полноэкранным просмотром;
- blockquote и fenced `text/message/email/draft/letter` рендерятся как переносимый текст с вертикальной линией и copy;
- inline `**bold**`, `*italic*`, `` `code` `` не показывают служебные markdown-маркеры;
- копирование полного ответа использует plain-text представление без markdown-обвязки.

## Ход работы

WesiOS не показывает скрытую chain-of-thought модели. Вместо неё UI показывает фактический work log: подготовку контекста, выбранный маршрут, инструментальные вызовы, агентов, проверки и статусы, которые реально пришли из streaming protocol. Пока ответ выполняется, блок раскрыт автоматически; после завершения его можно раскрыть вручную.

`tool` / `agent` activity хранит `textOffset`, поэтому renderer может вставлять событие в ту позицию ответа, в которой оно произошло. События сохраняются вместе с сообщением и переживают перезапуск приложения.

## Diff stats

Зелёное `+N` и красное `-N` — число добавленных/удалённых строк. Статистика хранится отдельно для каждого tool/agent event и агрегируется в message diff badge. Для `github_file_upsert` цифры берутся из GitHub commit detail после успешного PUT, а не вычисляются приблизительно на клиенте.

## Действия сообщения

Под завершённым ответом доступны: copy, сохранить/убрать из архива текущего чата, создать conversation branch от выбранного сообщения, открыть diff review. Архив не глобальный: сохранённые сообщения фильтруются только в пределах текущей conversation.

## Камера

Камера Wesi AI открывается модальным окном с ограниченной шириной/высотой. Внутренний `CameraPreview` продолжает использовать аппаратный aspect ratio, поэтому изображение не растягивается на весь экран и не деформируется.

## Contextual follow-ups and clarification

- follow-up chips derive their topic from the latest user turn/current answer and must not be a fixed repeated list;
- a valid fenced `question` JSON block renders 2–5 quick answers and optional `Свой ответ`;
- selecting an option is an ordinary user turn; malformed question JSON fails back to code rendering;
- a pending clarification suppresses generic follow-up chips;
- Zane/Nirvana identity/company/platform facts are contextual and are not injected into unrelated answers;
- a newly opened chat is a transient draft and enters durable history only after the first accepted user turn.
