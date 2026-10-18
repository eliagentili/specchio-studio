'use strict';
document.documentElement.classList.remove('no-js');
// Progressive enhancement only. No requests, persistence, analytics or tracking.
const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
function selectTab(tab, focus = false) {
  tabs.forEach(item => {
    const active = item === tab;
    item.setAttribute('aria-selected', String(active));
    item.tabIndex = active ? 0 : -1;
    const panel = document.getElementById(item.getAttribute('aria-controls'));
    if (panel) panel.hidden = !active;
  });
  if (focus) tab.focus();
}
tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    let target;
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') target = tabs[(index + 1) % tabs.length];
    if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') target = tabs[(index + tabs.length - 1) % tabs.length];
    if (event.key === 'Home') target = tabs[0];
    if (event.key === 'End') target = tabs[tabs.length - 1];
    if (target) { event.preventDefault(); selectTab(target, true); }
  });
});
const toggle = document.querySelector('.mask-toggle');
if (toggle) {
  toggle.addEventListener('click', () => {
    const shown = toggle.getAttribute('aria-pressed') !== 'true';
    toggle.setAttribute('aria-pressed', String(shown));
    document.querySelector('.mask-placeholder').hidden = shown;
    document.querySelector('.example-email').hidden = !shown;
    toggle.replaceChildren(document.createTextNode(shown ? toggle.dataset.hide : toggle.dataset.show));
    const arrow = document.createElement('span');
    arrow.setAttribute('aria-hidden', 'true'); arrow.textContent = ' ↗';
    toggle.append(arrow);
  });
}
// All workflow copy remains accessible when scripting is unavailable.
