from pathlib import Path

root = Path('server/employee-portal')
index_path = root / 'index.html'
js_path = root / 'app.js'
css_path = root / 'portal-v6.css'

html = index_path.read_text(encoding='utf-8')
js = js_path.read_text(encoding='utf-8')
css = css_path.read_text(encoding='utf-8')

# 1) Явная кнопка закрытия внутри самого popover.
if 'id="requirementsClose"' not in html:
    anchor = '<div class="requirements-popover" id="requirementsPopover" aria-hidden="true">\n            <div class="requirements-title">'
    replacement = '<div class="requirements-popover" id="requirementsPopover" aria-hidden="true">\n            <button class="requirements-close" id="requirementsClose" type="button" aria-label="Закрыть системные требования"><span aria-hidden="true"></span></button>\n            <div class="requirements-title">'
    if anchor not in html:
        raise SystemExit('requirements popover anchor not found')
    html = html.replace(anchor, replacement, 1)
    index_path.write_text(html, encoding='utf-8')

# 2) Крестик + свайп вниз на мобильном.
if "const close = $('#requirementsClose');" not in js:
    anchor = """    const trigger = $('#requirementsTrigger');
    const popover = $('#requirementsPopover');
    if (!trigger || !popover) return;
"""
    replacement = """    const trigger = $('#requirementsTrigger');
    const popover = $('#requirementsPopover');
    const close = $('#requirementsClose');
    if (!trigger || !popover) return;
"""
    if anchor not in js:
        raise SystemExit('requirements bind anchor not found')
    js = js.replace(anchor, replacement, 1)

    anchor2 = """    popover.addEventListener('click', event => event.stopPropagation());
    document.addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', event => { if (event.key === 'Escape') setOpen(false); });
"""
    replacement2 = """    close?.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
      trigger.focus({ preventScroll: true });
    });
    popover.addEventListener('click', event => event.stopPropagation());

    // На телефоне нижний лист можно закрыть привычным свайпом вниз.
    // Срабатываем только если человек начал жест почти у верхней кромки,
    // чтобы обычная прокрутка длинных требований не закрывала окно.
    let touchStartY = null;
    popover.addEventListener('touchstart', event => {
      if (event.touches.length !== 1) return;
      const rect = popover.getBoundingClientRect();
      const y = event.touches[0].clientY;
      touchStartY = y - rect.top <= 90 ? y : null;
    }, { passive: true });
    popover.addEventListener('touchend', event => {
      if (touchStartY == null || event.changedTouches.length !== 1) {
        touchStartY = null;
        return;
      }
      const delta = event.changedTouches[0].clientY - touchStartY;
      touchStartY = null;
      if (delta >= 72) setOpen(false);
    }, { passive: true });

    document.addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', event => { if (event.key === 'Escape') setOpen(false); });
"""
    if anchor2 not in js:
        raise SystemExit('requirements listeners anchor not found')
    js = js.replace(anchor2, replacement2, 1)
    js_path.write_text(js, encoding='utf-8')

# 3) Кнопка всегда видна в правом верхнем углу, даже при прокрутке popover.
if 'REQUIREMENTS_CLOSE_V1' not in css:
    css += '''\n\n/* REQUIREMENTS_CLOSE_V1 */\n.requirements-popover{padding-top:58px}\n.requirements-close{position:sticky;z-index:5;top:-42px;float:right;margin:-42px 0 8px 12px;width:38px;height:38px;border:1px solid var(--soft);border-radius:50%;background:var(--panel);color:var(--t1);cursor:pointer;display:grid;place-items:center;box-shadow:0 10px 28px rgba(var(--shadow-rgb),.25);transition:background .2s var(--ease),border-color .2s var(--ease),transform .2s var(--ease)}\n.requirements-close:hover{border-color:rgba(var(--a3),.55);transform:scale(1.04)}\n.requirements-close:focus-visible{outline:2px solid rgba(var(--a3),.75);outline-offset:2px}\n.requirements-close span,.requirements-close span:after{display:block;width:16px;height:1.8px;border-radius:99px;background:currentColor}\n.requirements-close span{transform:rotate(45deg)}\n.requirements-close span:after{content:\"\";transform:rotate(90deg)}\n@media(max-width:480px){.requirements-popover{padding-top:58px}.requirements-close{top:-42px;margin-top:-42px;width:42px;height:42px}}\n'''
    css_path.write_text(css, encoding='utf-8')

print('requirements close controls applied')
