import 'package:hive/hive.dart';

/// Откуда приложение берёт обновления.
///
/// **Почему свой сервер стал основным, а GitHub — запасным.**
///
/// До этого обновление шло только через GitHub Releases, и это требовало
/// входа в GitHub у каждого, кто хочет обновиться: закрытый репозиторий
/// отдаёт ассеты только по пропуску. Для владельца это одна кнопка, для
/// пятерых сотрудников — пять учётных записей на сервисе, к которому они не
/// имеют отношения, и объяснение, зачем бухгалтеру GitHub.
///
/// Со своего сервера сборка забирается без всякого входа: адрес известен,
/// файл лежит, приложение скачивает. GitHub при этом никуда не девается и
/// остаётся вторым путём — если сервер лёг или до него не дотянуться из
/// сети сотрудника, обновление всё равно приедет.
///
/// **Почему адрес можно переопределить.** Сервер может переехать, а сборка
/// с зашитым старым адресом останется у людей на руках — и обновиться, чтобы
/// узнать новый адрес, она уже не сможет. Замкнутый круг разрывается
/// настройкой.
class UpdateEndpoint {
  static const String _box = 'wesios_settings';
  static const String _key = 'update_server_base';

  /// Адрес по умолчанию. Не секрет: домен и так виден в DNS и в журналах
  /// выданных сертификатов. Секретом здесь были бы данные, а их по этим
  /// ссылкам нет — только то, что и так стоит у каждого на телефоне.
  static const String defaultBase = 'https://api.wesi-inc.ru/artifacts';

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  /// Заданный руками адрес. null — используется [defaultBase].
  static String? get override {
    final raw = _open()?.get(_key);
    if (raw is! String) return null;
    final s = raw.trim();
    return s.isEmpty ? null : s;
  }

  static Future<void> setOverride(String? value) async {
    final box = _open();
    if (box == null) return;
    final s = value?.trim() ?? '';
    if (s.isEmpty) {
      await box.delete(_key);
    } else {
      await box.put(_key, s);
    }
  }

  /// Основание всех ссылок, без хвостовой косой черты.
  static String get base {
    var b = override ?? defaultBase;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  static String get manifestUrl => '$base/app/app-manifest.json';

  /// Ссылка на файл по относительному пути из манифеста.
  ///
  /// Путь в манифесте относительный намеренно: один и тот же манифест
  /// годится и для боевого домена, и для проверки с другого адреса, и для
  /// отладки на своей машине. Домен подставляется здесь.
  static String fileUrl(String path) {
    var p = path;
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return '$base/$p';
  }
}
