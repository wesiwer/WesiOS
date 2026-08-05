import 'dart:convert';

import '../../../core/constants/app_version.dart';
import '../models/article_model.dart';

/// Встроенная справка WesiOS.
///
/// **Для кого она.** Для человека, который открыл программу впервые, и для
/// него же через полгода, когда вопрос будет уже не «куда нажать», а «как
/// вообще принято поступать». Поэтому здесь два пласта: как устроена
/// система и как устроены вещи, ради которых её открывают, — деньги, работа,
/// собственная голова.
///
/// **Чего здесь нет и не будет.** Устройства программы изнутри: названий
/// классов, полей моделей, формул из кода. Прежняя справка состояла из них
/// почти целиком — таблицы полей, идентификаторы хранилища, формула Z-оценки.
/// Человеку, который ищет «куда записать зарплату», это не отвечало ни на
/// один вопрос, зато выглядело так, будто отвечает.
///
/// **Как это устроено технически.** Тело статьи — документ Quill в формате
/// Delta. Раньше он собирался склейкой строк, и вокруг этой склейки успело
/// накопиться три разных способа сломать разметку: незакрытая кавычка,
/// атрибут блока не на том операторе, вложенный JSON без экранирования.
/// Теперь документ собирается объектами ([_Doc]) и кодируется `jsonEncode`
/// один раз в конце — ни один из тех способов больше не существует.
class BuiltinArticles {
  const BuiltinArticles._();

  static List<ArticleModel> all(bool ru) {
    final c = _Ctx(ru, DateTime.now());
    return [
      ..._start(c),
      ..._modules(c),
      ..._money(c),
      ..._work(c),
      ..._life(c),
    ];
  }

  // ═══════════════════════════════════════════════════════ Начало

  static List<ArticleModel> _start(_Ctx c) {
    final root = c.folder(
      'kb_start',
      c.t('Начало', 'Start here'),
      order: 0,
      pinned: true,
      section: ArticleSection.about,
    );

    final what = c.article(
      'kb_start_what',
      c.t('Что такое WesiOS', 'What WesiOS is'),
      parentId: 'kb_start',
      order: 0,
      section: ArticleSection.about,
      tags: c.tags(['о программе', 'начало'], ['about', 'start']),
      doc: _Doc()
        ..h1(c.t('Что такое WesiOS', 'What WesiOS is'))
        ..p(c.t(
          'WesiOS — рабочее место для одного человека или небольшой команды. '
              'В одном окне живут деньги, задачи, календарь, переписка и эта '
              'справка. Смысл не в том, чтобы заменить пять приложений, а в '
              'том, чтобы цифры в них перестали расходиться.',
          'WesiOS is a workplace for one person or a small team. Money, '
              'tasks, calendar, chats and this handbook live in one window. '
              'The point is not to replace five apps but to stop their '
              'numbers from disagreeing.',
        ))
        ..h2(c.t('Чем это не является', 'What it is not'))
        ..bullets([
          c.t(
            'Не банк. Программа не двигает ваши деньги — она записывает то, '
                'что уже произошло.',
            'Not a bank. It does not move your money — it records what has '
                'already happened.',
          ),
          c.t(
            'Не бухгалтерия. Отчётность в налоговую отсюда не сдают.',
            'Not accounting software. You do not file taxes from here.',
          ),
          c.t(
            'Не советник. Прогноз показывает продолжение ваших же привычек, '
                'а не то, что случится наверняка.',
            'Not an adviser. The forecast continues your own habits; it does '
                'not know the future.',
          ),
        ])
        ..h2(c.t('На чём всё держится', 'What it stands on'))
        ..bullets([
          c.t(
            'Данные лежат на вашем устройстве. Не «в облаке, но безопасно» — '
                'на устройстве.',
            'Data lives on your device. Not "in the cloud but safely" — on '
                'the device.',
          ),
          c.t(
            'Сервер нужен только чтобы связать телефон и компьютер. Без него '
                'работает всё, кроме этой связи.',
            'The server only links your phone and computer. Without it '
                'everything works except that link.',
          ),
          c.t(
            'Программа не притворяется. Если что-то не отправилось — так и '
                'написано, а не «галочка доставлено».',
            'The app does not pretend. If something was not sent, it says '
                'so instead of showing a checkmark.',
          ),
        ])
        ..h2(c.t('Версия', 'Version'))
        ..p(c.t(
          'Сейчас установлена ${AppVersion.display}. Буква α означает: '
              'программа живая, и что-то ещё будет меняться.',
          'You are running ${AppVersion.display}. The α means the app is '
              'still moving and some things will change.',
        ))
        ..h2(c.t('Куда дальше', 'Where next'))
        ..p(c.t(
          'Следующая статья — «Первые 20 минут». Она короткая и её стоит '
              'пройти руками, а не глазами.',
          'Next up is "The first 20 minutes". It is short, and it is worth '
              'doing rather than reading.',
        )),
    );

    final first = c.article(
      'kb_start_first',
      c.t('Первые 20 минут', 'The first 20 minutes'),
      parentId: 'kb_start',
      order: 1,
      section: ArticleSection.guide,
      tags: c.tags(['начало', 'настройка'], ['start', 'setup']),
      doc: _Doc()
        ..h1(c.t('Первые 20 минут', 'The first 20 minutes'))
        ..p(c.t(
          'Цель — чтобы к концу этих двадцати минут программа показывала '
              'ваши настоящие цифры, а не пустой экран. Пустой экран '
              'закрывают и не возвращаются.',
          'The goal is that by the end the app shows your real numbers '
              'instead of an empty screen. Empty screens get closed and not '
              'reopened.',
        ))
        ..h2(c.t('По шагам', 'Step by step'))
        ..steps([
          c.t(
            'Заведите счета: карта, наличные, накопительный. У каждого '
                'поставьте остаток, который там сейчас.',
            'Add your accounts: card, cash, savings. Give each the balance '
                'it actually has right now.',
          ),
          c.t(
            'Внесите последние 5–10 трат. Не за месяц — за последние дни, '
                'по памяти.',
            'Enter your last 5–10 expenses. Not a whole month — just the '
                'recent days, from memory.',
          ),
          c.t(
            'Внесите доход: зарплату, перевод, выручку. Хотя бы один.',
            'Enter one income: salary, transfer, revenue. At least one.',
          ),
          c.t(
            'Отметьте регулярные платежи — аренду, подписки, кредит. Их '
                'достаточно завести один раз.',
            'Mark the recurring payments — rent, subscriptions, loan. You '
                'enter them once.',
          ),
          c.t(
            'Зайдите в Аналитику. Если там появилась осмысленная картина — '
                'вы всё сделали правильно.',
            'Open Analytics. If it shows a picture that makes sense, you '
                'did it right.',
          ),
        ])
        ..h2(c.t('Чего делать не надо', 'What not to do'))
        ..bullets([
          c.t(
            'Не восстанавливайте историю за год. Она не нужна ни прогнозу, '
                'ни вам, а бросают почти всегда именно на этом.',
            'Do not reconstruct a year of history. Neither the forecast nor '
                'you need it, and this is where people give up.',
          ),
          c.t(
            'Не придумывайте идеальные категории. Хватит десятка, остальные '
                'появятся сами.',
            'Do not design perfect categories. Ten is plenty; the rest will '
                'appear on their own.',
          ),
          c.t(
            'Не настраивайте сервер сразу. Сначала пусть программа станет '
                'нужной на одном устройстве.',
            'Do not set up the server yet. First let the app become useful '
                'on one device.',
          ),
        ])
        ..h2(c.t('Открыть сейчас', 'Open now'))
        ..route(c.t('Открыть Казну', 'Open Treasury'), 'treasury'),
    );

    final map = c.article(
      'kb_start_map',
      c.t('Что где лежит', 'Where things are'),
      parentId: 'kb_start',
      order: 2,
      section: ArticleSection.about,
      tags: c.tags(['навигация', 'начало'], ['navigation', 'start']),
      doc: _Doc()
        ..h1(c.t('Что где лежит', 'Where things are'))
        ..p(c.t(
          'Разделов немного, и у каждого одна работа. Если непонятно, куда '
              'идти, — вопрос почти всегда решается тем, чтобы назвать вслух, '
              'что вы ищете.',
          'There are few sections and each has one job. When you are unsure '
              'where to go, saying out loud what you are looking for usually '
              'settles it.',
        ))
        ..table([
          [c.t('Раздел', 'Section'), c.t('Отвечает на вопрос', 'Answers')],
          [
            c.t('Главная', 'Home'),
            c.t('Как дела прямо сейчас', 'How things stand right now'),
          ],
          [
            c.t('Казна', 'Treasury'),
            c.t('Сколько есть и куда ушло', 'How much there is and where it went'),
          ],
          [
            c.t('Прогноз', 'Forecast'),
            c.t('Хватит ли до конца месяца', 'Will it last until month end'),
          ],
          [
            c.t('Аналитика', 'Analytics'),
            c.t('На чём именно уходит', 'What exactly the money goes on'),
          ],
          [
            c.t('Задачи', 'Tasks'),
            c.t('Что я должен сделать', 'What I owe someone'),
          ],
          [
            c.t('Календарь', 'Calendar'),
            c.t('Что и когда произойдёт', 'What happens when'),
          ],
          [
            c.t('Чаты', 'Chats'),
            c.t('О чём мы договорились', 'What we agreed on'),
          ],
          [
            c.t('Контакты', 'Contacts'),
            c.t('Кто в команде и что ему видно', 'Who is on the team and what they see'),
          ],
          [
            c.t('База знаний', 'Handbook'),
            c.t('Как это делается', 'How things are done'),
          ],
        ])
        ..p('')
        ..h2(c.t('Две вещи, которые ищут дольше всего', 'Two things people hunt for'))
        ..bullets([
          c.t(
            'Поиск по всему сразу — лупа в шапке главной. Он ищет и по '
                'операциям, и по задачам, и по статьям.',
            'Search across everything — the magnifier on Home. It covers '
                'operations, tasks and articles at once.',
          ),
          c.t(
            'Настройки, синхронизация и выход — в профиле, значок справа '
                'вверху.',
            'Settings, sync and sign-out live in the profile, top right.',
          ),
        ]),
    );

    final data = c.article(
      'kb_start_data',
      c.t('Где живут ваши данные', 'Where your data lives'),
      parentId: 'kb_start',
      order: 3,
      section: ArticleSection.about,
      tags: c.tags(['данные', 'приватность'], ['data', 'privacy']),
      doc: _Doc()
        ..h1(c.t('Где живут ваши данные', 'Where your data lives'))
        ..p(c.t(
          'Короткий ответ: на этом устройстве. Длинный — ниже, и его стоит '
              'прочитать один раз, чтобы потом не гадать.',
          'Short answer: on this device. The long one is below, and it is '
              'worth reading once so you never have to guess.',
        ))
        ..h2(c.t('Что остаётся здесь всегда', 'What never leaves'))
        ..bullets([
          c.t('Пароль Wesi Shield и всё, что он закрывает.',
              'The Wesi Shield password and everything it locks.'),
          c.t('Личная переписка — она не уходит с устройства даже при '
              'включённой синхронизации.',
              'Personal chats — they stay on the device even with sync on.'),
          c.t('Настройки и оформление: они привязаны к конкретному аппарату.',
              'Settings and appearance: they belong to this particular device.'),
        ])
        ..h2(c.t('Что уезжает, если вы вошли на сервер',
            'What travels once you sign in'))
        ..bullets([
          c.t('Счета и операции.', 'Accounts and operations.'),
          c.t('Задачи.', 'Tasks.'),
          c.t('Ваши статьи в базе знаний.', 'Your own handbook articles.'),
          c.t('Состав команды и рабочая переписка.',
              'Team members and work chats.'),
        ])
        ..h2(c.t('Как это проверить', 'How to check'))
        ..p(c.t(
          'Профиль → Синхронизация. Пока там написано, что вход не выполнен, '
              'с устройства не уходит ничего вообще. Это не настройка '
              'приватности, а простой факт: отправлять некуда.',
          'Profile → Sync. While it says you are not signed in, nothing '
              'leaves the device at all. That is not a privacy setting, just '
              'a fact: there is nowhere to send it.',
        ))
        ..h2(c.t('Что будет, если телефон потеряется',
            'What if the phone is lost'))
        ..p(c.t(
          'Всё, что успело уехать на сервер, вернётся на новом устройстве '
              'после входа. Всё, что не уехало, потеряется вместе с '
              'телефоном. Это и есть настоящая причина включить '
              'синхронизацию — не удобство, а второй экземпляр.',
          'Whatever reached the server comes back on a new device after you '
              'sign in. Whatever did not is gone with the phone. That is the '
              'real reason to turn sync on: not convenience, a second copy.',
        )),
    );

    final keep = c.article(
      'kb_start_keep',
      c.t('Как не забросить через неделю', 'How not to quit in a week'),
      parentId: 'kb_start',
      order: 4,
      section: ArticleSection.personal,
      tags: c.tags(['привычка', 'начало'], ['habit', 'start']),
      doc: _Doc()
        ..h1(c.t('Как не забросить через неделю', 'How not to quit in a week'))
        ..p(c.t(
          'Учёт бросают не потому, что он сложный. Его бросают потому, что '
              'он ничего не даёт первые дни, а требует каждый день. Это '
              'лечится, и способ известный.',
          'People abandon tracking not because it is hard. They abandon it '
              'because it gives nothing for the first few days while asking '
              'for something every day. There is a known fix.',
        ))
        ..h2(c.t('Три правила', 'Three rules'))
        ..steps([
          c.t(
            'Записывайте сразу, а не вечером. Вечером вы вспомните половину '
                'и решите, что учёт врёт.',
            'Record immediately, not in the evening. By evening you recall '
                'half of it and conclude the tracking lies.',
          ),
          c.t(
            'Пропустили день — не начинайте заново. Пропуск не обнуляет '
                'месяц, а попытка «начать с чистого листа» обнуляет.',
            'Missed a day? Do not start over. A gap does not void the month; '
                'starting over does.',
          ),
          c.t(
            'Смотрите Аналитику раз в неделю, а не каждый день. Ежедневный '
                'просмотр показывает шум и злит.',
            'Check Analytics weekly, not daily. Daily you only see noise, '
                'and it is annoying.',
          ),
        ])
        ..h2(c.t('Признак, что получилось', 'The sign it worked'))
        ..p(c.t(
          'Через месяц вы перестанете задавать себе вопрос «а сколько у меня '
              'вообще есть». Не потому, что стало больше, — потому что вы '
              'знаете ответ, не открывая приложение.',
          'After a month you stop asking yourself "how much do I even have". '
              'Not because there is more, but because you know the answer '
              'without opening the app.',
        )),
    );

    return [root, what, first, map, data, keep];
  }

