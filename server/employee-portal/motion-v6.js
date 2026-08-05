(() => {
  'use strict';

  /* Карточки получают готовые CSS-траектории до запуска основного motion-кода. */
  document.querySelectorAll('[data-float]').forEach((node, index) => {
    node.removeAttribute('data-float');
    node.classList.add('baked-float', `baked-float-${index + 1}`);
  });

  const svg = document.getElementById('runnerSvg');
  const trail = document.getElementById('runnerTrail');
  const head = document.getElementById('runnerHead');
  const origin = document.getElementById('runnerOrigin');
  const railLine = document.querySelector('#motionRail .rail-line');

  if (!svg || !trail || !head || !origin || !railLine) return;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  let target = 0;
  let smooth = 0;
  let startY = 0;
  let endY = 1;
  let frame = 0;
  let layoutTimer = 0;
  let routeKey = '';

  const clamp = (value, min = 0, max = 1) => Math.max(min, Math.min(max, value));
  const n = value => Math.round(value * 10) / 10;

  /*
   * Маршруты заранее подготовлены в нормализованной системе 1000×1000.
   * Во время прокрутки геометрия не рассчитывается: меняется только положение
   * короткого dash-сегмента по уже готовому SVG path.
   */
  function mobileRoute(startX, endX) {
    return [
      `M ${n(startX)} 0`,
      `C ${n(startX + 86)} 18, 224 72, 214 142`,
      'C 202 236, 872 178, 836 310',
      'C 803 431, 128 382, 169 512',
      'C 209 641, 854 586, 758 725',
      `C 660 865, ${n(endX + 174)} 846, ${n(endX + 72)} 940`,
      `C ${n(endX + 27)} 980, ${n(endX + 8)} 993, ${n(endX)} 1000`,
    ].join(' ');
  }

  function tabletRoute(startX, endX) {
    return [
      `M ${n(startX)} 0`,
      `C ${n(startX + 110)} 20, 296 76, 284 150`,
      'C 270 245, 826 193, 812 314',
      'C 797 438, 206 404, 234 520',
      'C 264 646, 808 598, 738 726',
      `C 665 861, ${n(endX + 196)} 850, ${n(endX + 82)} 943`,
      `C ${n(endX + 31)} 983, ${n(endX + 9)} 994, ${n(endX)} 1000`,
    ].join(' ');
  }

  function desktopRoute(startX, endX) {
    return [
      `M ${n(startX)} 0`,
      `C ${n(startX + 135)} 22, 356 64, 350 148`,
      'C 344 243, 790 205, 804 316',
      'C 820 440, 236 408, 267 525',
      'C 302 657, 778 606, 718 731',
      `C 654 865, ${n(endX + 215)} 856, ${n(endX + 91)} 945`,
      `C ${n(endX + 34)} 984, ${n(endX + 10)} 995, ${n(endX)} 1000`,
    ].join(' ');
  }

  function chooseRoute(width, startX, endX) {
    if (width <= 650) return mobileRoute(startX, endX);
    if (width <= 1000) return tabletRoute(startX, endX);
    return desktopRoute(startX, endX);
  }

  function bakeRoute() {
    const width = Math.max(document.documentElement.clientWidth, innerWidth, 1);
    const originRect = origin.getBoundingClientRect();
    const railRect = railLine.getBoundingClientRect();
    const routeTop = originRect.top + scrollY + originRect.height * .5;
    const routeBottom = railRect.top + scrollY + Math.min(3, railRect.height * .02);
    const routeHeight = Math.max(720, routeBottom - routeTop);
    const startX = ((originRect.left + originRect.width * .02) / width) * 1000;
    const endX = ((railRect.left + railRect.width * .5) / width) * 1000;
    const breakpoint = width <= 650 ? 'm' : width <= 1000 ? 't' : 'd';
    const nextKey = `${breakpoint}:${Math.round(width)}:${Math.round(routeTop)}:${Math.round(routeHeight)}:${Math.round(startX)}:${Math.round(endX)}`;

    if (nextKey === routeKey) return;
    routeKey = nextKey;

    const d = chooseRoute(width, startX, endX);
    trail.setAttribute('d', d);
    head.setAttribute('d', d);
    trail.setAttribute('pathLength', '1');
    head.setAttribute('pathLength', '1');
    svg.setAttribute('viewBox', '0 0 1000 1000');
    svg.setAttribute('preserveAspectRatio', 'none');
    svg.style.top = `${n(routeTop)}px`;
    svg.style.height = `${n(routeHeight)}px`;

    startY = routeTop - innerHeight * .7;
    endY = routeBottom - innerHeight * .36;
    updateTarget();
    draw(true);
  }

  function requestBake() {
    clearTimeout(layoutTimer);
    layoutTimer = setTimeout(() => requestAnimationFrame(bakeRoute), 90);
  }

  function updateTarget() {
    target = clamp((scrollY - startY) / Math.max(1, endY - startY));
    schedule();
  }

  function applyLine(progress) {
    const merge = clamp((progress - .82) / .18);
    const mergeEase = merge * merge * (3 - 2 * merge);
    const trailLength = Math.max(.028, .085 * (1 - mergeEase * .67));
    const headLength = Math.max(.009, .027 * (1 - mergeEase * .72));
    const trailStart = Math.max(0, progress - trailLength);
    const headStart = Math.max(0, progress - headLength);

    trail.style.strokeDasharray = `${trailLength} ${1 + trailLength}`;
    trail.style.strokeDashoffset = `${-trailStart}`;
    head.style.strokeDasharray = `${headLength} ${1 + headLength}`;
    head.style.strokeDashoffset = `${-headStart}`;
    trail.style.opacity = `${.34 * (1 - mergeEase)}`;
    head.style.opacity = `${1 - mergeEase}`;
    svg.classList.toggle('active', progress > .002 && progress < .9995);
    svg.style.zIndex = progress > .13 && progress < .48 ? '3' : '8';

    const pulse = Math.sin(mergeEase * Math.PI);
    railLine.style.setProperty('--runner-merge', pulse.toFixed(3));
    railLine.classList.toggle('runner-merge-active', merge > .01 && merge < .995);
  }

  function draw(force = false) {
    if (!force) smooth += (target - smooth) * .16;
    if (Math.abs(target - smooth) < .0007) smooth = target;
    applyLine(smooth);
  }

  function render() {
    frame = 0;
    draw();
    if (Math.abs(target - smooth) > .0007 && !document.hidden) schedule();
  }

  function schedule() {
    if (!frame && !document.hidden) frame = requestAnimationFrame(render);
  }

  addEventListener('scroll', updateTarget, { passive: true });
  addEventListener('resize', requestBake, { passive: true });
  addEventListener('orientationchange', requestBake, { passive: true });
  addEventListener('load', requestBake, { once: true });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && frame) {
      cancelAnimationFrame(frame);
      frame = 0;
    } else {
      requestBake();
    }
  });

  if (document.fonts?.ready) document.fonts.ready.then(requestBake).catch(() => {});
  requestBake();
})();