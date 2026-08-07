from pathlib import Path

path = Path('server/pb_hooks/employee_portal_static.pb.js')
text = path.read_text(encoding='utf-8')

css_anchor = ".requirements-proof{margin:14px 0 0;color:var(--t3);font-size:10px;line-height:1.65}.requirements-proof code{color:var(--t1);font-family:ui-monospace,SFMono-Regular,Consolas,monospace}.download-button[data-progress]:after{content:attr(data-progress);margin-left:8px;font-variant-numeric:tabular-nums;opacity:.75}"
css_replacement = ".requirements-proof{margin:14px 0 0;color:var(--t3);font-size:10px;line-height:1.65}.requirements-proof code{color:var(--t1);font-family:ui-monospace,SFMono-Regular,Consolas,monospace}.hero-extras{position:relative}.requirements-trigger{cursor:pointer;user-select:none}.requirements-trigger i{transition:transform .24s var(--ease)}.requirements-trigger[aria-expanded=\"true\"] i{transform:rotate(180deg)}.requirements-popover{position:absolute;z-index:30;right:0;bottom:58px;width:min(860px,calc(100vw - 42px));max-height:min(72vh,650px);margin:0!important;padding:22px;border:1px solid var(--line);border-radius:22px;background:linear-gradient(155deg,var(--panel-u),var(--sunken));box-shadow:0 30px 90px rgba(var(--shadow-rgb),.62),inset 0 1px rgba(var(--veil-rgb),.04);overflow:auto;overscroll-behavior:contain;opacity:0;visibility:hidden;pointer-events:none;transform:translateY(12px) scale(.985);transform-origin:100% 100%;transition:opacity .2s var(--ease),transform .2s var(--ease),visibility .2s}.requirements-popover.is-open{opacity:1;visibility:visible;pointer-events:auto;transform:translateY(0) scale(1)}.requirements-popover .requirements-title{grid-template-columns:1fr 1fr}.requirements-popover .requirements-title h3{font-size:clamp(24px,3vw,36px)}.requirements-popover .requirements-grid{margin-top:18px}.requirements-popover .req-card{box-shadow:none}.download-button[data-progress]:after{content:attr(data-progress);margin-left:8px;font-variant-numeric:tabular-nums;opacity:.75}"
if css_anchor not in text:
    raise SystemExit('CSS anchor not found')
text = text.replace(css_anchor, css_replacement, 1)

mobile_anchor = "@media(max-width:480px){.req-card,.product-fact{padding:18px}.req-cols dl{grid-template-columns:1fr}.req-cols dd{text-align:left;margin-bottom:4px}}"
mobile_replacement = "@media(max-width:480px){.req-card,.product-fact{padding:18px}.req-cols dl{grid-template-columns:1fr}.req-cols dd{text-align:left;margin-bottom:4px}.requirements-popover{position:fixed;left:12px;right:12px;bottom:max(18px,env(safe-area-inset-bottom));width:auto;max-height:78vh;padding:18px;transform-origin:50% 100%}.requirements-popover .requirements-title{grid-template-columns:1fr}.requirements-popover .requirements-title .section-label{grid-column:auto}.requirements-popover .requirements-title>p{font-size:11px}}"
if mobile_anchor not in text:
    raise SystemExit('mobile anchor not found')
text = text.replace(mobile_anchor, mobile_replacement, 1)

js_anchor = "showcase.parentNode.insertBefore(section,showcase);var hint=document.querySelector('.scroll-hint');if(hint)hint.setAttribute('href','#productInfo');"
js_replacement = """showcase.parentNode.insertBefore(section,showcase);
 var hint=document.querySelector('.scroll-hint'),requirements=section.querySelector('.requirements');
 if(hint&&requirements&&hint.parentNode){
  requirements.id='requirementsPopover';requirements.classList.add('requirements-popover');requirements.setAttribute('aria-hidden','true');hint.parentNode.insertBefore(requirements,hint);
  hint.removeAttribute('href');hint.classList.add('requirements-trigger');hint.setAttribute('role','button');hint.setAttribute('tabindex','0');hint.setAttribute('aria-controls','requirementsPopover');hint.setAttribute('aria-expanded','false');
  var label=hint.querySelector('span');if(label)label.textContent='Системные требования';
  function setRequirementsOpen(open){hint.setAttribute('aria-expanded',open?'true':'false');requirements.setAttribute('aria-hidden',open?'false':'true');requirements.classList.toggle('is-open',open);}
  function toggleRequirements(event){if(event){event.preventDefault();event.stopPropagation();}setRequirementsOpen(hint.getAttribute('aria-expanded')!=='true');}
  hint.addEventListener('click',toggleRequirements);
  hint.addEventListener('keydown',function(event){if(event.key==='Enter'||event.key===' '){toggleRequirements(event);}else if(event.key==='Escape'){setRequirementsOpen(false);}});
  requirements.addEventListener('click',function(event){event.stopPropagation();});
  document.addEventListener('click',function(){setRequirementsOpen(false);});
  document.addEventListener('keydown',function(event){if(event.key==='Escape')setRequirementsOpen(false);});
 }
"""
if js_anchor not in text:
    raise SystemExit('JS anchor not found')
text = text.replace(js_anchor, js_replacement, 1)

path.write_text(text, encoding='utf-8')
print('portal requirements menu patch applied')
