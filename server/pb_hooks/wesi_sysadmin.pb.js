/// Выполнение команд на сервере из консоли системного администратора.
///
/// Консоль в приложении умела делать сетевые проверки с телефона, но не
/// выполнять команды на самом сервере. Здесь появляется недостающая половина.
///
/// Что здесь важно и почему сделано именно так:
///
/// * Только владелец. Проверка та же, что у выдачи учётных записей: либо
///   суперпользователь PocketBase, либо запись-маркер владельца. Сотрудник с
///   любым набором прав сюда не попадает вовсе — это не модуль приложения, а
///   доступ к машине.
/// * Жёсткий срок. Команда запускается через `timeout`, поэтому забытый
///   `tail -f` или зависший запрос не держит обработчик вечно.
/// * Ограниченный вывод. Ответ обрезается: `cat` большого файла не должен
///   ни выесть память, ни утопить телефон.
/// * Журнал. Каждая команда — своя запись: кто, когда, что, с каким кодом
///   возврата. Консоль без следов была бы хуже, чем её отсутствие.
///
/// Кода возврата у `output()` нет, а при ненулевом коде он ещё и бросает
/// исключение. Поэтому команда оборачивается в оболочку, которая сама
/// печатает код в конце, — тогда `sh` завершается успешно всегда, а
/// настоящий код читается из вывода.

const SYSADMIN_MAX_OUTPUT = 64 * 1024;
const SYSADMIN_DEFAULT_TIMEOUT = 30;
const SYSADMIN_MAX_TIMEOUT = 300;
const SYSADMIN_EXIT_MARK = "__WESI_EXIT__";

routerAdd(
  "GET",
  "/api/wesi/sysadmin/version",
  (e) => {
    // Проба возможностей: приложение спрашивает до первой команды, чтобы не
    // предлагать человеку то, чего сервер не умеет.
    let shell = false;
    let detail = "";
    try {
      const probe = $os.exec("/bin/sh", "-c", "printf ok");
      shell = String(toString(probe.output())).indexOf("ok") >= 0;
    } catch (err) {
      detail = String(err);
    }
    return e.json(200, {
      "version": 1,
      "shell": shell,
      "maxOutputBytes": SYSADMIN_MAX_OUTPUT,
      "defaultTimeoutSeconds": SYSADMIN_DEFAULT_TIMEOUT,
      "maxTimeoutSeconds": SYSADMIN_MAX_TIMEOUT,
      "detail": detail,
    });
  },
  $apis.requireAuth("users"),
);

routerAdd(
  "POST",
  "/api/wesi/sysadmin/exec",
  (e) => {
    const ownerMarker = (ownerId) => {
      try {
        return e.app.findFirstRecordByFilter("wesios_records", "owner={:p_owner} && coll='system' && rid='portal-owner' && deleted=false", {"p_owner": ownerId});
      } catch (_) {
        return null;
      }
    };

    if (!e.hasSuperuserAuth() && (!e.auth || !ownerMarker(e.auth.id))) {
      throw new ForbiddenError(
        "Выполнять команды на сервере может только владелец",
      );
    }

    const body = e.requestInfo().body || {};
    const command = String(body.command || "").trim();
    if (!command) {
      throw new BadRequestError("Пустая команда");
    }
    if (command.length > 4000) {
      throw new BadRequestError("Команда длиннее 4000 символов");
    }

    const cwd = String(body.cwd || "").trim() || "/opt/pocketbase";
    let timeoutSeconds = parseInt(body.timeoutSeconds, 10);
    if (!isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
      timeoutSeconds = SYSADMIN_DEFAULT_TIMEOUT;
    }
    if (timeoutSeconds > SYSADMIN_MAX_TIMEOUT) {
      timeoutSeconds = SYSADMIN_MAX_TIMEOUT;
    }

    // Команда и каталог передаются оболочке аргументами, а не склейкой строк.
    // Так кавычки, пробелы и апострофы внутри команды остаются данными и не
    // могут случайно стать частью самой обёртки.
    const wrapper =
      'cd "$2" 2>/dev/null || true; ' +
      "timeout " + timeoutSeconds + 's /bin/sh -c "$1" 2>&1; ' +
      "printf '\\n" + SYSADMIN_EXIT_MARK + "%d' \"$?\"";

    const startedAt = new Date();
    let raw = "";
    let failure = "";
    try {
      const cmd = $os.exec("/bin/sh", "-c", wrapper, "wesios", command, cwd);
      raw = String(toString(cmd.output()));
    } catch (err) {
      failure = String(err);
    }

    let exitCode = -1;
    let output = raw;
    const mark = raw.lastIndexOf(SYSADMIN_EXIT_MARK);
    if (mark >= 0) {
      const parsed = parseInt(raw.substring(mark + SYSADMIN_EXIT_MARK.length), 10);
      if (isFinite(parsed)) exitCode = parsed;
      output = raw.substring(0, mark);
      if (output.charAt(output.length - 1) === "\n") {
        output = output.substring(0, output.length - 1);
      }
    }

    // 124 — так `timeout` сообщает, что оборвал команду по сроку. Без этой
    // подсказки человек видит пустой вывод и не понимает, что произошло.
    const timedOut = exitCode === 124;

    let truncated = false;
    if (output.length > SYSADMIN_MAX_OUTPUT) {
      output = output.substring(0, SYSADMIN_MAX_OUTPUT);
      truncated = true;
    }

    const finishedAt = new Date();
    const durationMs = finishedAt.getTime() - startedAt.getTime();

    try {
      const collection = e.app.findCollectionByNameOrId("wesios_records");
      const entry = new Record(collection);
      entry.set("owner", "__wesios_security__");
      entry.set("org", "wesi-inc");
      entry.set("coll", "sysadmin");
      entry.set(
        "rid",
        "exec:" + startedAt.getTime() + ":" +
          $security.randomStringWithAlphabet(8, "abcdefghijklmnopqrstuvwxyz0123456789"),
      );
      entry.set("payload", {
        "kind": "exec",
        "command": command,
        "cwd": cwd,
        "exitCode": exitCode,
        "timedOut": timedOut,
        "truncated": truncated,
        "durationMs": durationMs,
        "at": startedAt.toISOString(),
        "by": e.auth ? e.auth.id : "superuser",
        // Сам вывод в журнал не пишется намеренно: в нём бывают ключи,
        // содержимое конфигов и переписка. Журнал отвечает на вопрос
        // «что запускали», а не хранит копию всего, что выводилось.
        "outputBytes": output.length,
        "failure": failure,
      });
      e.app.save(entry);
    } catch (_) {
      // Журнал не должен обрывать саму команду: она уже выполнена, и
      // человеку важнее увидеть результат.
    }

    if (failure && !raw) {
      return e.json(200, {
        "ok": false,
        "command": command,
        "cwd": cwd,
        "exitCode": -1,
        "output": "",
        "timedOut": false,
        "truncated": false,
        "durationMs": durationMs,
        "error": "Сервер не смог запустить оболочку: " + failure,
      });
    }

    return e.json(200, {
      "ok": exitCode === 0,
      "command": command,
      "cwd": cwd,
      "exitCode": exitCode,
      "output": output,
      "timedOut": timedOut,
      "truncated": truncated,
      "durationMs": durationMs,
      "error": "",
    });
  },
  $apis.requireAuth("users"),
);
