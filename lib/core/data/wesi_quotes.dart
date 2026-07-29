import 'dart:math';

/// Фразы для поднятия духа на главном экране.
///
/// Задача — чтобы они не приедались, поэтому: (1) их много, (2) выбор
/// детерминирован по дате+слоту, а не чисто случаен — иначе одна и та же
/// фраза могла бы выпасть дважды подряд, и это бросается в глаза сильнее,
/// чем повтор через неделю; (3) индекс сдвигается вместе с днём, так что
/// в течение дня подборка стабильна (не мельтешит на каждой перерисовке),
/// а назавтра — уже другая.
class WesiQuote {
  final String ru;
  final String en;

  /// Кому принадлежит мысль. null — народная/без авторства, тогда
  /// подпись не рисуется вовсе, а не показывается пустой прочерк.
  final String? author;

  const WesiQuote(this.ru, this.en, [this.author]);
}

class WesiQuotes {
  const WesiQuotes._();

  /// Сколько разных фраз показывается в течение одного дня при обновлениях
  /// (смена вкладки/перезапуск). Больше 1, чтобы за день видеть несколько,
  /// но не бесконечно — иначе теряется ощущение «фраза дня».
  static const int slotsPerDay = 4;

  static final List<WesiQuote> all = [
    // — Дело, труд, ремесло —
    WesiQuote('Дорогу осилит идущий.', 'The road is mastered by the one walking it.'),
    WesiQuote('Делай что должно, и будь что будет.', 'Do what you must, and come what may.'),
    WesiQuote('Начало — половина всего.', 'The beginning is half of everything.', 'Пифагор'),
    WesiQuote('Терпение и труд всё перетрут.', 'Patience and work grind everything down.'),
    WesiQuote('Лучшее время посадить дерево было двадцать лет назад. Второе лучшее — сегодня.',
        'The best time to plant a tree was twenty years ago. The second best is today.'),
    WesiQuote('Не бойся медленного движения, бойся остановки.',
        'Do not fear moving slowly; fear standing still.'),
    WesiQuote('Кто хочет — ищет способ, кто не хочет — причину.',
        'Those who want to, find a way. Those who don\'t, find an excuse.'),
    WesiQuote('Большие дела складываются из малых шагов, сделанных сегодня.',
        'Great things are built from small steps taken today.'),
    WesiQuote('Сделанное лучше идеального.', 'Done is better than perfect.'),
    WesiQuote('Дисциплина — это мост между целью и результатом.',
        'Discipline is the bridge between goals and accomplishment.', 'Джим Рон'),
    WesiQuote('Успех — это способность идти от неудачи к неудаче, не теряя энтузиазма.',
        'Success is going from failure to failure without losing enthusiasm.', 'Уинстон Черчилль'),
    WesiQuote('Труд избавляет нас от трёх зол: скуки, порока и нужды.',
        'Work spares us from three evils: boredom, vice, and need.', 'Вольтер'),

    // — Стойкость —
    WesiQuote('Что нас не убивает, делает нас сильнее.',
        'What does not kill us makes us stronger.', 'Фридрих Ницше'),
    WesiQuote('Падать можно сколько угодно. Вставать нужно на один раз больше.',
        'Fall as many times as you like. Just get up one more time than you fall.'),
    WesiQuote('Спокойное море не сделает моряка умелым.',
        'A smooth sea never made a skilled sailor.'),
    WesiQuote('Мы не можем управлять ветром, но можем настроить паруса.',
        'We cannot control the wind, but we can adjust our sails.'),
    WesiQuote('Кризис — это возможность, одетая в рабочую одежду.',
        'A crisis is an opportunity dressed in work clothes.'),
    WesiQuote('Самая тёмная ночь — перед рассветом.',
        'The darkest hour is just before the dawn.'),
    WesiQuote('Препятствие — это и есть путь.', 'The obstacle is the way.', 'Марк Аврелий'),
    WesiQuote('Ты имеешь власть над своим разумом, а не над внешними событиями. Осознай это, и обретёшь силу.',
        'You have power over your mind — not outside events. Realize this, and you will find strength.',
        'Марк Аврелий'),

    // — Ясность мышления —
    WesiQuote('Простота — высшая форма сложности.',
        'Simplicity is the ultimate sophistication.', 'Леонардо да Винчи'),
    WesiQuote('Если не знаешь, куда плыть, ни один ветер не будет попутным.',
        'If you don\'t know which port you\'re sailing to, no wind is favourable.', 'Сенека'),
    WesiQuote('Мы страдаем чаще в воображении, чем в реальности.',
        'We suffer more in imagination than in reality.', 'Сенека'),
    WesiQuote('Знать, что мы знаем то, что знаем, и знать, что не знаем того, чего не знаем, — вот истинное знание.',
        'To know what we know, and to know what we do not know — that is true knowledge.', 'Конфуций'),
    WesiQuote('Порядок в мыслях рождает порядок в делах.',
        'Order in thought creates order in action.'),
    WesiQuote('Считай не то, что легко считается, а то, что действительно важно.',
        'Count what matters, not what is merely easy to count.'),
    WesiQuote('Кто ясно мыслит — ясно излагает.',
        'He who thinks clearly, speaks clearly.'),

    // — Время —
    WesiQuote('Время — самый дефицитный ресурс, и пока им не управляют, управлять нечем.',
        'Time is the scarcest resource; unless it is managed, nothing else can be.', 'Питер Друкер'),
    WesiQuote('Мы не располагаем малым временем — мы много его теряем.',
        'It is not that we have a short time to live, but that we waste much of it.', 'Сенека'),
    WesiQuote('Сегодня — это тот завтрашний день, о котором ты вчера беспокоился.',
        'Today is the tomorrow you worried about yesterday.'),
    WesiQuote('Час утром стоит двух вечером.',
        'One hour in the morning is worth two in the evening.'),
    WesiQuote('Занятость — не то же самое, что продуктивность.',
        'Being busy is not the same as being productive.'),

    // — Деньги и дело —
    WesiQuote('Цена — это то, что платишь. Ценность — то, что получаешь.',
        'Price is what you pay. Value is what you get.', 'Уоррен Баффет'),
    WesiQuote('Не откладывай то, что осталось после трат, — трать то, что осталось после сбережений.',
        'Do not save what is left after spending; spend what is left after saving.', 'Уоррен Баффет'),
    WesiQuote('Риск приходит от незнания того, что ты делаешь.',
        'Risk comes from not knowing what you are doing.', 'Уоррен Баффет'),
    WesiQuote('Прибыль — это награда за решённую чужую проблему.',
        'Profit is the reward for solving someone else\'s problem.'),
    WesiQuote('Считай деньги в спокойное время, чтобы не считать их в панике.',
        'Count your money in calm times, so you never count it in panic.'),
    WesiQuote('Бизнес — это марафон, который все почему-то бегут как спринт.',
        'Business is a marathon that everyone insists on running as a sprint.'),

    // — Рост —
    WesiQuote('Стань тем, кем ты являешься.', 'Become who you are.', 'Фридрих Ницше'),
    WesiQuote('Кто имеет «зачем» жить, вынесет почти любое «как».',
        'He who has a why to live can bear almost any how.', 'Фридрих Ницше'),
    WesiQuote('Сравнивай себя с собой вчерашним, а не с кем-то сегодняшним.',
        'Compare yourself to who you were yesterday, not to who someone else is today.'),
    WesiQuote('Ошибка — это не провал, это данные.',
        'A mistake is not a failure, it is data.'),
    WesiQuote('Учись так, будто будешь жить вечно. Живи так, будто умрёшь завтра.',
        'Learn as if you will live forever. Live as if you will die tomorrow.'),
    WesiQuote('Уверенность приходит не до действия, а после него.',
        'Confidence does not come before action. It comes after.'),
    WesiQuote('Один шаг за раз — всё ещё шаг вперёд.',
        'One step at a time is still a step forward.'),
    WesiQuote('Тот, кто двигает горы, начинает с малых камней.',
        'The one who moves mountains begins by carrying small stones.', 'Конфуций'),
  ];

  /// Фраза для текущего момента. Меняется несколько раз в день, но в
  /// пределах одного слота стабильна — экран не «мигает» новой цитатой
  /// на каждой перерисовке.
  static WesiQuote current({DateTime? now}) {
    final t = now ?? DateTime.now();
    final dayNumber = DateTime(t.year, t.month, t.day)
            .difference(DateTime(2020, 1, 1))
            .inDays;
    final slot = (t.hour * slotsPerDay) ~/ 24;
    // Шаг простым числом, взаимно простым с длиной списка при большинстве
    // её значений — так подборка не вырождается в короткий цикл из 2-3 фраз.
    final index = (dayNumber * slotsPerDay + slot) * 7 % all.length;
    return all[index];
  }

  /// Случайная фраза — для кнопки «показать другую», когда пользователь
  /// сам захотел сменить, не дожидаясь следующего слота.
  static WesiQuote random([Random? rng]) =>
      all[(rng ?? Random()).nextInt(all.length)];
}
