(() => {
  'use strict';

  const root = document.documentElement;
  const boot = document.getElementById('siteBoot');
  const bootProgress = document.getElementById('bootProgress');
  const bootPercent = document.getElementById('bootPercent');
  const bootStatus = document.getElementById('bootStatus');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const finePointer = matchMedia('(hover: hover) and (pointer: fine)').matches;

  // Карточки не получают transform из JavaScript на каждый кадр: их
  // траектории описаны CSS-keyframes и живут в композиторе.
  document.querySelectorAll('[data-float]').forEach((node, index) => {
    node.removeAttribute('data-float');
    node.classList.add('baked-float', `baked-float-${index + 1}`);
  });

  const app = document.getElementById('app');
  const gridBg = document.getElementById('gridBg');
  const spotlight = document.getElementById('spotlight');
  const progressFill = document.getElementById('scrollProgressFill');
  const progressHead = document.getElementById('scrollProgressHead');
  const railLine = document.querySelector('#motionRail .rail-line');
  const origin = document.getElementById('runnerOrigin');

  const supportsOffsetPath = CSS.supports?.('offset-path', 'path("M 0 0 L 1 1")');

  const layers = ['runnerBack', 'runnerFront'].map(id => {
    const box = document.getElementById(id);
    if (!box) return null;
    // По имени, а не по порядку в разметке: там элементы лежат в порядке
    // наложения — хвост под головой, — и совпадение индексов было бы
    // случайным. Стоило поменять местами две строки в HTML, и хвост
    // полетел бы впереди огонька.
    const parts = {};
    box.querySelectorAll('[data-runner]').forEach(node => {
      parts[node.dataset.runner] = node;
    });
    return { box, parts, shown: -1 };
  });

  const hasRunner = !reduced && supportsOffsetPath && layers.every(Boolean) && railLine && origin;

  // Звенья кометы: насколько каждое отстаёт от головы вдоль траектории.
  // Отставание растёт со скоростью — на быстром движении хвост вытягивается,
  // на медленном подбирается к голове.
  const PARTS = [
    { key: 'head', lag: 0 },
    { key: 't1', lag: .006 },
    { key: 't2', lag: .014 },
    { key: 't3', lag: .026 },
    { key: 'glow', lag: .002 },
  ];

  const clamp = (value, min = 0, max = 1) => Math.max(min, Math.min(max, value));
  const rounded = value => Math.round(value * 10) / 10;
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve));
  const smoothstep = t => t * t * (3 - 2 * t);

  // ─────────────────────────────────────────────────────── маршрут огонька
  //
  // Точки маршрута в условных координатах 0…1000 по обеим осям. Пиксели
  // считаются при укладке: offset-path работает в системе координат самого
  // элемента, а не в viewBox, как было у SVG.
  //
  // Обе крайние точки лежат ЗА пределами полосы: −240 слева и 1250 справа.
  // Раньше линия начиналась у заголовка и заканчивалась на рейке — то есть
  // возникала из ниоткуда посреди экрана и там же пропадала. Теперь она
  // влетает из-за края и улетает за край.
  const routes = {
    mobile: [
      ['M', -240, -60], ['C', -40, -26, 196, 34, 214, 140],
      ['C', 232, 246, 872, 186, 828, 314], ['C', 786, 436, 120, 384, 168, 516],
      ['C', 214, 644, 858, 590, 752, 728], ['C', 660, 848, 300, 836, 236, 934],
      ['C', 176, 1026, 900, 1032, 1250, 1075],
    ],
    tablet: [
      ['M', -240, -58], ['C', -20, -22, 268, 40, 286, 148],
      ['C', 304, 252, 830, 198, 806, 318], ['C', 782, 442, 198, 400, 232, 522],
      ['C', 268, 650, 812, 600, 734, 730], ['C', 660, 852, 318, 842, 252, 936],
      ['C', 190, 1024, 910, 1030, 1250, 1072],
    ],
    desktop: [
      ['M', -240, -55], ['C', 10, -18, 318, 44, 344, 150],
      ['C', 370, 254, 796, 210, 802, 320], ['C', 808, 446, 226, 406, 262, 526],
      ['C', 300, 656, 782, 608, 716, 734], ['C', 652, 856, 336, 848, 268, 938],
      ['C', 206, 1022, 920, 1028, 1240, 1070],
    ],
  };

  function toPath(route, width, height) {
    const kx = width / 1000;
    const ky = height / 1000;
    return route.map(([cmd, ...nums]) => {
      const scaled = nums.map((n, i) => rounded(i % 2 === 0 ? n * kx : n * ky));
      return `${cmd} ${scaled.join(' ')}`;
    }).join(' ');
  }

  // Где линия ныряет за содержимое, а где идёт поверх.
  //
  // Пары «прогресс → глубина»: 0 — перед карточками, 1 — за ними. Между
  // точками значение сглаживается, поэтому переход не заметен как момент.
  // Одним слоем это неразрешимо в принципе: смена z-index происходит
  // мгновенно и читается как рывок сквозь карточку.
  const depthStops = [
    [0.00, 0], [0.11, 0], [0.17, 1], [0.32, 1], [0.39, 0],
    [0.46, 0], [0.52, 1], [0.64, 1], [0.71, 0],
    [0.76, 0], [0.81, 1], [0.90, 1], [0.96, 0], [1.00, 0],
  ];

  function depthAt(progress) {
    for (let i = 1; i < depthStops.length; i++) {
      const [x1, y1] = depthStops[i - 1];
      const [x2, y2] = depthStops[i];
      if (progress > x2) continue;
      if (y1 === y2) return y1;
      return y1 + (y2 - y1) * smoothstep(clamp((progress - x1) / (x2 - x1)));
    }
    return depthStops[depthStops.length - 1][1];
  }

  // ─────────────────────────────────────────────────────────────── состояние
  let target = 0;
  let smooth = 0;
  let velocity = 0;
  let startY = 0;
  let endY = 1;
  let docProgress = 0;
  let docSmooth = 0;
  let routeKey = '';
  let layoutTimer = 0;
  let running = false;
  let idleFrames = 0;
  let lastScroll = 0;
  let lastTime = 0;
  let lastApplied = -1;
  let lastDepth = -1;
  let lastRail = -1;
  let lastProgress = -1;
  let pointerX = 0;
  let pointerY = 0;
  let spotX = 0;
  let spotY = 0;
  let pointerSeen = false;

  // Дальше этого линия не отстаёт никогда.
  //
  // Плавность — это сглаживание, а сглаживание по своей природе отстаёт.
  // На резком свайпе прежняя линия уезжала на пол-экрана назад и догоняла
  // уже после остановки: выглядело как подтормаживание сайта. Порог решает
  // спор в пользу правды: сглаживаем, пока отставание незаметно, и
  // подтягиваем силой, как только оно становится заметным.
  const MAX_LAG = 0.055;

  function readScroll() {
    const limit = Math.max(1, endY - startY);
    target = clamp((scrollY - startY) / limit);

    const docLimit = Math.max(1, document.documentElement.scrollHeight - innerHeight);
    docProgress = clamp(scrollY / docLimit);
  }

  function applyRunner(progress, force) {
    if (!force && Math.abs(progress - lastApplied) < .0004) return;
    lastApplied = progress;

    // Хвост вытягивается на скорости: чем быстрее листают, тем длиннее
    // шлейф — движение читается как движение, а не как перемотка.
    const rush = 1 + clamp(Math.abs(velocity) * 22, 0, 1) * 1.9;

    const depth = depthAt(progress);
    if (Math.abs(depth - lastDepth) > .004 || force) {
      lastDepth = depth;
      // Сумма непрозрачностей постоянна: огонёк не двоится на переходе.
      layers[0].box.style.opacity = `${depth.toFixed(3)}`;
      layers[1].box.style.opacity = `${(1 - depth).toFixed(3)}`;
    }

    for (const layer of layers) {
      for (const { key, lag } of PARTS) {
        const part = layer.parts[key];
        if (!part) continue;
        const at = clamp(progress - lag * rush) * 100;
        part.style.offsetDistance = `${at.toFixed(3)}%`;
      }
    }

    const visible = progress > .001 && progress < .999;
    for (const layer of layers) {
      const state = visible ? 1 : 0;
      if (state !== layer.shown) {
        layer.shown = state;
        layer.box.classList.toggle('active', visible);
      }
    }

    // Рейка откликается на пролетающий мимо огонёк.
    const rail = Math.max(0, 1 - Math.abs(progress - .84) / .13);
    if (Math.abs(rail - lastRail) > .006 || force) {
      lastRail = rail;
      railLine.style.setProperty('--runner-merge', rail.toFixed(3));
      railLine.classList.toggle('runner-merge-active', rail > .02);
    }
  }

  function applyProgressBar(value, force) {
    if (!progressFill) return;
    if (!force && Math.abs(value - lastProgress) < .0008) return;
    lastProgress = value;
    progressFill.style.transform = `scaleX(${value.toFixed(4)})`;
    if (progressHead) {
      progressHead.style.transform = `translate3d(${(value * 100).toFixed(3)}vw,0,0)`;
      progressHead.style.opacity = value > .004 && value < .999 ? '1' : '0';
    }
  }

  // Один цикл на всё: огонёк, полоса прокрутки, подсветка под курсором и
  // параллакс сетки. Четыре отдельных requestAnimationFrame стоили бы
  // четырёх пробуждений композитора на кадр ради одного и того же кадра.
  function frame(now) {
    const elapsed = lastTime ? clamp(now - lastTime, 8, 48) : 16.7;
    lastTime = now;

    // Позицию читаем здесь, а не в обработчике события: во время инерции
    // на телефоне события прокрутки приходят пачками и с задержкой, а
    // scrollY в кадре всегда актуален.
    readScroll();

    const delta = scrollY - lastScroll;
    lastScroll = scrollY;
    velocity += ((delta / Math.max(1, innerHeight)) * (16.7 / elapsed) - velocity) * .22;

    let busy = false;

    if (hasRunner) {
      const distance = target - smooth;
      const magnitude = Math.abs(distance);
      const rate = magnitude > .3 ? 42 : magnitude > .12 ? 32 : 22;
      smooth += distance * (1 - Math.exp(-rate * elapsed / 1000));
      if (Math.abs(target - smooth) > MAX_LAG) {
        smooth = target - Math.sign(distance) * MAX_LAG;
      }
      if (Math.abs(target - smooth) < .0004) smooth = target;
      applyRunner(smooth, false);
      if (Math.abs(target - smooth) > .0004) busy = true;
    }

    docSmooth += (docProgress - docSmooth) * (1 - Math.exp(-26 * elapsed / 1000));
    if (Math.abs(docProgress - docSmooth) < .0005) docSmooth = docProgress;
    applyProgressBar(docSmooth, false);
    if (Math.abs(docProgress - docSmooth) > .0005) busy = true;

    if (gridBg) {
      gridBg.style.transform = `translate3d(0,${(-scrollY * .022).toFixed(2)}px,0)`;
    }

    if (spotlight && pointerSeen) {
      spotX += (pointerX - spotX) * .12;
      spotY += (pointerY - spotY) * .12;
      spotlight.style.transform =
        `translate3d(${spotX.toFixed(1)}px,${spotY.toFixed(1)}px,0)`;
      if (Math.abs(pointerX - spotX) > .5 || Math.abs(pointerY - spotY) > .5) busy = true;
    }

    if (Math.abs(velocity) > .0004) busy = true;

    idleFrames = busy ? 0 : idleFrames + 1;
    // Несколько холостых кадров про запас — иначе цикл засыпает ровно
    // между двумя событиями прокрутки и первый кадр после паузы дёргается.
    if (idleFrames > 6 || document.hidden) {
      running = false;
      return;
    }
    requestAnimationFrame(frame);
  }

  function wake() {
    if (running || document.hidden) return;
    running = true;
    idleFrames = 0;
    lastTime = 0;
    requestAnimationFrame(frame);
  }

  function bakeRoute(force = false) {
    if (!hasRunner) return;

    const width = Math.max(document.documentElement.clientWidth, innerWidth, 1);
    const originRect = origin.getBoundingClientRect();
    const railRect = railLine.getBoundingClientRect();

    // Полоса, по которой летит огонёк, начинается выше первой секции и
    // заканчивается ниже рейки: концы маршрута обязаны лежать за экраном,
    // а не упираться в границы содержимого.
    const top = originRect.top + scrollY - innerHeight * .55;
    const bottom = railRect.top + scrollY + railRect.height + innerHeight * .3;
    const height = Math.max(900, bottom - top);
    const mode = width <= 650 ? 'mobile' : width <= 1000 ? 'tablet' : 'desktop';
    const key = `${mode}:${Math.round(width)}:${Math.round(top)}:${Math.round(height)}`;

    if (!force && key === routeKey) return;
    routeKey = key;

    const d = toPath(routes[mode], width, height);
    for (const layer of layers) {
      layer.box.style.top = `${rounded(top)}px`;
      layer.box.style.height = `${rounded(height)}px`;
      for (const part of Object.values(layer.parts)) {
        part.style.offsetPath = `path("${d}")`;
      }
    }

    startY = top;
    endY = bottom - innerHeight * .2;
    readScroll();
    smooth = target;
    lastApplied = -1;
    lastDepth = -1;
    applyRunner(smooth, true);
    applyProgressBar(docProgress, true);
  }

  function requestBake() {
    clearTimeout(layoutTimer);
    layoutTimer = setTimeout(() => requestAnimationFrame(() => {
      bakeRoute(true);
      wake();
    }), 110);
  }

  // ───────────────────────────────────────────────────────────── загрузка
  function decodeImages() {
    const tasks = [...document.images].map(image => {
      if (typeof image.decode === 'function') return image.decode().catch(() => undefined);
      if (image.complete) return Promise.resolve();
      return new Promise(resolve => {
        image.addEventListener('load', resolve, { once: true });
        image.addEventListener('error', resolve, { once: true });
      });
    });
    return Promise.allSettled(tasks);
  }

  function warmLayout() {
    // Один принудительный расчёт во время загрузочного экрана дешевле
    // серии неожиданных пересчётов во время первого быстрого свайпа.
    ['#top', '#showcase', '#moduleStage', '#flowSection', '#motionRail', '#authorization']
      .forEach(selector => document.querySelector(selector)?.getBoundingClientRect());
    document.querySelectorAll('.module-card,.flow-node,.intro-orbit,[data-scroll-reveal]')
      .forEach(node => getComputedStyle(node).transform);
    void document.body.offsetHeight;
  }

  function setBoot(percent, status) {
    const safe = clamp(Math.round(percent), 0, 100);
    if (bootProgress) bootProgress.style.transform = `scaleX(${safe / 100})`;
    if (bootPercent) bootPercent.textContent = `${safe}%`;
    if (bootStatus && status) bootStatus.textContent = status;
  }

  async function completeBoot() {
    const minimumVisible = wait(620);
    try {
      setBoot(14, 'Загружаем оформление');
      if (document.fonts?.ready) {
        await Promise.race([document.fonts.ready.catch(() => undefined), wait(850)]);
      }
      setBoot(39, 'Декодируем графику');
      await Promise.race([decodeImages(), wait(950)]);
      setBoot(66, 'Прогреваем анимации');
      warmLayout();
      bakeRoute(true);
      setBoot(88, 'Собираем первый кадр');
      await nextFrame();
      await nextFrame();
      await minimumVisible;
    } catch (_) {
      // Даже при отказе одного ресурса сайт обязан открыться.
    }
    setBoot(100, 'Готово');
    await wait(110);
    clearTimeout(window.__WESI_BOOT_FAILSAFE__);
    root.classList.remove('is-booting');
    root.classList.add('is-ready');
    window.__WESI_PORTAL_READY__ = true;
    wake();
    setTimeout(() => boot?.remove(), 520);
  }

  addEventListener('scroll', wake, { passive: true });
  addEventListener('resize', requestBake, { passive: true });
  addEventListener('orientationchange', requestBake, { passive: true });
  window.visualViewport?.addEventListener('resize', requestBake, { passive: true });
  addEventListener('load', requestBake, { once: true });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      running = false;
    } else {
      lastTime = 0;
      requestBake();
    }
  });

  if (finePointer && spotlight && !reduced) {
    root.classList.add('has-spotlight');
    addEventListener('pointermove', event => {
      if (event.pointerType === 'touch') return;
      pointerX = event.clientX;
      pointerY = event.clientY;
      if (!pointerSeen) {
        pointerSeen = true;
        spotX = pointerX;
        spotY = pointerY;
        spotlight.classList.add('visible');
      }
      wake();
    }, { passive: true });
  }

  if ('ResizeObserver' in window && app) {
    new ResizeObserver(requestBake).observe(app);
  }

  completeBoot();
})();
