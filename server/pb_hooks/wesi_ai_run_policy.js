// Бюджет длинного прохода Wesi AI.
//
// Раньше цикл инструментов был жёстко ограничен четырьмя ходами: после
// четвёртого персона обязана была дать финальный ответ, даже если работа не
// закончена. Для «посчитай остаток» этого хватало, а для «разберись и
// приведи в порядок» — нет: человеку приходилось после каждого шага писать
// «продолжай», хотя решение продолжать не требовало от него ничего.
//
// Проход теперь идёт до конца задачи. Но «до конца» не значит «без границ»:
// без них сломанный инструмент или зациклившаяся модель будут крутиться,
// пока не кончатся деньги. Границ три, и каждая закрывает свой отказ:
//
//   steps    — сколько ходов вообще разрешено;
//   deadline — сколько времени, если ходы короткие, но их много;
//   stall    — сколько подряд ходов без пользы, если модель зациклилась.
//
// Достижение любой из них не рвёт ответ: персона получает последний ход с
// требованием подвести итог тем, что уже собрано.

var LIMITS = {
  fast: {steps: 4, deadlineMs: 90000, stall: 2},
  pro: {steps: 16, deadlineMs: 6 * 60000, stall: 3},
  maximum: {steps: 40, deadlineMs: 20 * 60000, stall: 4},
};

function limitsFor(tier) {
  var key = String(tier || "fast").trim().toLowerCase();
  return LIMITS[key] || LIMITS.fast;
}

function evaluate(input) {
  var tier = String((input && input.tier) || "fast").trim().toLowerCase();
  var limits = limitsFor(tier);
  var toolCount = Array.isArray(input && input.toolDefinitions) ? input.toolDefinitions.length : 0;

  // Без инструментов ходить некуда: остаётся один ход, он же финальный.
  var steps = toolCount > 0 ? limits.steps : 1;

  return {
    tier: tier,
    maxSteps: steps,
    deadlineMs: limits.deadlineMs,
    maxStalledSteps: limits.stall,
    // Длинный проход разрешён только там, где ходов больше одного пакета.
    autonomous: steps > 4,
    reason: toolCount > 0
      ? (steps > 4 ? "long_autonomous_run" : "short_bounded_run")
      : "no_tools_available",
  };
}

module.exports = {LIMITS: LIMITS, limitsFor: limitsFor, evaluate: evaluate};
