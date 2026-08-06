enum ConsoleTemplateCategory {
  wesi,
  network,
  certificates,
  ssh,
  tokens,
}

class ConsoleTemplate {
  final String id;
  final ConsoleTemplateCategory category;
  final String titleRu;
  final String titleEn;
  final String descriptionRu;
  final String descriptionEn;
  final String command;
  final bool runImmediately;
  final bool pinned;
  final bool sensitive;

  const ConsoleTemplate({
    required this.id,
    required this.category,
    required this.titleRu,
    required this.titleEn,
    required this.descriptionRu,
    required this.descriptionEn,
    required this.command,
    this.runImmediately = false,
    this.pinned = false,
    this.sensitive = false,
  });

  String title(bool russian) => russian ? titleRu : titleEn;
  String description(bool russian) => russian ? descriptionRu : descriptionEn;

  bool get hasPlaceholder => command.contains('<') && command.contains('>');
  bool get canRunImmediately => runImmediately && !hasPlaceholder && !sensitive;
}

class ConsoleTemplateLibrary {
  static const List<ConsoleTemplate> all = [
    ConsoleTemplate(
      id: 'wesi-status',
      category: ConsoleTemplateCategory.wesi,
      titleRu: 'Состояние WesiOS',
      titleEn: 'WesiOS status',
      descriptionRu: 'Проверить все серверы, API и портал сотрудников.',
      descriptionEn: 'Probe every server, API endpoint, and employee portal.',
      command: 'status',
      runImmediately: true,
      pinned: true,
    ),
    ConsoleTemplate(
      id: 'wesi-api-health',
      category: ConsoleTemplateCategory.wesi,
      titleRu: 'PocketBase API',
      titleEn: 'PocketBase API',
      descriptionRu: 'Проверить основной health endpoint WesiOS.',
      descriptionEn: 'Check the primary WesiOS health endpoint.',
      command: 'http https://api.wesi-inc.ru/api/health',
      runImmediately: true,
      pinned: true,
    ),
    ConsoleTemplate(
      id: 'wesi-portal',
      category: ConsoleTemplateCategory.wesi,
      titleRu: 'Портал сотрудников',
      titleEn: 'Employee portal',
      descriptionRu: 'Проверить полный HTTP-ответ портала сотрудников.',
      descriptionEn: 'Check the complete employee portal HTTP response.',
      command: 'http https://api.wesi-inc.ru/portal/',
      runImmediately: true,
    ),
    ConsoleTemplate(
      id: 'wesi-load',
      category: ConsoleTemplateCategory.wesi,
      titleRu: 'Нагрузка сервера',
      titleEn: 'Server load',
      descriptionRu: 'Показать CPU, память и диск по данным серверного агента.',
      descriptionEn: 'Show CPU, memory, and disk data reported by the server agent.',
      command: 'load wesi-russia-server',
      runImmediately: true,
      pinned: true,
    ),
    ConsoleTemplate(
      id: 'network-dns-wesi',
      category: ConsoleTemplateCategory.network,
      titleRu: 'DNS WesiOS',
      titleEn: 'WesiOS DNS',
      descriptionRu: 'Разрешить api.wesi-inc.ru в IP-адреса и измерить время.',
      descriptionEn: 'Resolve api.wesi-inc.ru to IP addresses and measure time.',
      command: 'dns api.wesi-inc.ru',
      runImmediately: true,
    ),
    ConsoleTemplate(
      id: 'network-ping-wesi',
      category: ConsoleTemplateCategory.network,
      titleRu: 'Отклик HTTPS',
      titleEn: 'HTTPS latency',
      descriptionRu: 'Измерить TCP-отклик основного сервера на порту 443.',
      descriptionEn: 'Measure TCP latency to the primary server on port 443.',
      command: 'ping api.wesi-inc.ru 443',
      runImmediately: true,
      pinned: true,
    ),
    ConsoleTemplate(
      id: 'network-custom',
      category: ConsoleTemplateCategory.network,
      titleRu: 'Проверить адрес',
      titleEn: 'Check address',
      descriptionRu: 'Подставить любой домен и порт для TCP-проверки.',
      descriptionEn: 'Insert any domain and port for a TCP probe.',
      command: 'ping <host> <port>',
    ),
    ConsoleTemplate(
      id: 'http-custom',
      category: ConsoleTemplateCategory.network,
      titleRu: 'Проверить URL',
      titleEn: 'Check URL',
      descriptionRu: 'Выполнить безопасный GET и показать HTTP-код и задержку.',
      descriptionEn: 'Run a safe GET and display status code and latency.',
      command: 'http <https://example.com/health>',
    ),
    ConsoleTemplate(
      id: 'cert-wesi',
      category: ConsoleTemplateCategory.certificates,
      titleRu: 'Сертификат WesiOS',
      titleEn: 'WesiOS certificate',
      descriptionRu: 'Показать субъект, издателя и оставшийся срок TLS.',
      descriptionEn: 'Show TLS subject, issuer, and remaining validity.',
      command: 'tls api.wesi-inc.ru 443',
      runImmediately: true,
      pinned: true,
    ),
    ConsoleTemplate(
      id: 'cert-ai',
      category: ConsoleTemplateCategory.certificates,
      titleRu: 'Сертификат Wesi AI',
      titleEn: 'Wesi AI certificate',
      descriptionRu: 'Проверить TLS-сертификат зарубежного AI-шлюза.',
      descriptionEn: 'Check the TLS certificate of the foreign AI gateway.',
      command: 'tls ai.wesi-inc.ru 443',
      runImmediately: true,
    ),
    ConsoleTemplate(
      id: 'cert-custom',
      category: ConsoleTemplateCategory.certificates,
      titleRu: 'Любой сертификат',
      titleEn: 'Any certificate',
      descriptionRu: 'Подставить домен и порт для чтения сертификата.',
      descriptionEn: 'Insert a domain and port to read its certificate.',
      command: 'tls <host> 443',
    ),
    ConsoleTemplate(
      id: 'ssh-wesi',
      category: ConsoleTemplateCategory.ssh,
      titleRu: 'SSH-порт WesiOS',
      titleEn: 'WesiOS SSH port',
      descriptionRu: 'Без авторизации проверить, доступен ли SSH-порт сервера.',
      descriptionEn: 'Check whether the server SSH port is reachable without authenticating.',
      command: 'ssh-check api.wesi-inc.ru 22',
      runImmediately: true,
    ),
    ConsoleTemplate(
      id: 'ssh-custom',
      category: ConsoleTemplateCategory.ssh,
      titleRu: 'Проверить SSH',
      titleEn: 'Check SSH',
      descriptionRu: 'Подставить хост и порт. Ключи и пароль не сохраняются.',
      descriptionEn: 'Insert host and port. Keys and passwords are never stored.',
      command: 'ssh-check <host> 22',
    ),
    ConsoleTemplate(
      id: 'ssh-help',
      category: ConsoleTemplateCategory.ssh,
      titleRu: 'Безопасность SSH',
      titleEn: 'SSH security',
      descriptionRu: 'Показать правила безопасной работы с SSH в WesiOS.',
      descriptionEn: 'Show WesiOS rules for safe SSH administration.',
      command: 'ssh-help',
      runImmediately: true,
    ),
    ConsoleTemplate(
      id: 'token-inspect',
      category: ConsoleTemplateCategory.tokens,
      titleRu: 'Проверить JWT',
      titleEn: 'Inspect JWT',
      descriptionRu: 'Локально прочитать заголовок и срок токена, не отправляя его в сеть.',
      descriptionEn: 'Read token header and expiry locally without sending it over the network.',
      command: 'token inspect <TOKEN>',
      sensitive: true,
    ),
    ConsoleTemplate(
      id: 'token-hash',
      category: ConsoleTemplateCategory.tokens,
      titleRu: 'Отпечаток токена',
      titleEn: 'Token fingerprint',
      descriptionRu: 'Локально вычислить SHA-256 для безопасного сравнения токенов.',
      descriptionEn: 'Compute SHA-256 locally for safe token comparison.',
      command: 'token hash <TOKEN>',
      sensitive: true,
    ),
    ConsoleTemplate(
      id: 'token-redact',
      category: ConsoleTemplateCategory.tokens,
      titleRu: 'Скрыть токен',
      titleEn: 'Redact token',
      descriptionRu: 'Показать маскированный вид без раскрытия полного секрета.',
      descriptionEn: 'Display a masked representation without exposing the full secret.',
      command: 'token redact <TOKEN>',
      sensitive: true,
    ),
  ];

  static List<ConsoleTemplate> get pinned =>
      all.where((template) => template.pinned).toList(growable: false);

  static List<ConsoleTemplate> inCategory(ConsoleTemplateCategory category) =>
      all.where((template) => template.category == category).toList(growable: false);

  static String categoryTitle(ConsoleTemplateCategory category, bool russian) {
    return switch (category) {
      ConsoleTemplateCategory.wesi => russian ? 'WesiOS' : 'WesiOS',
      ConsoleTemplateCategory.network => russian ? 'Сеть и HTTP' : 'Network and HTTP',
      ConsoleTemplateCategory.certificates => russian ? 'Сертификаты' : 'Certificates',
      ConsoleTemplateCategory.ssh => russian ? 'SSH' : 'SSH',
      ConsoleTemplateCategory.tokens => russian ? 'Токены' : 'Tokens',
    };
  }
}
