(() => {
  'use strict';

  const root = document.documentElement;
  const boot = document.getElementById('siteBoot');
  const bootProgress = document.getElementById('bootProgress');
  const bootPercent = document.getElementById('bootPercent');
  const bootStatus = document.getElementById('bootStatus');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Карточки больше не получают transform из JavaScript на каждом scroll.
  // Их траектории заранее описаны CSS-keyframes и выполняются композитором.
  document.querySelectorAll('[data-float]').forEach((node, index) => {
    node.removeAttribute('data-float');
    node.classList.add('baked-float', `baked-float-${index + 1}`);
  });

  const svg = document.getElementById('runnerSvg');
  const aura = document.getElementById('runnerAura');
  const trail = document.getElementById('runnerTrail');
  const head = document.getElementById('runnerHead');
  const origin = document.getElementById('runnerOrigin');
  const railLine = document.querySelector('#motionRail .rail-line');
  const app = document.getElementById('app');
  const hasRunner = !reduced && svg && aura && trail && head && origin && railLine;

  let target = 0;
  let smooth = 0;
  let startY = 0;
  let endY = 1;
  let frame = 0;
  let layoutTimer = 0;
  let routeKey = '';
  let lastFrameTime = 0;
  let lastApplied = -1;
  let lastLayer = '';
  let lastActive = false;
  let lastMerge = -1;

  const clamp = (value, min = 0, max = 1) => Math.max(min, Math.min(max, value));
  const rounded = value => Math.round(value * 10) / 10;
  const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
  const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve));

  const routes = {
    mobile: (sx, ex) => `M ${rounded(sx)} 0 C ${rounded(sx + 86)} 18,224 72,214 142 C 202 236,872 178,836 310 C 803 431,128 382,169 512 C 209 641,854 586,758 725 C 660 865,${rounded(ex + 174)} 846,${rounded(ex + 72)} 940 C ${rounded(ex + 27)} 980,${rounded(ex + 8)} 993,${rounded(ex)} 1000`,
    tablet: (sx, ex) => `M ${rounded(sx)} 0 C ${rounded(sx + 110)} 20,296 76,284 150 C 270 245,826 193,812 314 C 797 438,206 404,234 520 C 264 646,808 598,738 726 C 665 861,${rounded(ex + 196)} 850,${rounded(ex + 82)} 943 C ${rounded(ex + 31)} 983,${rounded(ex + 9)} 994,${rounded(ex)} 1000`,
    desktop: (sx, ex) => `M ${rounded(sx)} 0 C ${rounded(sx + 135)} 22,356 64,350 148 C 344 243,790 205,804 316 C 820 440,236 408,267 525 C 302 657,778 606,718 731 C 654 865,${rounded(ex + 215)} 856,${rounded(ex + 91)} 945 C ${rounded(ex + 34)} 984,${rounded(ex + 10)} 995,${rounded(ex)} 1000`,
  };

  function setBoot(percent, status) {
    const safe = clamp(Math.round(percent), 0, 100);
    if (bootProgress) bootProgress.style.transform = `scaleX(${safe / 100})`;
    if (bootPercent) bootPercent.textContent = `${safe}%`;
    if (bootStatus && status) bootStatus.textContent = status;
  }

  function updateTarget() {
    if (!hasRunner) return;
    target = clamp((scrollY - startY) / Math.max(1, endY - startY));
    schedule();
  }

  function applyLine(progress, force = false) {
    if (!hasRunner) return;
    if (!force && Math.abs(progress - lastApplied) < .00035) return;
    lastApplied = progress;

    const merge = clamp((progress - .82) / .18);
    const ease = merge * merge * (3 - 2 * merge);
    const trailLength = Math.max(.028, .085 * (1 - ease * .67));
    const headLength = Math.max(.009, .027 * (1 - ease * .72));
    const auraLength = Math.max(.038, trailLength * 1.24);
    const trailOffset = -Math.max(0, progress - trailLength);
    const headOffset = -Math.max(0, progress - headLength);
    const auraOffset = -Math.max(0, progress - auraLength);

    aura.style.strokeDasharray = `${auraLength} ${1 + auraLength}`;
    aura.style.strokeDashoffset = `${auraOffset}`;
    aura.style.opacity = `${.13 * (1 - ease)}`;
    trail.style.strokeDasharray = `${trailLength} ${1 + trailLength}`;
    trail.style.strokeDashoffset = `${trailOffset}`;
    trail.style.opacity = `${.31 * (1 - ease)}`;
    head.style.strokeDasharray = `${headLength} ${1 + headLength}`;
    head.style.strokeDashoffset = `${headOffset}`;
    head.style.opacity = `${1 - ease}`;

    const active = progress > .002 && progress < .9995;
    if (active !== lastActive) {
      lastActive = active;
      svg.classList.toggle('active', active);
    }

    const layer = progress > .13 && progress < .48 ? '3' : '8';
    if (layer !== lastLayer) {
      lastLayer = layer;
      svg.style.zIndex = layer;
    }

    const pulse = Math.sin(ease * Math.PI);
    if (force || Math.abs(pulse - lastMerge) > .004) {
      lastMerge = pulse;
      railLine.style.setProperty('--runner-merge', pulse.toFixed(3));
      railLine.classList.toggle('runner-merge-active', merge > .01 && merge < .995);
    }
  }

  function draw(now = performance.now(), force = false) {
    if (!hasRunner) return;

    if (force) {
      smooth = target;
    } else {
      const elapsed = lastFrameTime ? clamp(now - lastFrameTime, 8, 48) : 16.7;
      const distance = target - smooth;
      const magnitude = Math.abs(distance);

      // При медленном скролле линия течёт мягко. При быстром свайпе коэффициент
      // автоматически растёт, поэтому она догоняет экран за 1–3 кадра, а не
      // продолжает ехать позади ещё несколько сотен миллисекунд.
      const rate = magnitude > .38 ? 43 : magnitude > .18 ? 34 : magnitude > .07 ? 26 : 19;
      const alpha = 1 - Math.exp(-rate * elapsed / 1000);
      smooth += distance * alpha;
      if (magnitude > .62) smooth += (target - smooth) * .24;
      if (Math.abs(target - smooth) < .00045) smooth = target;
    }

    lastFrameTime = now;
    applyLine(smooth, force);
  }

  function render(now) {
    frame = 0;
    draw(now);
    if (Math.abs(target - smooth) > .00045 && !document.hidden) schedule();
  }

  function schedule() {
    if (hasRunner && !frame && !document.hidden) frame = requestAnimationFrame(render);
  }

  function bakeRoute(force = false) {
    if (!hasRunner) return false;

    const width = Math.max(document.documentElement.clientWidth, innerWidth, 1);
    const originRect = origin.getBoundingClientRect();
    const railRect = railLine.getBoundingClientRect();
    const top = originRect.top + scrollY + originRect.height * .5;
    const bottom = railRect.top + scrollY + Math.min(3, railRect.height * .02);
    const height = Math.max(720, bottom - top);
    const startX = ((originRect.left + originRect.width * .02) / width) * 1000;
    const endX = ((railRect.left + railRect.width * .5) / width) * 1000;
    const mode = width <= 650 ? 'mobile' : width <= 1000 ? 'tablet' : 'desktop';
    const key = `${mode}:${Math.round(width)}:${Math.round(top)}:${Math.round(height)}:${Math.round(startX)}:${Math.round(endX)}`;

    if (!force && key === routeKey) return true;
    routeKey = key;

    const d = routes[mode](startX, endX);
    [aura, trail, head].forEach(path => {
      path.setAttribute('d', d);
      path.setAttribute('pathLength', '1');
    });
    svg.setAttribute('viewBox', '0 0 1000 1000');
    svg.setAttribute('preserveAspectRatio', 'none');
    svg.style.top = `${rounded(top)}px`;
    svg.style.height = `${rounded(height)}px`;

    startY = top - innerHeight * .7;
    endY = bottom - innerHeight * .36;
    target = clamp((scrollY - startY) / Math.max(1, endY - startY));
    smooth = target;
    lastApplied = -1;
    draw(performance.now(), true);
    return true;
  }

  function requestBake() {
    if (!hasRunner) return;
    clearTimeout(layoutTimer);
    layoutTimer = setTimeout(() => requestAnimationFrame(() => bakeRoute()), 110);
  }

  function decodeImages() {
    const tasks = [...document.images].map(image => {
      if (typeof image.decode === 'function') {
        return image.decode().catch(() => undefined);
      }
      if (image.complete) return Promise.resolve();
      return new Promise(resolve => {
        image.addEventListener('load', resolve, { once: true });
        image.addEventListener('error', resolve, { once: true });
      });
    });
    return Promise.allSettled(tasks);
  }

  function warmLayout() {
    // Один принудительный layout во время загрузочного экрана дешевле серии
    // неожиданных layout/paint во время первого быстрого скролла.
    const selectors = ['#top', '#showcase', '#moduleStage', '#flowSection', '#motionRail', '#authorization'];
    selectors.forEach(selector => document.querySelector(selector)?.getBoundingClientRect());
    document.querySelectorAll('.module-card,.flow-node,.intro-orbit,[data-scroll-reveal]').forEach(node => {
      getComputedStyle(node).transform;
    });
    void document.body.offsetHeight;
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
      // Даже при ошибке отдельного визуального ресурса сайт обязан открыться.
    }

    setBoot(100, 'Готово');
    await wait(110);
    clearTimeout(window.__WESI_BOOT_FAILSAFE__);
    root.classList.remove('is-booting');
    root.classList.add('is-ready');
    window.__WESI_PORTAL_READY__ = true;

    // После fade-out загрузчик остаётся невидимым, но удаляется из дерева,
    // чтобы больше никогда не участвовать в отрисовке.
    setTimeout(() => boot?.remove(), 520);
  }

  if (hasRunner) {
    addEventListener('scroll', updateTarget, { passive: true });
    addEventListener('resize', requestBake, { passive: true });
    addEventListener('orientationchange', requestBake, { passive: true });
    window.visualViewport?.addEventListener('resize', requestBake, { passive: true });
    addEventListener('load', requestBake, { once: true });

    document.addEventListener('visibilitychange', () => {
      if (document.hidden && frame) {
        cancelAnimationFrame(frame);
        frame = 0;
      } else {
        lastFrameTime = 0;
        requestBake();
      }
    });

    if ('ResizeObserver' in window && app) {
      const observer = new ResizeObserver(requestBake);
      observer.observe(app);
    }
  }

  completeBoot();
})();
