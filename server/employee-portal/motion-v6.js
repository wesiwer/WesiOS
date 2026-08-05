(() => {
  'use strict';

  const svg = document.getElementById('runnerSvg');
  const trail = document.getElementById('runnerTrail');
  const head = document.getElementById('runnerHead');
  const origin = document.getElementById('runnerOrigin');
  const rail = document.getElementById('motionRail');
  const railLine = rail?.querySelector('.rail-line');
  const stage = document.getElementById('moduleStage');
  const core = document.getElementById('orbitCore');
  const flow = document.getElementById('flowSection');
  const board = document.querySelector('.flow-board');

  if (!svg || !trail || !head || !origin || !rail || !railLine || !stage || !core || !flow || !board) return;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  let target = 0;
  let smooth = 0;
  let pathLength = 0;
  let startY = 0;
  let endY = 1;
  let frame = 0;
  let rebuildFrame = 0;
  let lastWidth = 0;
  let lastHeight = 0;

  const clamp = (value, min = 0, max = 1) => Math.max(min, Math.min(max, value));

  function documentPoint(node, x = .5, y = .5) {
    const rect = node.getBoundingClientRect();
    return {
      x: rect.left + scrollX + rect.width * x,
      y: rect.top + scrollY + rect.height * y,
    };
  }

  function catmullRom(points) {
    if (points.length < 2) return '';
    let d = `M ${points[0].x.toFixed(1)} ${points[0].y.toFixed(1)}`;
    for (let i = 0; i < points.length - 1; i += 1) {
      const p0 = points[Math.max(0, i - 1)];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = points[Math.min(points.length - 1, i + 2)];
      const c1x = p1.x + (p2.x - p0.x) / 6;
      const c1y = p1.y + (p2.y - p0.y) / 6;
      const c2x = p2.x - (p3.x - p1.x) / 6;
      const c2y = p2.y - (p3.y - p1.y) / 6;
      d += ` C ${c1x.toFixed(1)} ${c1y.toFixed(1)}, ${c2x.toFixed(1)} ${c2y.toFixed(1)}, ${p2.x.toFixed(1)} ${p2.y.toFixed(1)}`;
    }
    return d;
  }

  function buildPath() {
    rebuildFrame = 0;
    const pageHeight = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, innerHeight);
    const pageWidth = Math.max(document.documentElement.clientWidth, innerWidth);

    if (pageWidth !== lastWidth || pageHeight !== lastHeight) {
      lastWidth = pageWidth;
      lastHeight = pageHeight;
      svg.setAttribute('viewBox', `0 0 ${pageWidth} ${pageHeight}`);
      svg.setAttribute('width', `${pageWidth}`);
      svg.setAttribute('height', `${pageHeight}`);
      svg.style.height = `${pageHeight}px`;
    }

    const o = documentPoint(origin, .02, .5);
    const merge = documentPoint(railLine, .5, .015);
    const points = [
      o,
      { x: o.x + 70, y: o.y + 4 },
      documentPoint(stage, .17, .24),
      documentPoint(core, .48, .18),
      documentPoint(stage, .83, .34),
      documentPoint(stage, .73, .76),
      documentPoint(flow, .77, .24),
      documentPoint(board, .55, .48),
      documentPoint(flow, .22, .76),
      { x: merge.x + Math.min(118, pageWidth * .18), y: merge.y - 210 },
      { x: merge.x + Math.min(42, pageWidth * .08), y: merge.y - 94 },
      { x: merge.x, y: merge.y - 34 },
      merge,
    ];

    const d = catmullRom(points);
    trail.setAttribute('d', d);
    head.setAttribute('d', d);
    pathLength = trail.getTotalLength();
    startY = o.y - innerHeight * .7;
    endY = merge.y - innerHeight * .36;
    updateTarget();
    draw(true);
  }

  function requestBuild() {
    if (rebuildFrame) cancelAnimationFrame(rebuildFrame);
    rebuildFrame = requestAnimationFrame(buildPath);
  }

  function updateTarget() {
    target = clamp((scrollY - startY) / Math.max(1, endY - startY));
    schedule();
  }

  function applyLine(progress) {
    if (!pathLength) return;
    const visible = pathLength * progress;
    const merge = clamp((progress - .82) / .18);
    const mergeEase = merge * merge * (3 - 2 * merge);
    const baseTrailLength = Math.min(150, 72 + innerWidth * .055);
    const baseHeadLength = Math.min(44, 28 + innerWidth * .018);
    const trailLength = Math.max(34, baseTrailLength * (1 - mergeEase * .62));
    const headLength = Math.max(9, baseHeadLength * (1 - mergeEase * .74));
    const trailStart = Math.max(0, visible - trailLength);
    const headStart = Math.max(0, visible - headLength);

    trail.style.strokeDasharray = `${trailLength} ${pathLength + trailLength}`;
    trail.style.strokeDashoffset = `${-trailStart}`;
    head.style.strokeDasharray = `${headLength} ${pathLength + headLength}`;
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
    if (!force) smooth += (target - smooth) * .14;
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
  addEventListener('resize', requestBuild, { passive: true });
  addEventListener('orientationchange', requestBuild, { passive: true });
  addEventListener('load', requestBuild, { once: true });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && frame) {
      cancelAnimationFrame(frame);
      frame = 0;
    } else {
      requestBuild();
    }
  });

  if (document.fonts?.ready) document.fonts.ready.then(requestBuild).catch(() => {});
  if ('ResizeObserver' in window) {
    let resizeTimer = 0;
    const observer = new ResizeObserver(() => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(requestBuild, 120);
    });
    observer.observe(document.getElementById('app') || document.body);
  }

  requestBuild();
})();