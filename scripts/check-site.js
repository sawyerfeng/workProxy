// Run in the website's browser context, e.g. agent-browser eval --stdin < scripts/check-site.js.
(() => {
  const assert = (condition, message) => { if (!condition) throw new Error(message); };
  const select = scene => document.querySelector('[data-scene="' + scene + '"]').click();
  const state = () => document.querySelector('#proxy-state').textContent;
  select('office');
  assert(state() === '已关闭', 'Office must disable proxy');
  select('cafe');
  assert(state() === '已关闭', 'Unmatched network must retain disabled state');
  select('home');
  assert(state() === '已开启', 'Home must enable proxy');
  select('cafe');
  assert(state() === '已开启', 'Unmatched network must retain enabled state');
  assert(document.querySelectorAll('[aria-pressed="true"]').length === 1, 'One selected scene');
  select('home');
  assert(document.querySelectorAll('h1').length === 1, 'One main heading');
  assert(document.documentElement.scrollWidth <= innerWidth, 'No horizontal overflow');
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    assert(document.getElementById(link.hash.slice(1)), 'Anchor target exists: ' + link.hash);
  });
  const faq = document.querySelector('details');
  faq.open = true;
  assert(faq.querySelector('p').getBoundingClientRect().height > 0, 'FAQ answer visible');
  faq.open = false;
  return 'PASS: scene transitions, state retention, selection, anchors, FAQ and layout';
})();
