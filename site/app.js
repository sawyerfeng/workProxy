const names = { office: '公司有线网络', home: '家庭 Wi-Fi', cafe: '咖啡馆 Wi-Fi' };
let proxyEnabled = true;
document.querySelectorAll('[data-scene]').forEach(button => {
  button.addEventListener('click', () => {
    const scene = button.dataset.scene;
    if (scene !== 'cafe') proxyEnabled = scene === 'home';
    document.querySelectorAll('[data-scene]').forEach(item => {
      item.setAttribute('aria-pressed', String(item === button));
    });
    document.querySelectorAll('[data-rule]').forEach(item => {
      item.classList.toggle('active', item.dataset.rule === scene);
    });
    document.querySelector('#network-name').textContent = names[scene];
    document.querySelector('#proxy-state').textContent = proxyEnabled ? '已开启' : '已关闭';
    document.querySelector('#demo-result').textContent = scene === 'cafe'
      ? '没有匹配规则，保持此前的代理状态。'
      : scene === 'home' ? '已匹配家庭网络规则，开启系统代理。' : '已匹配公司网络规则，关闭系统代理。';
  });
});

// Scroll illustrates the sequence; buttons remain available without motion or on small screens.
const journey = document.querySelector('.journey');
const panel = document.querySelector('.journey-panel');
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
const narrowScreen = matchMedia('(max-width: 700px)');
const phases = [
  ['公司网络', '关闭系统代理', '命中公司规则，保持直连。'],
  ['正在连接家庭网络', '等待网络稳定', '网络稳定 3 秒后，再匹配规则。'],
  ['家庭网络', '开启系统代理', '命中家庭规则，开启代理。']
];
let currentPhase = -1;
function renderJourney(progress) {
  const phase = progress < 0.33 ? 0 : progress < 0.67 ? 1 : 2;
  panel.style.setProperty('--progress', progress);
  panel.style.setProperty('--incoming', Math.min(1, Math.max(0, (progress - 0.33) / 0.2)));
  panel.style.setProperty('--outgoing', Math.min(1, Math.max(0, (progress - 0.67) / 0.25)));
  if (phase === currentPhase) return;
  currentPhase = phase;
  panel.dataset.stage = String(phase);
  document.querySelector('#journey-label').textContent = phases[phase][0];
  document.querySelector('#journey-state').textContent = phases[phase][1];
  document.querySelector('#journey-detail').textContent = phases[phase][2];
  document.querySelectorAll('[data-phase]').forEach(button => {
    button.setAttribute('aria-pressed', String(Number(button.dataset.phase) === phase));
  });
}
document.querySelectorAll('[data-phase]').forEach(button => {
  button.addEventListener('click', () => renderJourney([0, 0.55, 1][Number(button.dataset.phase)]));
});
let scrollFrame = 0;
function updateJourneyOnScroll() {
  if (scrollFrame || motionPreference.matches || narrowScreen.matches) return;
  scrollFrame = requestAnimationFrame(() => {
    scrollFrame = 0;
    const bounds = journey.getBoundingClientRect();
    if (bounds.bottom <= 0 || bounds.top >= innerHeight) return;
    const distance = journey.offsetHeight - document.querySelector('.journey-sticky').offsetHeight;
    renderJourney(Math.min(1, Math.max(0, (innerHeight * 0.08 - bounds.top) / Math.max(1, distance))));
  });
}
addEventListener('scroll', updateJourneyOnScroll, { passive: true });
addEventListener('resize', updateJourneyOnScroll);
motionPreference.addEventListener('change', updateJourneyOnScroll);
renderJourney(0);
updateJourneyOnScroll();
