(() => {
  'use strict';
  const svg = document.getElementById('runnerSvg');
  const trail = document.getElementById('runnerTrail');
  const head = document.getElementById('runnerHead');
  const origin = document.getElementById('runnerOrigin');
  if (!svg || !trail || !head || !origin || matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const $ = (id) => document.getElementById(id);
  let target = 0;
  let smooth = 0;
  let pathLength = 0;
  let lastPathKey = '';

  function clamp(value, min = 0, max = 1) {
    return Math.max(min, Math.min(max, value));
  }

  function point(node, x = .5, y = .5) {
    const r = node.getBoundingClientRect();
    return { x: r.left + r.width * x, y: r.top + r.height * y };
  }

  function catmullRom(points) {
    if (points.length < 2) return '';
    let d = `M ${points[0].x.toFixed(1)} ${points[0].y.toFixed(1)}`;
    for (let i = 0; i < points.length - 1; i++) {
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
    const stage = $('moduleStage');
    const core = $('orbitCore');
    const flow = $('flowSection');
    const board = document.querySelector('.flow-board');
    const rail = $('motionRail');
    const railLine = rail?.querySelector('.rail-line');
    if (!stage || !core || !flow || !board || !rail || !railLine) return;

    const o = point(origin, .02, .5);
    const merge = point(railLine, .5, .015);
    const points = [
      o,
      { x: o.x + 70, y: o.y + 4 },
      point(stage, .17, .24),
      point(core, .48, .18),
      point(stage, .83, .34),
      point(stage, .73, .76),
      point(flow, .77, .24),
      point(board, .55, .48),
      point(flow, .22, .76),
      { x: merge.x + 118, y: merge.y - 210 },
      { x: merge.x + 42, y: merge.y - 94 },
      { x: merge.x, y: merge.y - 34 },
      merge,
    ];

    const key = points.map(p => `${Math.round(p.x)},${Math.round(p.y)}`).join('|');
    if (key === lastPathKey) return;
    lastPathKey = key;
    const d = catmullRom(points);
    trail.setAttribute('d', d);
    head.setAttribute('d', d);
    pathLength = trail.getTotalLength();
  }

  function updateTarget() {
    const rail = $('motionRail');
    const railLine = rail?.querySelector('.rail-line');
    if (!rail || !railLine) return;
    const start = origin.getBoundingClientRect().top + scrollY - innerHeight * .7;
    const end = railLine.getBoundingClientRect().top + scrollY - innerHeight * .36;
    target = clamp((scrollY - start) / Math.max(1, end - start));
  }

  function render() {
    buildPath();
    smooth += (target - smooth) * .075;

    const railLine = document.querySelector('#motionRail .rail-line');
    if (pathLength > 0) {
      const visible = pathLength * smooth;
      const merge = clamp((smooth - .82) / .18);
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
      trail.style.opacity = `${.32 * (1 - mergeEase)}`;
      head.style.opacity = `${1 - mergeEase}`;
      svg.classList.toggle('active', smooth > .002 && smooth < .9995);

      // Один и тот же путь проходит за карточками, а в финале точно входит
      // в вертикальную ось шагов 01–02–03 и растворяется в ней.
      svg.style.zIndex = smooth > .13 && smooth < .48 ? '3' : '8';
      if (railLine) {
        const pulse = Math.sin(mergeEase * Math.PI);
        railLine.style.setProperty('--runner-merge', pulse.toFixed(3));
        railLine.classList.toggle('runner-merge-active', merge > .01 && merge < .995);
      }
    }
    requestAnimationFrame(render);
  }

  addEventListener('scroll', updateTarget, { passive: true });
  addEventListener('resize', () => { lastPathKey = ''; updateTarget(); }, { passive: true });
  updateTarget();
  requestAnimationFrame(render);
})();