  // ═══════════════════════════════════════════════════════ Модули

  static List<ArticleModel> _modules(_Ctx c) {
    final root = c.folder(
      'kb_modules',
      c.t('Как пользоваться', 'Using WesiOS'),
      order: 1,
      section: ArticleSection.guide,
    );

    final out = <ArticleModel>[root];

    // ── Казна ────────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_money', c.t('Казна', 'Treasury'),
        parentId: 'kb_modules', order: 0, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_money_first',
      c.t('Первая операция', 'Your first operation'),
      parentId: 'kb_m_money',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['казна', 'операции'], ['treasury', 'operations']),
      doc: _Doc()
        ..h1(c.t('Первая операция', 'Your first operation'))
        ..p(c.t(
          'Операция — это одна запись о том, что деньги пришли, ушли или '
              'переехали между вашими счетами. Больше в ней ничего нет.',
          'An operation is one record that money came in, went out, or moved '
              'between your own accounts. That is all it is.',
        ))
        ..h2(c.t('Как добавить', 'How to add one'))
        ..steps([
          c.t('Откройте Казну и нажмите «плюс».',
              'Open Treasury and tap the plus.'),
          c.t('Выберите тип: приход, расход или перевод.',
              'Pick the type: income, expense or transfer.'),
          c.t('Укажите сумму и счёт, с которого это произошло.',
              'Enter the amount and the account it happened on.'),
          c.t('Выберите категорию — по ней потом строится Аналитика.',
              'Choose a category — Analytics is built from these.'),
          c.t('Дату меняйте, только если вносите задним числом.',
              'Change the date only if you are entering something from the past.'),
        ])
        ..h2(c.t('Про категории', 'About categories'))
        ..p(c.t(
          'Категория отвечает на вопрос «на что», а не «где». «Продукты» — '
              'категория, «Пятёрочка» — нет: магазин может продать и хлеб, и '
              'зарядку, и это разные строки в вашей жизни.',
          'A category answers "what for", not "where". "Groceries" is a '
              'category, "the corner shop" is not: the same shop sells bread '
              'and phone chargers, and those are different lines in your life.',
        ))
        ..h2(c.t('Частая ошибка', 'The common mistake'))
        ..p(c.t(
          'Перевод между своими счетами — это не расход. Если снять наличные '
              'и записать это тратой, месяц покажет, что вы потратили вдвое '
              'больше, чем на самом деле.',
          'Moving money between your own accounts is not spending. If you '
              'withdraw cash and log it as an expense, the month will claim '
              'you spent twice what you did.',
        )),
    ));

    out.add(c.article(
      'kb_m_money_accounts',
      c.t('Счета и переводы', 'Accounts and transfers'),
      parentId: 'kb_m_money',
      order: 1,
      section: ArticleSection.guide,
      tags: c.tags(['счета', 'переводы'], ['accounts', 'transfers']),
      doc: _Doc()
        ..h1(c.t('Счета и переводы', 'Accounts and transfers'))
        ..p(c.t(
          'Счёт — это место, где лежат деньги: карта, наличные в кармане, '
              'накопительный, счёт бизнеса. Общий баланс складывается из них.',
          'An account is a place where money sits: a card, cash in your '
              'pocket, savings, a business account. The total balance is '
              'their sum.',
        ))
        ..h2(c.t('Сколько счетов заводить', 'How many accounts'))
        ..p(c.t(
          'Столько, сколько вы реально различаете. Если вам всё равно, с '
              'какой из двух карт платить, — заведите один счёт. Разделение '
              'ради порядка, а не ради количества.',
          'As many as you actually tell apart. If you do not care which of '
              'two cards you pay with, make it one account. Split for '
              'clarity, not for the count.',
        ))
        ..h2(c.t('Перевод', 'Transfers'))
        ..bullets([
          c.t('Общий баланс от перевода не меняется — меняется, где деньги.',
              'A transfer does not change the total — it changes where the '
                  'money is.'),
          c.t('Перевод не попадает в расходы и не портит Аналитику.',
              'Transfers stay out of expenses and do not distort Analytics.'),
          c.t('Снятие наличных — это перевод «карта → наличные».',
              'Withdrawing cash is a transfer: card → cash.'),
        ])
        ..h2(c.t('Если баланс разошёлся с реальностью',
            'If the balance disagrees with reality'))
        ..p(c.t(
          'Не пересчитывайте всё заново. Добавьте одну операцию на разницу с '
              'категорией «Корректировка» — и дальше живите. Точность прошлого '
              'месяца не стоит вечера вашей жизни.',
          'Do not redo everything. Add one operation for the difference with '
              'a "Correction" category and move on. Last month\'s precision '
              'is not worth an evening of your life.',
        )),
    ));

    out.add(c.article(
      'kb_m_money_repeat',
      c.t('Регулярные платежи', 'Recurring payments'),
      parentId: 'kb_m_money',
      order: 2,
      section: ArticleSection.guide,
      tags: c.tags(['подписки', 'платежи'], ['subscriptions', 'payments']),
      doc: _Doc()
        ..h1(c.t('Регулярные платежи', 'Recurring payments'))
        ..p(c.t(
          'Аренда, подписки, кредит, интернет — то, что списывается само. '
              'Их заводят один раз, и дальше программа знает, что они будут.',
          'Rent, subscriptions, a loan, internet — the things that charge '
              'themselves. You enter them once and the app knows they are '
              'coming.',
        ))
        ..h2(c.t('Зачем это отмечать', 'Why mark them'))
        ..bullets([
          c.t('Прогноз перестаёт быть наивным: он видит, что через неделю '
              'спишется аренда.',
              'The forecast stops being naive: it sees rent leaving next week.'),
          c.t('Колокольчик предупреждает заранее, а не постфактум.',
              'The bell warns you beforehand instead of afterwards.'),
          c.t('Видно сумму всех подписок за месяц — обычно она неприятно '
              'удивляет.',
              'You see what all subscriptions cost per month — usually an '
                  'unpleasant surprise.'),
        ])
        ..h2(c.t('Как завести', 'How to add one'))
        ..steps([
          c.t('Создайте обычную операцию с датой первого списания.',
              'Create a normal operation dated at the first charge.'),
          c.t('Включите «повторяется» и выберите период.',
              'Turn on "recurring" and pick the period.'),
          c.t('Проверьте на главной: платёж должен появиться в ближайших.',
              'Check Home: the payment should show up in what is coming.'),
        ])
        ..h2(c.t('Раз в год — тоже регулярно', 'Yearly counts too'))
        ..p(c.t(
          'Страховка, домен, годовая подписка. Именно они забываются, потому '
              'что случаются реже, чем вы вспоминаете о них.',
          'Insurance, a domain, an annual plan. These are exactly the ones '
              'you forget, because they happen less often than you think of '
              'them.',
        )),
    ));

    // ── Прогноз ──────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_forecast', c.t('Прогноз', 'Forecast'),
        parentId: 'kb_modules', order: 1, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_forecast_read',
      c.t('Как читать прогноз', 'How to read the forecast'),
      parentId: 'kb_m_forecast',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['прогноз'], ['forecast']),
      doc: _Doc()
        ..h1(c.t('Как читать прогноз', 'How to read the forecast'))
        ..p(c.t(
          'Прогноз отвечает на один вопрос: если дальше будет как сейчас, '
              'сколько останется через месяц. Не «сколько будет», а «если '
              'ничего не менять».',
          'The forecast answers one question: if things continue as they '
              'are, what is left in a month. Not "what will be" — "what if '
              'nothing changes".',
        ))
        ..h2(c.t('Три вещи на графике', 'Three things on the chart'))
        ..bullets([
          c.t('Линия — самый вероятный ход событий.',
              'The line — the most likely path.'),
          c.t('Полоса вокруг неё — насколько программа не уверена. Широкая '
              'полоса означает «данных мало», а не «всё плохо».',
              'The band around it — how unsure the app is. A wide band means '
                  '"not enough data", not "things are bad".'),
          c.t('Отметки на линии — известные будущие списания.',
              'The marks on the line — known future charges.'),
        ])
        ..h2(c.t('Когда ему верить', 'When to trust it'))
        ..p(c.t(
          'После двух-трёх месяцев записей. До этого он честно строит линию '
              'по тому немногому, что есть, и полоса неуверенности будет '
              'шире самого прогноза.',
          'After two or three months of records. Before that it honestly '
              'draws a line through the little it has, and the uncertainty '
              'band will be wider than the forecast itself.',
        ))
        ..h2(c.t('Чего он не знает', 'What it cannot know'))
        ..p(c.t(
          'Что вы собрались в отпуск, что у вас сломалась стиральная машина '
              'и что в марте будет премия. Всё это можно внести вручную '
              'будущей датой — тогда прогноз это учтёт.',
          'That you are going on holiday, that your washing machine died, or '
              'that a bonus lands in March. You can enter any of those with '
              'a future date and the forecast will take them in.',
        )),
    ));

    // ── Аналитика ────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_analytics', c.t('Аналитика', 'Analytics'),
        parentId: 'kb_modules', order: 2, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_analytics_read',
      c.t('Куда уходят деньги', 'Where the money goes'),
      parentId: 'kb_m_analytics',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['аналитика', 'расходы'], ['analytics', 'spending']),
      doc: _Doc()
        ..h1(c.t('Куда уходят деньги', 'Where the money goes'))
        ..p(c.t(
          'Аналитика показывает не «много или мало», а «на что». Это разные '
              'вопросы, и полезен второй: сумму вы и так примерно знаете, а '
              'состав — почти никогда.',
          'Analytics does not show "a lot or a little" — it shows "on what". '
              'Those are different questions, and the second one is useful: '
              'you roughly know the total, but almost never the breakdown.',
        ))
        ..h2(c.t('С чего начинать смотреть', 'Where to look first'))
        ..steps([
          c.t('Три самые крупные категории месяца. Обычно там 60–70% всего.',
              'The three biggest categories of the month. Usually 60–70% of '
                  'everything.'),
          c.t('Сравнение с прошлым месяцем — что выросло вдвое.',
              'The comparison with last month — what doubled.'),
          c.t('Мелкие частые траты. Они не видны поодиночке и заметны только '
              'в сумме.',
              'Small frequent purchases. Invisible one by one, obvious in '
                  'total.'),
        ])
        ..h2(c.t('Необычные операции', 'Unusual operations'))
        ..p(c.t(
          'Программа помечает траты, которые сильно выбиваются из ваших '
              'обычных по этой категории. Это не обвинение — это способ '
              'заметить ошибку ввода или списание, о котором вы забыли.',
          'The app marks purchases that stand far out from your usual ones '
              'in that category. It is not an accusation — it is a way to '
              'catch a typo or a charge you forgot about.',
        )),
    ));

    // ── Задачи ───────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_tasks', c.t('Задачи', 'Tasks'),
        parentId: 'kb_modules', order: 3, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_tasks_first',
      c.t('Задачи и сроки', 'Tasks and deadlines'),
      parentId: 'kb_m_tasks',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['задачи', 'сроки'], ['tasks', 'deadlines']),
      doc: _Doc()
        ..h1(c.t('Задачи и сроки', 'Tasks and deadlines'))
        ..p(c.t(
          'Задача здесь — то, что вы кому-то должны, включая себя. Список '
              'нужен не чтобы всё успеть, а чтобы не держать это в голове.',
          'A task here is something you owe someone, yourself included. The '
              'list is not for getting everything done — it is for not '
              'holding it in your head.',
        ))
        ..h2(c.t('Правила, которые делают список рабочим',
            'What makes a list work'))
        ..bullets([
          c.t('Формулируйте действием: не «отчёт», а «отправить отчёт Ане».',
              'Phrase it as an action: not "report" but "send the report to '
                  'Anna".'),
          c.t('Срок ставьте только настоящий. Выдуманные сроки обесценивают '
              'настоящие, и через месяц красное перестаёт что-либо значить.',
              'Set only real deadlines. Invented ones devalue the real ones, '
                  'and within a month red stops meaning anything.'),
          c.t('Большое разбивайте на подзадачи. «Сделать сайт» не делается, '
              '«написать текст на главную» — делается.',
              'Break big things into subtasks. "Build a website" never gets '
                  'done; "write the homepage copy" does.'),
        ])
        ..h2(c.t('Просроченное', 'Overdue'))
        ..p(c.t(
          'Раз в неделю просмотрите просроченное и честно решите по каждой: '
              'делаю сейчас, переношу с новым сроком или удаляю. Третий '
              'вариант — не поражение, а самый частый правильный ответ.',
          'Once a week go through the overdue list and decide honestly for '
              'each: do it now, move it with a new date, or delete it. The '
              'third option is not defeat — it is usually the right answer.',
        )),
    ));

    // ── Календарь ────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_calendar', c.t('Календарь', 'Calendar'),
        parentId: 'kb_modules', order: 4, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_calendar_first',
      c.t('День, неделя, месяц', 'Day, week, month'),
      parentId: 'kb_m_calendar',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['календарь'], ['calendar']),
      doc: _Doc()
        ..h1(c.t('День, неделя, месяц', 'Day, week, month'))
        ..p(c.t(
          'В календаре видно и события, и сроки задач, и будущие списания '
              'сразу. Это единственное место, где «занят» и «денег не будет» '
              'стоят рядом.',
          'The calendar shows events, task deadlines and upcoming charges in '
              'one place. It is the only view where "busy" and "no money '
              'left" sit side by side.',
        ))
        ..h2(c.t('Небольшой месяц на главной', 'The small month on Home'))
        ..p(c.t(
          'Рядом с часами стоит месяц целиком: сегодняшнее число подсвечено, '
              'по нажатию открывается полный календарь. Он там ровно для '
              'одного — ответить «какое сегодня» и «сколько до конца недели», '
              'не открывая ничего.',
          'Next to the clock there is a whole month with today highlighted; '
              'tapping it opens the full calendar. It exists for exactly one '
              'purpose: answering "what is the date" and "how long until the '
              'weekend" without opening anything.',
        ))
        ..h2(c.t('Открыть сейчас', 'Open now'))
        ..route(c.t('Открыть календарь', 'Open calendar'), 'calendar'),
    ));

    // ── Чаты ─────────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_chats', c.t('Чаты', 'Chats'),
        parentId: 'kb_modules', order: 5, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_chats_first',
      c.t('Переписка', 'Messaging'),
      parentId: 'kb_m_chats',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['чаты', 'переписка'], ['chats', 'messaging']),
      doc: _Doc()
        ..h1(c.t('Переписка', 'Messaging'))
        ..p(c.t(
          'Чаты внутри WesiOS нужны, чтобы договорённости лежали рядом с '
              'задачами и деньгами, а не в третьем приложении, где их потом '
              'не найти.',
          'Chats inside WesiOS exist so that agreements sit next to the '
              'tasks and the money, instead of in a third app where nobody '
              'finds them later.',
        ))
        ..h2(c.t('Что умеет', 'What it can do'))
        ..bullets([
          c.t('Личные и групповые разговоры.', 'One-to-one and group chats.'),
          c.t('Правка отправленного — с пометкой, что сообщение изменено.',
              'Editing a sent message — marked as edited.'),
          c.t('Файлы и картинки до 20 МБ.', 'Files and images up to 20 MB.'),
          c.t('Реакции и поиск внутри переписки.',
              'Reactions and search inside a conversation.'),
          c.t('Срок хранения на конкретный чат: старое стирается само.',
              'A retention period per chat: old messages clear themselves.'),
        ])
        ..h2(c.t('Значки под сообщением', 'The marks under a message'))
        ..table([
          [c.t('Значок', 'Mark'), c.t('Что означает', 'Meaning')],
          [
            c.t('Часики', 'Clock'),
            c.t('Ждёт отправки на сервер', 'Waiting to be sent'),
          ],
          [
            c.t('Галочка', 'Check'),
            c.t('Ушло на сервер', 'Reached the server'),
          ],
          [
            c.t('Ничего', 'Nothing'),
            c.t('Сообщению некуда ехать — вы не вошли на сервер или это '
                'личный чат', 'Nowhere to go — you are not signed in, or '
                'this is a personal chat'),
          ],
        ])
        ..p(''),
    ));

    out.add(c.article(
      'kb_m_chats_privacy',
      c.t('Что уезжает, а что остаётся', 'What travels and what stays'),
      parentId: 'kb_m_chats',
      order: 1,
      section: ArticleSection.about,
      tags: c.tags(['чаты', 'приватность'], ['chats', 'privacy']),
      doc: _Doc()
        ..h1(c.t('Что уезжает, а что остаётся', 'What travels and what stays'))
        ..p(c.t(
          'В чатах два вида разговоров, и разница между ними не в оформлении, '
              'а в том, покидает ли переписка устройство.',
          'There are two kinds of conversation here, and the difference is '
              'not cosmetic: it is whether the messages leave the device.',
        ))
        ..bullets([
          c.t('Рабочий чат уезжает на сервер и доступен на всех ваших '
              'устройствах.',
              'A work chat goes to the server and is available on all your '
                  'devices.'),
          c.t('Личный чат не уезжает никуда. На втором устройстве его не '
              'будет — это цена обещания «видят только собеседники».',
              'A personal chat goes nowhere. It will not appear on your '
                  'second device — that is the price of "only the two of you '
                  'see this".'),
        ])
        ..h2(c.t('Почему так, а не шифрование', 'Why this and not encryption'))
        ..p(c.t(
          'Настоящее сквозное шифрование ещё не сделано. Пока его нет, '
              'обещание держится единственным честным способом: личная '
              'переписка физически не покидает аппарат. Обратное — написать '
              '«защищено» и отправить на сервер как есть.',
          'Proper end-to-end encryption is not built yet. Until it is, the '
              'promise is kept the only honest way: personal messages simply '
              'never leave the device. The alternative would be writing '
              '"secure" and sending them anyway.',
        )),
    ));

    // ── Команда ──────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_team', c.t('Команда', 'Team'),
        parentId: 'kb_modules', order: 6, section: ArticleSection.playbook));

    out.add(c.article(
      'kb_m_team_add',
      c.t('Как завести сотрудника', 'Adding a person'),
      parentId: 'kb_m_team',
      order: 0,
      section: ArticleSection.playbook,
      tags: c.tags(['команда', 'сотрудники'], ['team', 'people']),
      doc: _Doc()
        ..h1(c.t('Как завести сотрудника', 'Adding a person'))
        ..steps([
          c.t('Контакты → «плюс». Заполните имя и должность.',
              'Contacts → plus. Fill in the name and role.'),
          c.t('Программа предложит свободный логин и пароль. Их можно '
              'заменить своими.',
              'The app suggests a free login and password. You may replace '
                  'them.'),
          c.t('Отметьте, что человеку видно. По умолчанию не видно почти '
              'ничего — это правильное начало.',
              'Set what the person can see. By default almost nothing — that '
                  'is the right starting point.'),
          c.t('Передайте логин и пароль лично. Не в общем чате.',
              'Hand the login and password over in person. Not in a group '
                  'chat.'),
        ])
        ..h2(c.t('Логин занять нельзя дважды', 'A login is taken only once'))
        ..p(c.t(
          'Программа держит список занятых логинов и не даст выдать один и '
              'тот же двоим. Освобождается он только когда вы смените логин '
              'или удалите человека.',
          'The app keeps a list of taken logins and will not hand the same '
              'one to two people. It frees up only when you change the login '
              'or remove the person.',
        )),
    ));

    out.add(c.article(
      'kb_m_team_rights',
      c.t('Права: кто что видит', 'Permissions: who sees what'),
      parentId: 'kb_m_team',
      order: 1,
      section: ArticleSection.playbook,
      tags: c.tags(['права', 'доступ'], ['permissions', 'access']),
      doc: _Doc()
        ..h1(c.t('Права: кто что видит', 'Permissions: who sees what'))
        ..p(c.t(
          'Права устроены как дерево: сначала модуль целиком, потом отдельные '
              'части внутри него. Базу знаний можно закрыть вплоть до '
              'конкретной статьи.',
          'Permissions form a tree: the whole module first, then individual '
              'parts inside. The handbook can be restricted down to a single '
              'article.',
        ))
        ..h2(c.t('Правило по умолчанию', 'The default rule'))
        ..p(c.t(
          'Выдавайте не то, что «пусть будет», а то, без чего человек не '
              'сможет работать. Расширить права занимает минуту, а вернуть '
              'увиденное назад нельзя.',
          'Grant what the person cannot work without, not what "might come '
              'in handy". Widening access takes a minute; un-seeing what was '
              'seen is impossible.',
        ))
        ..h2(c.t('Проверка', 'Checking'))
        ..p(c.t(
          'Настройка, которая ни на что не влияет, хуже её отсутствия. '
              'Поэтому после выдачи прав стоит войти под этим логином и '
              'посмотреть своими глазами, что видно.',
          'A setting that changes nothing is worse than no setting at all. '
              'After granting access, sign in as that person and look at what '
              'is actually visible.',
        )),
    ));

    // ── Защита ───────────────────────────────────────────────────────────
    out.add(c.folder('kb_m_shield', c.t('Защита', 'Shield'),
        parentId: 'kb_modules', order: 7, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_shield_first',
      c.t('Замок на приложение', 'Locking the app'),
      parentId: 'kb_m_shield',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['защита', 'пароль'], ['shield', 'password']),
      doc: _Doc()
        ..h1(c.t('Замок на приложение', 'Locking the app'))
        ..p(c.t(
          'Wesi Shield закрывает приложение отдельным паролем. Смысл '
              'простой: разблокированный телефон в чужих руках не должен '
              'означать «показал все свои деньги».',
          'Wesi Shield locks the app behind its own password. The point is '
              'simple: an unlocked phone in someone else\'s hands should not '
              'mean "showed them all my money".',
        ))
        ..h2(c.t('Что важно знать до включения', 'Before you turn it on'))
        ..bullets([
          c.t('Пароль хранится только на этом устройстве и никуда не '
              'уезжает.',
              'The password stays on this device and never travels.'),
          c.t('Восстановить его нельзя. Забытый пароль означает потерю '
              'доступа к тому, что он закрывает.',
              'It cannot be recovered. A forgotten password means losing '
                  'access to what it protects.'),
          c.t('Можно закрыть либо всё приложение, либо только денежную часть.',
              'You can lock either the whole app or just the money part.'),
        ])
        ..h2(c.t('Открыть сейчас', 'Open now'))
        ..route(c.t('Открыть защиту', 'Open Shield'), 'shield'),
    ));

    // ── Синхронизация ────────────────────────────────────────────────────
    out.add(c.folder('kb_m_sync', c.t('Синхронизация', 'Sync'),
        parentId: 'kb_modules', order: 8, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_sync_first',
      c.t('Связать телефон и компьютер', 'Linking phone and computer'),
      parentId: 'kb_m_sync',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['синхронизация'], ['sync']),
      doc: _Doc()
        ..h1(c.t('Связать телефон и компьютер', 'Linking phone and computer'))
        ..p(c.t(
          'Адрес сервера вводить не нужно — он зашит в программу. Нужны '
              'только логин и пароль, и один раз на каждом устройстве.',
          'You do not enter a server address — it is built into the app. '
              'Only a login and password, once per device.',
        ))
        ..steps([
          c.t('Профиль → Синхронизация.', 'Profile → Sync.'),
          c.t('Введите логин и пароль, нажмите «Войти».',
              'Enter login and password, tap "Sign in".'),
          c.t('Дальше обмен идёт сам, через пару секунд после любой правки.',
              'From then on the exchange happens by itself, a couple of '
                  'seconds after any change.'),
          c.t('На втором устройстве войдите под тем же логином.',
              'On the second device sign in with the same login.'),
        ])
        ..h2(c.t('Кнопка «Синхронизировать сейчас»', 'The "Sync now" button'))
        ..p(c.t(
          'Она осталась, но нажимать её не обязано быть условием того, что '
              'данные доедут. Она про «прямо сию секунду», а не про «иначе не '
              'уедет».',
          'It is still there, but pressing it is not a condition for your '
              'data arriving. It means "right this second", not "otherwise '
              'it will not go".',
        )),
    ));

    out.add(c.article(
      'kb_m_sync_trouble',
      c.t('Если обмен не идёт', 'If sync is not working'),
      parentId: 'kb_m_sync',
      order: 1,
      section: ArticleSection.guide,
      tags: c.tags(['синхронизация', 'ошибки'], ['sync', 'errors']),
      doc: _Doc()
        ..h1(c.t('Если обмен не идёт', 'If sync is not working'))
        ..p(c.t(
          'Сначала посмотрите, что написано в карточке синхронизации в '
              'профиле. Она называет причину словами, и почти всегда это одна '
              'из трёх.',
          'First read what the sync card in your profile says. It names the '
              'reason in plain words, and it is almost always one of three.',
        ))
        ..table([
          [c.t('Написано', 'It says'), c.t('Что делать', 'What to do')],
          [
            c.t('Вход не выполнен', 'Not signed in'),
            c.t('Войдите логином и паролем. Пропуск живёт около двух недель '
                'и потом просит повторить вход.',
                'Sign in again. The pass lasts about two weeks and then asks '
                    'for a repeat.'),
          ],
          [
            c.t('Нет связи с сервером', 'No connection'),
            c.t('Проверьте интернет. Правки не потеряются — они уедут при '
                'первой возможности.',
                'Check the internet. Nothing is lost — changes go out at the '
                    'first opportunity.'),
          ],
          [
            c.t('Неверный логин или пароль', 'Wrong login or password'),
            c.t('Проверьте раскладку и регистр. Логин всегда маленькими '
                'буквами.', 'Check the keyboard layout and case. Logins are '
                'always lowercase.'),
          ],
        ])
        ..p('')
        ..h2(c.t('Данные на двух устройствах разошлись',
            'The two devices disagree'))
        ..p(c.t(
          'Побеждает более поздняя правка. Если вы поменяли одну и ту же '
              'операцию в двух местах, останется та, которую сделали позже, '
              'а не та, которая «правильнее» — программа этого знать не '
              'может.',
          'The later edit wins. If you changed the same operation in two '
              'places, the later one survives — not the "more correct" one, '
              'which the app has no way of knowing.',
        )),
    ));

    // ── Обновления ───────────────────────────────────────────────────────
    out.add(c.folder('kb_m_update', c.t('Обновления', 'Updates'),
        parentId: 'kb_modules', order: 9, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_update_how',
      c.t('Как приходит обновление', 'How updates arrive'),
      parentId: 'kb_m_update',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['обновление'], ['update']),
      doc: _Doc()
        ..h1(c.t('Как приходит обновление', 'How updates arrive'))
        ..p(c.t(
          'Программа сама проверяет, вышла ли новая версия, и показывает '
              'полоску на главной. Скачивание и установка запускаются только '
              'по вашему нажатию.',
          'The app checks for a new version by itself and shows a banner on '
              'Home. Downloading and installing start only when you tap.',
        ))
        ..bullets([
          c.t('На компьютере: скачивается архив, программа закрывается, '
              'подменяет себя и открывается заново.',
              'On desktop: an archive downloads, the app closes, replaces '
                  'itself and reopens.'),
          c.t('На телефоне: скачивается пакет и открывается обычная установка '
              'Android.',
              'On phone: a package downloads and the normal Android '
                  'installer opens.'),
          c.t('Данные обновление не трогает.', 'Updates never touch your data.'),
        ]),
    ));

    out.add(c.article(
      'kb_m_update_fail',
      c.t('Если обновление не встало', 'If the update did not install'),
      parentId: 'kb_m_update',
      order: 1,
      section: ArticleSection.guide,
      tags: c.tags(['обновление', 'ошибки'], ['update', 'errors']),
      doc: _Doc()
        ..h1(c.t('Если обновление не встало', 'If the update did not install'))
        ..p(c.t(
          'При сбое программа показывает окно с коротким кодом. Код нужен, '
              'чтобы отличить «не скачалось» от «скачалось, но не '
              'заменилось», — лечится это по-разному.',
          'On failure the app shows a short code. The code separates "did '
              'not download" from "downloaded but did not replace" — those '
              'are fixed differently.',
        ))
        ..h2(c.t('Компьютер', 'Desktop'))
        ..table([
          [c.t('Код', 'Code'), c.t('Что произошло', 'What happened'),
            c.t('Что делать', 'What to do')],
          ['W101', c.t('Не удалось получить список версий',
              'Could not get the version list'),
            c.t('Проверьте интернет и повторите',
                'Check the internet and retry')],
          ['W103', c.t('Скачивание оборвалось', 'Download interrupted'),
            c.t('Повторите — файл докачается заново',
                'Retry — the file downloads again')],
          ['W105', c.t('Архив не распаковался', 'Archive did not unpack'),
            c.t('Повторите; если снова — освободите место на диске',
                'Retry; if it repeats, free some disk space')],
          ['W107', c.t('Файлы не заменились', 'Files were not replaced'),
            c.t('Чаще всего антивирус. Добавьте папку WesiOS в исключения',
                'Usually antivirus. Add the WesiOS folder to exclusions')],
          ['W109', c.t('Программа не закрылась полностью',
              'The app did not fully quit'),
            c.t('Закройте все окна WesiOS и повторите',
                'Close every WesiOS window and retry')],
        ])
        ..p('')
        ..h2(c.t('Телефон', 'Phone'))
        ..table([
          [c.t('Код', 'Code'), c.t('Что произошло', 'What happened'),
            c.t('Что делать', 'What to do')],
          ['A201', c.t('Установка запрещена', 'Install not allowed'),
            c.t('Разрешите установку из этого источника в настройках Android',
                'Allow installs from this source in Android settings')],
          ['A202', c.t('Установщик не открылся', 'Installer did not open'),
            c.t('Повторите', 'Retry')],
        ])
        ..p('')
        ..h2(c.t('Самый частый случай', 'The most common one'))
        ..p(c.t(
          'Скачалось, программа закрылась, открылась — и версия та же. Это '
              'W107: антивирус не дал заменить файлы. Исключение для папки с '
              'программой решает вопрос насовсем.',
          'It downloaded, the app closed, reopened — and the version is '
              'unchanged. That is W107: the antivirus blocked the file '
              'replacement. An exclusion for the app folder settles it for '
              'good.',
        )),
    ));

    // ── База знаний ──────────────────────────────────────────────────────
    out.add(c.folder('kb_m_kb', c.t('База знаний', 'Handbook'),
        parentId: 'kb_modules', order: 10, section: ArticleSection.guide));

    out.add(c.article(
      'kb_m_kb_write',
      c.t('Как писать свои статьи', 'Writing your own articles'),
      parentId: 'kb_m_kb',
      order: 0,
      section: ArticleSection.guide,
      tags: c.tags(['база знаний', 'статьи'], ['handbook', 'articles']),
      doc: _Doc()
        ..h1(c.t('Как писать свои статьи', 'Writing your own articles'))
        ..p(c.t(
          'Встроенные статьи помечены и не удаляются — они приходят с '
              'обновлением. Всё остальное здесь ваше: пишите, складывайте в '
              'папки, удаляйте.',
          'Built-in articles are marked and cannot be deleted — they arrive '
              'with updates. Everything else here is yours: write it, file '
              'it, delete it.',
        ))
        ..h2(c.t('Что сюда стоит писать', 'What belongs here'))
        ..bullets([
          c.t('То, что вы объясняли кому-то дважды.',
              'Anything you have explained to someone twice.'),
          c.t('Порядок действий, который легко забыть за полгода.',
              'A procedure that is easy to forget in six months.'),
          c.t('Решения и почему они такие. Через год «почему» будет ценнее '
              '«что».',
              'Decisions and why they were made. In a year the "why" beats '
                  'the "what".'),
        ])
        ..h2(c.t('Разделы', 'Sections'))
        ..p(c.t(
          'Раздел — это срез поперёк дерева: он собирает статьи одного рода '
              'из разных папок. Ставьте его по смыслу текста, а не по месту, '
              'куда положили.',
          'A section is a slice across the tree: it gathers articles of one '
              'kind from different folders. Choose it by what the text is '
              'about, not by where you filed it.',
        ))
        ..h2(c.t('Ссылки внутрь программы', 'Links into the app'))
        ..p(c.t(
          'В статью можно вставить ссылку, которая открывает нужный экран '
              'или другую статью. Инструкция, из которой можно сразу перейти '
              'туда, о чём она, читается совсем иначе.',
          'An article can carry a link that opens a screen or another '
              'article. A guide you can act on from the page itself reads '
              'very differently.',
        )),
    ));

    return out;
  }

  // ═══════════════════════════════════════════════════════ Деньги

  static List<ArticleModel> _money(_Ctx c) {
    final root = c.folder(
      'kb_money',
      c.t('Деньги', 'Money'),
      order: 2,
      section: ArticleSection.finance,
    );

    return [
      root,
      c.article(
        'kb_money_start',
        c.t('С чего начать', 'Where to start'),
        parentId: 'kb_money',
        order: 0,
        section: ArticleSection.finance,
        tags: c.tags(['деньги', 'начало'], ['money', 'start']),
        doc: _Doc()
          ..h1(c.t('С чего начать', 'Where to start'))
          ..p(c.t(
            'Не с бюджета и не с инвестиций. С одной цифры: сколько уходит в '
                'месяц. Пока она неизвестна, любое решение о деньгах — '
                'угадывание.',
            'Not with a budget and not with investing. With one number: how '
                'much leaves per month. Until you know it, every money '
                'decision is a guess.',
          ))
          ..h2(c.t('Порядок, который работает', 'The order that works'))
          ..steps([
            c.t('Месяц просто записывайте траты. Ничего не меняйте.',
                'Spend one month just recording. Change nothing.'),
            c.t('Посмотрите три крупнейшие категории. Решение почти всегда '
                'там, а не в кофе.',
                'Look at the three biggest categories. The answer is there, '
                    'not in your coffee.'),
            c.t('Соберите подушку на один месяц жизни.',
                'Build one month of living expenses as a cushion.'),
            c.t('Разберитесь с долгами, если они есть.',
                'Deal with debt, if any.'),
            c.t('И только потом — накопления и всё остальное.',
                'Only then — saving and everything else.'),
          ])
          ..h2(c.t('Почему именно так', 'Why this order'))
          ..p(c.t(
            'Каждый следующий шаг бессмысленен без предыдущего. Копить, имея '
                'долг под большой процент, — это платить банку за то, чтобы '
                'чувствовать себя ответственным.',
            'Each step is pointless without the one before. Saving while '
                'carrying high-interest debt means paying the bank for the '
                'feeling of being responsible.',
          )),
      ),
      c.article(
        'kb_money_cushion',
        c.t('Подушка: сколько и где', 'The cushion: how much and where'),
        parentId: 'kb_money',
        order: 1,
        section: ArticleSection.finance,
        tags: c.tags(['подушка', 'сбережения'], ['cushion', 'savings']),
        doc: _Doc()
          ..h1(c.t('Подушка: сколько и где', 'The cushion: how much and where'))
          ..p(c.t(
            'Подушка — это не накопления. Это сумма, которая позволяет не '
                'принимать плохих решений в плохой момент: не соглашаться на '
                'первую попавшуюся работу и не брать кредит на ремонт '
                'холодильника.',
            'A cushion is not savings. It is the amount that lets you avoid '
                'bad decisions at a bad moment: not taking the first job '
                'offered, not borrowing to fix a fridge.',
          ))
          ..h2(c.t('Сколько', 'How much'))
          ..bullets([
            c.t('Первая цель — один месяц расходов. Она достижима и меняет '
                'ощущение сразу.',
                'First target: one month of expenses. Reachable, and it '
                    'changes how you feel immediately.'),
            c.t('Дальше — три месяца. Этого хватает на спокойный поиск '
                'работы.',
                'Then three months. Enough for an unhurried job search.'),
            c.t('Шесть месяцев — если доход нерегулярный или вы один '
                'кормилец.',
                'Six months if your income is irregular or you are the only '
                    'earner.'),
          ])
          ..h2(c.t('Где держать', 'Where to keep it'))
          ..p(c.t(
            'Там, откуда можно забрать сегодня и без потерь. Подушка в '
                'акциях — это не подушка: беда обычно приходит ровно тогда, '
                'когда рынок внизу.',
            'Somewhere you can take it today without a loss. A cushion in '
                'stocks is not a cushion: trouble tends to arrive exactly '
                'when the market is down.',
          ))
          ..h2(c.t('Признак, что это работает', 'The sign it works'))
          ..p(c.t(
            'Сломавшаяся техника перестаёт быть катастрофой и становится '
                'расходом. Разница между этими двумя словами и есть весь '
                'смысл подушки.',
            'A broken appliance stops being a disaster and becomes an '
                'expense. The distance between those two words is the whole '
                'point.',
          )),
      ),
      c.article(
        'kb_money_budget',
        c.t('Бюджет, который не бросают', 'A budget you will not abandon'),
        parentId: 'kb_money',
        order: 2,
        section: ArticleSection.finance,
        tags: c.tags(['бюджет'], ['budget']),
        doc: _Doc()
          ..h1(c.t('Бюджет, который не бросают',
              'A budget you will not abandon'))
          ..p(c.t(
            'Подробный бюджет по двадцати категориям бросают за две недели. '
                'Работает грубый, из трёх частей, потому что его не надо '
                'помнить.',
            'A detailed twenty-category budget dies in two weeks. A rough '
                'three-part one works, because there is nothing to remember.',
          ))
          ..h2(c.t('Три части', 'Three parts'))
          ..bullets([
            c.t('Обязательное: жильё, еда, транспорт, кредиты, связь.',
                'Fixed: housing, food, transport, loans, phone.'),
            c.t('Свободное: всё, на что вы тратите по желанию.',
                'Free: everything you spend by choice.'),
            c.t('Отложенное: то, что уходит с карты в день зарплаты.',
                'Saved: what leaves the account on payday.'),
          ])
          ..h2(c.t('Главный приём', 'The one trick'))
          ..p(c.t(
            'Откладывать в день получения, а не в конце месяца из остатка. '
                'Остатка не бывает — это не жадность, а свойство внимания.',
            'Save on the day you get paid, not from what is left at month '
                'end. There is never anything left — that is not greed, it '
                'is how attention works.',
          ))
          ..h2(c.t('Когда бюджет всё-таки нарушен',
              'When the budget breaks anyway'))
          ..p(c.t(
            'Это нормально и случается у всех. Плохо не превышение, а вывод '
                '«значит, учёт не работает». Превышение — это как раз '
                'информация, ради которой всё затевалось.',
            'That is normal and happens to everyone. The overspend is not '
                'the problem; the conclusion "so tracking does not work" is. '
                'The overspend is exactly the information you were after.',
          )),
      ),
      c.article(
        'kb_money_debt',
        c.t('Долги: какой гасить первым', 'Debt: which one first'),
        parentId: 'kb_money',
        order: 3,
        section: ArticleSection.finance,
        tags: c.tags(['долги', 'кредит'], ['debt', 'loans']),
        doc: _Doc()
          ..h1(c.t('Долги: какой гасить первым', 'Debt: which one first'))
          ..p(c.t(
            'Если долгов несколько, порядок важнее суммы платежа. Есть два '
                'честных подхода, и оба лучше, чем платить всем понемногу.',
            'With several debts the order matters more than the payment '
                'size. There are two honest approaches, and both beat paying '
                'a little to everyone.',
          ))
          ..h2(c.t('По ставке', 'By interest rate'))
          ..p(c.t(
            'Сначала самый дорогой процент. Математически это дешевле всего '
                'и заканчивается быстрее.',
            'Highest rate first. Mathematically the cheapest and the fastest '
                'to finish.',
          ))
          ..h2(c.t('По размеру', 'By size'))
          ..p(c.t(
            'Сначала самый маленький долг. Дороже на бумаге, но каждый '
                'закрытый долг — это видимая победа, а бросают обычно от '
                'ощущения бесконечности.',
            'Smallest balance first. More expensive on paper, but each '
                'closed debt is a visible win — and people usually quit from '
                'the feeling that it never ends.',
          ))
          ..h2(c.t('Что не работает', 'What does not work'))
          ..bullets([
            c.t('Новый кредит, чтобы закрыть старый, без изменения привычек.',
                'A new loan to close an old one without changing habits.'),
            c.t('Копить и обслуживать дорогой долг одновременно.',
                'Saving and servicing expensive debt at the same time.'),
            c.t('Не считать, сколько всего должны. Пока цифра неизвестна, '
                'она кажется больше, чем есть.',
                'Not knowing the total. While the number is unknown it feels '
                    'bigger than it is.'),
          ]),
      ),
      c.article(
        'kb_money_big',
        c.t('Крупная покупка', 'A big purchase'),
        parentId: 'kb_money',
        order: 4,
        section: ArticleSection.finance,
        tags: c.tags(['покупки', 'планирование'], ['purchases', 'planning']),
        doc: _Doc()
          ..h1(c.t('Крупная покупка', 'A big purchase'))
          ..p(c.t(
            'Крупная — это та, которую нельзя оплатить из месячного остатка, '
                'не задев обязательное. Для неё есть простой порядок.',
            'Big means you cannot pay for it from the monthly leftover '
                'without touching the fixed part. There is a simple order '
                'for it.',
          ))
          ..steps([
            c.t('Назовите точную сумму. Не «примерно», а с доставкой и всем '
                'сопутствующим.',
                'Name the exact amount. Not "about" — with delivery and '
                    'everything around it.'),
            c.t('Разделите на число месяцев, которые готовы ждать. Получилась '
                'ежемесячная сумма.',
                'Divide by the months you are willing to wait. That is your '
                    'monthly amount.'),
            c.t('Внесите её как регулярный платёж самому себе — тогда '
                'прогноз будет её учитывать.',
                'Enter it as a recurring payment to yourself — then the '
                    'forecast accounts for it.'),
            c.t('Дождитесь конца срока. Если к тому моменту вещь всё ещё '
                'нужна — покупайте спокойно.',
                'Wait it out. If you still want the thing at the end, buy it '
                    'without second thoughts.'),
          ])
          ..h2(c.t('Про рассрочку', 'About instalments'))
          ..p(c.t(
            'Рассрочка не делает вещь дешевле — она делает её незаметнее. '
                'Проверка простая: если вы не готовы отложить эту сумму '
                'четыре месяца, вы не готовы платить её четыре месяца.',
            'Instalments do not make a thing cheaper, only less noticeable. '
                'The test is simple: if you are not willing to save that '
                'amount for four months, you are not willing to pay it for '
                'four months.',
          )),
      ),
      c.article(
        'kb_money_uneven',
        c.t('Когда доход скачет', 'When income is uneven'),
        parentId: 'kb_money',
        order: 5,
        section: ArticleSection.finance,
        tags: c.tags(['доход', 'фриланс'], ['income', 'freelance']),
        doc: _Doc()
          ..h1(c.t('Когда доход скачет', 'When income is uneven'))
          ..p(c.t(
            'У фрилансера, сезонного дела и сдельной работы месяц на месяц '
                'не приходится. Обычные советы про «десять процентов от '
                'зарплаты» тут не работают.',
            'For freelancers, seasonal businesses and piecework, months do '
                'not match. The usual "save ten percent of your salary" '
                'advice does not apply.',
          ))
          ..h2(c.t('Приём: платить себе зарплату',
              'The trick: pay yourself a salary'))
          ..steps([
            c.t('Посчитайте средний доход за последние 6–12 месяцев.',
                'Work out the average income over the last 6–12 months.'),
            c.t('Возьмите примерно 70% от него — это ваша «зарплата».',
                'Take roughly 70% of it — that is your "salary".'),
            c.t('Всё, что приходит сверх, откладывайте на буфер.',
                'Everything above that goes into a buffer.'),
            c.t('В плохой месяц берите недостающее из буфера, а не из '
                'привычек.',
                'In a bad month draw the difference from the buffer, not '
                    'from your habits.'),
          ])
          ..h2(c.t('Отдельно про налоги', 'Taxes deserve their own place'))
          ..p(c.t(
            'Откладывайте налог сразу, в день поступления, и считайте эти '
                'деньги чужими. Налог, который «где-то в общей сумме», '
                'обнаруживается ровно тогда, когда его нечем заплатить.',
            'Set tax aside the day the money arrives and treat it as someone '
                'else\'s. Tax that lives "somewhere in the total" is '
                'discovered exactly when there is nothing to pay it with.',
          )),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════ Работа

  static List<ArticleModel> _work(_Ctx c) {
    final root = c.folder(
      'kb_work',
      c.t('Работа и дело', 'Work'),
      order: 3,
      section: ArticleSection.playbook,
    );

    return [
      root,
      c.article(
        'kb_work_start',
        c.t('Первая работа', 'Your first job'),
        parentId: 'kb_work',
        order: 0,
        section: ArticleSection.playbook,
        tags: c.tags(['работа', 'начало'], ['work', 'start']),
        doc: _Doc()
          ..h1(c.t('Первая работа', 'Your first job'))
          ..p(c.t(
            'Первые месяцы почти всегда страшнее, чем оказываются. Помогает '
                'знать несколько вещей заранее.',
            'The first months are almost always scarier in advance than they '
                'turn out to be. A few things help to know beforehand.',
          ))
          ..h2(c.t('Что действительно важно', 'What actually matters'))
          ..bullets([
            c.t('Спрашивать сразу, а не через три дня молчаливого тупика. '
                'Вопрос стоит дешевле переделки.',
                'Ask right away instead of three days of silent stalling. A '
                    'question is cheaper than redoing the work.'),
            c.t('Записывать, что вам объяснили. Второй раз объясняют хуже.',
                'Write down what you were told. The second explanation is '
                    'always worse.'),
            c.t('Предупреждать о срыве срока заранее, а не в день сдачи. '
                'Опоздание прощают, внезапность — нет.',
                'Warn about a slip in advance, not on the deadline. People '
                    'forgive lateness, not surprises.'),
          ])
          ..h2(c.t('Про договор', 'About the contract'))
          ..p(c.t(
            'Прочитайте, что написано про испытательный срок, сроки выплат и '
                'что происходит при увольнении. Это три места, где потом '
                'возникают все споры.',
            'Read what it says about the probation period, payment dates and '
                'what happens if you leave. Those three spots produce every '
                'later dispute.',
          )),
      ),
      c.article(
        'kb_work_price',
        c.t('Сколько просить за работу', 'What to charge'),
        parentId: 'kb_work',
        order: 1,
        section: ArticleSection.playbook,
        tags: c.tags(['цена', 'переговоры'], ['pricing', 'negotiation']),
        doc: _Doc()
          ..h1(c.t('Сколько просить за работу', 'What to charge'))
          ..p(c.t(
            'Самая частая ошибка — называть цену от своих расходов. Заказчику '
                'всё равно, сколько вы платите за квартиру; ему важно, чего '
                'стоит результат.',
            'The most common mistake is pricing from your own costs. The '
                'client does not care what your rent is; they care what the '
                'result is worth.',
          ))
          ..h2(c.t('Три опоры', 'Three anchors'))
          ..bullets([
            c.t('Нижняя граница: ниже неё браться незачем, лучше отдохнуть.',
                'A floor: below it the work is not worth taking at all.'),
            c.t('Рынок: сколько берут за похожее. Спросите у двоих-троих.',
                'The market: what others charge for similar work. Ask two or '
                    'three people.'),
            c.t('Ценность: что заказчик получит. Одна и та же работа стоит '
                'разного в разных ситуациях.',
                'The value: what the client gets. The same work is worth '
                    'different amounts in different situations.'),
          ])
          ..h2(c.t('Как называть', 'How to say it'))
          ..p(c.t(
            'Называйте цифру спокойно и не извиняйтесь. Пауза после названной '
                'цены — не ваша задача её заполнять. Готовность объяснить '
                'состав работы — да; готовность сразу снизить — нет.',
            'Say the number calmly and do not apologise. The pause after it '
                'is not yours to fill. Be ready to explain what the work '
                'includes — not to drop the price on the spot.',
          ))
          ..h2(c.t('Признак, что цена низкая',
              'A sign your price is too low'))
          ..p(c.t(
            'Соглашаются сразу и без вопросов — почти всегда. Это не повод '
                'отказываться от этого заказа, но повод поднять цену '
                'следующему.',
            'Everyone agrees immediately, every time. Not a reason to refuse '
                'this job, but a reason to raise the price for the next one.',
          )),
      ),
      c.article(
        'kb_work_deal',
        c.t('Договориться письменно', 'Put it in writing'),
        parentId: 'kb_work',
        order: 2,
        section: ArticleSection.playbook,
        tags: c.tags(['договор', 'заказчик'], ['agreement', 'client']),
        doc: _Doc()
          ..h1(c.t('Договориться письменно', 'Put it in writing'))
          ..p(c.t(
            'Спор почти никогда не про злой умысел. Он про то, что двое '
                'по-разному помнят разговор месячной давности. Письменная '
                'договорённость — не про недоверие, а про память.',
            'Disputes are almost never about bad faith. They are about two '
                'people remembering a month-old conversation differently. '
                'Writing it down is not about distrust — it is about memory.',
          ))
          ..h2(c.t('Что записать обязательно', 'What must be written down'))
          ..bullets([
            c.t('Что именно считается сделанным.',
                'What exactly counts as done.'),
            c.t('Сколько и когда платят.', 'How much and when they pay.'),
            c.t('Сколько правок входит в цену.',
                'How many revisions the price includes.'),
            c.t('Что происходит, если работу отменяют посередине.',
                'What happens if the work is cancelled halfway.'),
          ])
          ..h2(c.t('Достаточно переписки', 'A chat is enough'))
          ..p(c.t(
            'Не всегда нужен договор на трёх листах. Часто хватает сообщения '
                '«итого: делаю то-то, срок такой, сумма такая, две правки» — '
                'и ответа «да». Именно поэтому переписка живёт внутри '
                'программы рядом с деньгами.',
            'You do not always need a three-page contract. Often a message '
                'saying "to confirm: I do X by date Y for amount Z, two '
                'revisions" and a "yes" is enough. That is exactly why chats '
                'live inside the app next to the money.',
          )),
      ),
      c.article(
        'kb_work_self',
        c.t('Самозанятость: как это устроено',
            'Self-employment: how it works'),
        parentId: 'kb_work',
        order: 3,
        section: ArticleSection.playbook,
        tags: c.tags(['самозанятость', 'налоги'], ['self-employed', 'taxes']),
        doc: _Doc()
          ..h1(c.t('Самозанятость: как это устроено',
              'Self-employment: how it works'))
          ..p(c.t(
            'Общая механика одинакова почти везде: вы регистрируетесь, '
                'выставляете чек за каждую оплату и раз в месяц платите налог '
                'с полученного. Ставки и правила зависят от страны и '
                'меняются — их обязательно надо проверить в официальном '
                'источнике, а не в справке приложения.',
            'The general mechanics are similar almost everywhere: you '
                'register, issue a receipt for each payment, and pay tax on '
                'the total once a month. Rates and rules depend on the '
                'country and change — check an official source, not an app '
                'handbook.',
          ))
          ..h2(c.t('Что важно с первого дня', 'What matters from day one'))
          ..bullets([
            c.t('Чек выставлять сразу при получении денег, а не в конце '
                'месяца по памяти.',
                'Issue the receipt when the money arrives, not from memory '
                    'at month end.'),
            c.t('Налог откладывать в тот же день. Считайте эти деньги '
                'чужими.',
                'Set the tax aside the same day. Treat that money as '
                    'someone else\'s.'),
            c.t('Хранить, кто и за что заплатил. Через год вы не вспомните.',
                'Keep a record of who paid for what. In a year you will not '
                    'remember.'),
          ])
          ..h2(c.t('Как это ведут здесь', 'How to track it here'))
          ..p(c.t(
            'Заведите отдельный счёт для дела и отдельную категорию для '
                'налога. Тогда «сколько я заработал» и «сколько из этого '
                'моё» перестают быть одним числом.',
            'Create a separate account for the business and a separate '
                'category for tax. Then "what I earned" and "what is mine" '
                'stop being the same number.',
          )),
      ),
      c.article(
        'kb_work_burn',
        c.t('Выгорание', 'Burnout'),
        parentId: 'kb_work',
        order: 4,
        section: ArticleSection.personal,
        tags: c.tags(['выгорание', 'усталость'], ['burnout', 'fatigue']),
        doc: _Doc()
          ..h1(c.t('Выгорание', 'Burnout'))
          ..p(c.t(
            'Выгорание — не «устал». Устал проходит за выходные. Выгорание '
                'не проходит за отпуск и возвращается на второй день после '
                'выхода.',
            'Burnout is not tiredness. Tiredness passes over a weekend. '
                'Burnout survives a holiday and comes back on your second '
                'day at work.',
          ))
          ..h2(c.t('Ранние признаки', 'Early signs'))
          ..bullets([
            c.t('Воскресный вечер портится задолго до понедельника.',
                'Sunday evening spoils long before Monday.'),
            c.t('Простые задачи стали занимать втрое дольше.',
                'Simple tasks take three times longer.'),
            c.t('Раздражение на людей, которые ни при чём.',
                'Irritation at people who have nothing to do with it.'),
            c.t('Пропало любопытство — не силы, а именно интерес.',
                'Curiosity is gone — not energy, interest.'),
          ])
          ..h2(c.t('Что помогает раньше', 'What helps early'))
          ..p(c.t(
            'Не героическое усилие, а границы: конец рабочего дня, выходной '
                'без переписки, один отказ в неделю. Выгорание растёт из '
                'постоянного «ещё чуть-чуть», а не из объёма работы как '
                'такового.',
            'Not heroic effort but boundaries: an end to the working day, a '
                'day off with no messages, one refusal a week. Burnout grows '
                'from constant "just a bit more", not from the volume of '
                'work itself.',
          ))
          ..h2(c.t('Когда пора к специалисту', 'When to get help'))
          ..p(c.t(
            'Если состояние держится месяцами, задевает сон и отношения — это '
                'не вопрос дисциплины и не лечится списком дел. Поговорите с '
                'врачом или психотерапевтом.',
            'If it lasts for months and reaches your sleep and your '
                'relationships, it is not a discipline problem and no to-do '
                'list will fix it. Talk to a doctor or a therapist.',
          )),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════ Жизнь

  static List<ArticleModel> _life(_Ctx c) {
    final root = c.folder(
      'kb_life',
      c.t('Жизнь', 'Life'),
      order: 4,
      section: ArticleSection.personal,
    );

    return [
      root,
      c.article(
        'kb_life_habit',
        c.t('Привычка держится на среде', 'Habits run on surroundings'),
        parentId: 'kb_life',
        order: 0,
        section: ArticleSection.personal,
        tags: c.tags(['привычки'], ['habits']),
        doc: _Doc()
          ..h1(c.t('Привычка держится на среде', 'Habits run on surroundings'))
          ..p(c.t(
            'Сила воли — расходуемая вещь, и к вечеру её нет. Поэтому '
                'привычки, построенные на «надо себя заставить», держатся '
                'ровно до первой тяжёлой недели.',
            'Willpower is consumable and by evening it is gone. Habits built '
                'on "I must make myself" last exactly until the first hard '
                'week.',
          ))
          ..h2(c.t('Что работает вместо воли', 'What works instead'))
          ..bullets([
            c.t('Убрать препятствие: форма для зала — у двери, а не в шкафу.',
                'Remove the obstacle: gym clothes by the door, not in the '
                    'wardrobe.'),
            c.t('Привязать к тому, что уже происходит: после чистки зубов, '
                'после обеда.',
                'Attach it to something that already happens: after brushing '
                    'your teeth, after lunch.'),
            c.t('Уменьшить до неловко маленького: две минуты, одна страница, '
                'одна запись.',
                'Shrink it to embarrassingly small: two minutes, one page, '
                    'one entry.'),
          ])
          ..h2(c.t('Правило пропуска', 'The missed-day rule'))
          ..p(c.t(
            'Пропустить один раз — ничего. Пропустить два подряд — уже начало '
                'конца. Возвращайтесь на следующий день, даже в уменьшенном '
                'виде.',
            'Missing once is nothing. Missing twice in a row is where it '
                'ends. Come back the next day, even in the shrunken version.',
          )),
      ),
      c.article(
        'kb_life_attention',
        c.t('Куда исчез день', 'Where the day went'),
        parentId: 'kb_life',
        order: 1,
        section: ArticleSection.personal,
        tags: c.tags(['внимание', 'время'], ['attention', 'time']),
        doc: _Doc()
          ..h1(c.t('Куда исчез день', 'Where the day went'))
          ..p(c.t(
            'Ощущение «весь день что-то делал и ничего не сделал» почти '
                'всегда означает не лень, а раздробленное внимание.',
            'The feeling of "busy all day and nothing done" almost never '
                'means laziness. It means shattered attention.',
          ))
          ..h2(c.t('Откуда берётся', 'Where it comes from'))
          ..p(c.t(
            'После каждого переключения нужно время, чтобы вернуться в '
                'задачу. Десять переключений за час — это час, в котором '
                'работы почти не было, хотя вы не отдыхали ни минуты.',
            'Every switch costs time to get back into the task. Ten switches '
                'in an hour is an hour with almost no work in it, even '
                'though you never rested.',
          ))
          ..h2(c.t('Что делать', 'What to do'))
          ..steps([
            c.t('Выберите одну задачу на ближайший час. Одну.',
                'Pick one task for the next hour. One.'),
            c.t('Уберите уведомления на это время, а не «на потом».',
                'Silence notifications for that hour, not "later".'),
            c.t('Мысли о других делах записывайте, а не выполняйте.',
                'Write other thoughts down instead of acting on them.'),
            c.t('Через час сделайте перерыв по-настоящему — без экрана.',
                'After the hour take a real break — away from a screen.'),
          ])
          ..h2(c.t('Про списки', 'About lists'))
          ..p(c.t(
            'Список дел нужен не для дисциплины, а чтобы голова перестала '
                'держать всё сразу. Записанное перестаёт всплывать посреди '
                'другой работы.',
            'A to-do list is not for discipline. It is so your head stops '
                'holding everything at once. Written things stop surfacing '
                'in the middle of other work.',
          )),
      ),
      c.article(
        'kb_life_sleep',
        c.t('Сон', 'Sleep'),
        parentId: 'kb_life',
        order: 2,
        section: ArticleSection.personal,
        tags: c.tags(['сон', 'здоровье'], ['sleep', 'health']),
        doc: _Doc()
          ..h1(c.t('Сон', 'Sleep'))
          ..p(c.t(
            'Недосып не отдаёт долг по выходным и первым делом бьёт по тому, '
                'чем вы принимаете решения. Экономия на сне — самая дорогая '
                'из бытовых.',
            'Lost sleep is not repaid at the weekend, and the first thing it '
                'takes is the part of you that makes decisions. Cutting '
                'sleep is the most expensive saving there is.',
          ))
          ..h2(c.t('Три вещи, которые дают больше всего',
              'The three that matter most'))
          ..bullets([
            c.t('Ложиться и вставать примерно в одно время, включая выходные.',
                'Roughly the same times to bed and up, weekends included.'),
            c.t('Час до сна — без яркого экрана и без рабочих разговоров.',
                'An hour before bed with no bright screen and no work talk.'),
            c.t('Прохладная тёмная комната. Это даёт больше, чем любые '
                'добавки.',
                'A cool dark room. It beats any supplement.'),
          ])
          ..h2(c.t('Если не спится от мыслей',
              'If your head will not stop'))
          ..p(c.t(
            'Запишите то, что крутится, — хоть в задачи, хоть на бумагу. '
                'Голова держит мысль ночью именно потому, что боится её '
                'потерять.',
            'Write down whatever is spinning — in tasks or on paper. Your '
                'head keeps a thought at night precisely because it is '
                'afraid of losing it.',
          )),
      ),
      c.article(
        'kb_life_talk',
        c.t('Трудный разговор', 'A hard conversation'),
        parentId: 'kb_life',
        order: 3,
        section: ArticleSection.personal,
        tags: c.tags(['разговор', 'отношения'], ['conversation', 'people']),
        doc: _Doc()
          ..h1(c.t('Трудный разговор', 'A hard conversation'))
          ..p(c.t(
            'Разговор, который откладывают, дорожает. Через месяц придётся '
                'обсуждать не только сам вопрос, но и месяц молчания.',
            'A postponed conversation gets more expensive. In a month you '
                'will be discussing not only the issue but also the month of '
                'silence.',
          ))
          ..h2(c.t('Порядок, который снижает температуру',
              'An order that lowers the heat'))
          ..steps([
            c.t('Скажите факт, а не оценку: «счёт пришёл на неделю позже», а '
                'не «ты вечно тянешь».',
                'State a fact, not a judgement: "the invoice came a week '
                    'late", not "you always drag".'),
            c.t('Скажите, чем это обернулось для вас.',
                'Say what it cost you.'),
            c.t('Скажите, чего хотите дальше — конкретно.',
                'Say what you want going forward — specifically.'),
            c.t('Замолчите и дайте ответить.',
                'Then stop talking and let them answer.'),
          ])
          ..h2(c.t('Чего не делать', 'What not to do'))
          ..bullets([
            c.t('Не собирать список претензий за полгода.',
                'Do not bring six months of grievances.'),
            c.t('Не начинать в переписке то, что требует голоса.',
                'Do not start in text what needs a voice.'),
            c.t('Не требовать признания вины. Вам нужен другой исход, а не '
                'капитуляция.',
                'Do not demand an admission of guilt. You want a different '
                    'outcome, not a surrender.'),
          ]),
      ),
      c.article(
        'kb_life_docs',
        c.t('Документы и что делать, если потерял',
            'Documents, and losing them'),
        parentId: 'kb_life',
        order: 4,
        section: ArticleSection.personal,
        tags: c.tags(['документы', 'быт'], ['documents', 'everyday']),
        doc: _Doc()
          ..h1(c.t('Документы и что делать, если потерял',
              'Documents, and losing them'))
          ..p(c.t(
            'Порядок действий зависит от страны, но подготовка везде одна и '
                'та же, и делается заранее — потому что в момент потери '
                'думать некогда.',
            'The exact procedure depends on the country, but the preparation '
                'is the same everywhere and is done in advance — because at '
                'the moment of loss there is no time to think.',
          ))
          ..h2(c.t('Что сделать сегодня', 'Do this today'))
          ..bullets([
            c.t('Сфотографируйте главные документы и положите копии туда, '
                'куда попадёте без телефона.',
                'Photograph your main documents and store copies where you '
                    'can reach them without your phone.'),
            c.t('Запишите номера банковских телефонов отдельно от телефона.',
                'Write down your bank\'s phone numbers somewhere other than '
                    'your phone.'),
            c.t('Держите один запасной способ входа в почту.',
                'Keep one backup way into your email.'),
          ])
          ..h2(c.t('Если потеряли', 'If it is gone'))
          ..steps([
            c.t('Сначала блокируйте то, чем можно воспользоваться: карты, '
                'доступы.',
                'First block what can be used: cards, access.'),
            c.t('Потом заявляйте о потере официально.',
                'Then report the loss officially.'),
            c.t('Потом восстанавливайте. Именно в этом порядке.',
                'Then replace. In that order.'),
          ])
          ..h2(c.t('Здесь этому место есть', 'There is a place for this here'))
          ..p(c.t(
            'Свой список «где что лежит» удобно завести статьёй в этой базе '
                'знаний и закрыть паролем Wesi Shield.',
            'Your own "where everything is" list works well as an article in '
                'this handbook, locked behind the Wesi Shield password.',
          )),
      ),
      c.article(
        'kb_life_hard',
        c.t('Когда всё навалилось', 'When it all piles up'),
        parentId: 'kb_life',
        order: 5,
        section: ArticleSection.personal,
        tags: c.tags(['стресс', 'помощь'], ['stress', 'help']),
        doc: _Doc()
          ..h1(c.t('Когда всё навалилось', 'When it all piles up'))
          ..p(c.t(
            'Бывает состояние, когда дел столько, что не делается ни одно. '
                'Это не лень и не слабость: голова не умеет держать двадцать '
                'открытых вопросов и работать одновременно.',
            'There is a state where there is so much to do that nothing gets '
                'done. It is not laziness or weakness: a head cannot hold '
                'twenty open questions and work at the same time.',
          ))
          ..h2(c.t('Первое действие', 'The first move'))
          ..p(c.t(
            'Выгрузить всё из головы на бумагу или в задачи. Не сортировать, '
                'не оценивать — просто выписать. Список из двадцати пунктов '
                'почти всегда оказывается короче, чем ощущение от него.',
            'Empty your head onto paper or into tasks. Do not sort or judge '
                '— just write. A list of twenty items is almost always '
                'shorter than the feeling of it.',
          ))
          ..h2(c.t('Второе', 'The second'))
          ..steps([
            c.t('Отметьте то, что горит по-настоящему. Обычно таких два-три.',
                'Mark what is genuinely on fire. Usually two or three items.'),
            c.t('Одно из них сделайте сейчас, даже плохо.',
                'Do one of them now, even badly.'),
            c.t('Остальное поставьте на конкретный день, а не «скоро».',
                'Give the rest a specific day, not "soon".'),
          ])
          ..h2(c.t('И самое важное', 'And the important part'))
          ..p(c.t(
            'Если тяжесть держится неделями, мешает спать, есть и общаться — '
                'это не про организацию дел. Поговорите с близким человеком '
                'или со специалистом. Просить помощи — обычное действие, а не '
                'крайняя мера.',
            'If the weight stays for weeks and gets in the way of sleeping, '
                'eating and talking to people, it is not about organising '
                'tasks. Talk to someone close to you, or to a professional. '
                'Asking for help is an ordinary move, not a last resort.',
          )),
      ),
    ];
  }
}

/// Общее для всех статей: язык, время создания и сборка записи.
class _Ctx {
  _Ctx(this.ru, this.now);

  final bool ru;
  final DateTime now;

  /// Выбор языка одной строкой.
  ///
  /// Раньше `ru ? … : …` стоял в каждой строке текста, и в паре мест обе
  /// ветки оказались одинаковыми, а в паре — русская фраза с английским
  /// хвостом. Здесь то же самое, но вызов один и его видно.
  String t(String russian, String english) => ru ? russian : english;

  List<String> tags(List<String> russian, List<String> english) =>
      ru ? russian : english;

  ArticleModel folder(
    String id,
    String title, {
    String? parentId,
    required int order,
    required ArticleSection section,
    bool pinned = false,
  }) =>
      ArticleModel(
        id: id,
        title: title,
        body: '',
        section: section,
        tags: const [],
        createdAt: now,
        updatedAt: now,
        builtIn: true,
        pinned: pinned,
        parentId: parentId,
        isFolder: true,
        orderRaw: order,
      );

  ArticleModel article(
    String id,
    String title, {
    required _Doc doc,
    required String parentId,
    required int order,
    required ArticleSection section,
    required List<String> tags,
    bool pinned = false,
  }) =>
      ArticleModel(
        id: id,
        title: title,
        body: doc.body,
        section: section,
        tags: tags,
        createdAt: now,
        updatedAt: now,
        builtIn: true,
        pinned: pinned,
        parentId: parentId,
        orderRaw: order,
      );
}

/// Документ статьи в формате Delta.
///
/// **Почему объектами, а не строками.** В Delta атрибут блока — заголовок,
/// маркер списка — принадлежит не тексту, а переводу строки, который этот
/// блок закрывает. Собранный вручную JSON нарушал это правило молча:
/// компилятор ничего не знает о Delta, анализатор тоже, и ошибка всплывала
/// уже в готовой статье как «заголовки выглядят не так». Здесь правило
/// записано ровно один раз — в [_line], — и обойти его больше нечем.
///
/// Кодирование тоже одно, в самом конце: кавычка внутри текста, апостроф в
/// подписи и вложенный JSON таблицы раньше ломали разметку целиком, каждый
/// своим способом.
class _Doc {
  final List<Map<String, Object?>> _ops = [];

  void _line(String text, [Map<String, Object?>? attributes]) {
    if (text.isNotEmpty) _ops.add({'insert': text});
    _ops.add(attributes == null
        ? {'insert': '\n'}
        : {'insert': '\n', 'attributes': attributes});
  }

  void h1(String text) => _line(text, {'header': 1});

  void h2(String text) => _line(text, {'header': 2});

  void p(String text) => _line(text);

  void bullets(List<String> items) {
    for (final item in items) {
      _line(item, {'list': 'bullet'});
    }
  }

  void steps(List<String> items) {
    for (final item in items) {
      _line(item, {'list': 'ordered'});
    }
  }

  void table(List<List<String>> rows) {
    _ops.add({
      'insert': {'table': jsonEncode(rows)}
    });
    _ops.add({'insert': '\n'});
  }

  /// Ссылка, открывающая экран программы прямо из статьи.
  void route(String text, String path) {
    _ops.add({
      'insert': text,
      'attributes': {'link': 'wesios://route/$path'},
    });
    _ops.add({'insert': '\n'});
  }

  String get body => jsonEncode(_ops);
}
