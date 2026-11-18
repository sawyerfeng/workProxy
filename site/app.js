const names = { office: '公司有线网络', home: '家庭 Wi-Fi', cafe: '咖啡馆 Wi-Fi' };
let proxyEnabled = true;
let automatic = true;
let currentScene = 'home';
const sceneButtons = [...document.querySelectorAll('[data-scene]')];
const proxyButtons = [...document.querySelectorAll('[data-proxy]')];
const ruleRows = [...document.querySelectorAll('[data-rule]')];
const autoButton = document.querySelector('#demo-auto');
const searchButton = document.querySelector('#demo-search-toggle');
const searchInput = document.querySelector('#demo-search');

let switchedToUnmatched = false;
function renderDemo() {
  sceneButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.scene === currentScene)));
  proxyButtons.forEach(button => button.setAttribute('aria-pressed', String((button.dataset.proxy === 'on') === proxyEnabled)));
  ruleRows.forEach(row => row.classList.toggle('active', automatic && row.dataset.rule === currentScene));
  document.querySelector('#network-name').textContent = names[currentScene];
  document.querySelector('#proxy-state').textContent = proxyEnabled ? '代理已开启' : '代理已关闭';
  autoButton.setAttribute('aria-pressed', String(automatic));
  autoButton.textContent = automatic ? '自动切换' : '恢复自动';
  document.querySelector('#demo-result').textContent = !automatic
    ? '手动模式：自动切换已暂停，保持当前代理状态。'
    : currentScene === 'cafe'
      ? (switchedToUnmatched ? '未命中任何规则，切换网络后默认关闭代理。' : '当前网络没有匹配规则，恢复自动后保持现有状态。')
      : currentScene === 'home' ? '已命中“家庭 Wi-Fi”规则，自动开启系统代理。' : '已命中“公司网络”规则，自动关闭系统代理。';
}

sceneButtons.forEach(button => button.addEventListener('click', () => {
  currentScene = button.dataset.scene;
  if (automatic) {
    proxyEnabled = currentScene === 'home';
    switchedToUnmatched = currentScene === 'cafe';
  }
  renderDemo();
}));
proxyButtons.forEach(button => button.addEventListener('click', () => {
  proxyEnabled = button.dataset.proxy === 'on';
  automatic = false;
  switchedToUnmatched = false;
  renderDemo();
}));
autoButton.addEventListener('click', () => {
  automatic = !automatic;
  switchedToUnmatched = false;
  if (automatic && currentScene !== 'cafe') proxyEnabled = currentScene === 'home';
  renderDemo();
});
function filterDemoRules() {
  const query = searchInput.value.trim().toLocaleLowerCase();
  ruleRows.forEach(row => { row.hidden = !row.textContent.toLocaleLowerCase().includes(query); });
  document.querySelector('#demo-no-results').hidden = ruleRows.some(row => !row.hidden);
}
function closeDemoSearch() {
  searchInput.hidden = true;
  searchInput.value = '';
  searchButton.setAttribute('aria-expanded', 'false');
  filterDemoRules();
  searchButton.focus();
}
searchButton.addEventListener('click', () => {
  if (!searchInput.hidden) { closeDemoSearch(); return; }
  searchInput.hidden = false;
  searchButton.setAttribute('aria-expanded', 'true');
  searchInput.focus();
});
searchInput.addEventListener('input', filterDemoRules);
searchInput.addEventListener('keydown', event => {
  if (event.key === 'Escape') closeDemoSearch();
});
renderDemo();

const panel = document.querySelector('.journey-panel');
const diagram = document.querySelector('.route-diagram');
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
const motionToggle = document.querySelector('.motion-toggle');
const routeButtons = [...document.querySelectorAll('button[data-route]')];
const activePath = document.querySelector('.active-route');
const glowPath = document.querySelector('.active-glow');
const packets = [...document.querySelectorAll('.flow-packet')];
const lever = document.querySelector('.switch-lever');
let userPaused = false;
let diagramVisible = false;
let target = 0;
let position = 0;
let travel = 0;
let elapsed = 0;
let lastFrame = 0;
let frame = 0;

function drawRoute() {
  const y = 90 + 200 * position;
  const path = 'M150 190C260 190 250 ' + y + ' 350 ' + y +
    'H550C650 ' + y + ' 640 190 750 190';
  activePath.setAttribute('d', path);
  glowPath.setAttribute('d', path);
  lever.setAttribute('transform', 'rotate(' + (-25 + position * 50) + ' 205 190)');
  const length = activePath.getTotalLength();
  packets.forEach((packet, index) => {
    const point = activePath.getPointAtLength(((travel + index / packets.length) % 1) * length);
    packet.setAttribute('cx', point.x);
    packet.setAttribute('cy', point.y);
  });
}

function selectRoute(route) {
  const throughProxy = route === 'proxy';
  target = throughProxy ? 1 : 0;
  elapsed = 0;
  panel.dataset.route = route;
  document.querySelector('.journey-controls').dataset.route = route;
  routeButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.route === route)));
  document.querySelector('#journey-label').textContent = throughProxy ? '家庭网络' : '公司网络';
  document.querySelector('#journey-state').textContent = throughProxy ? '经过代理' : '直接连接';
  document.querySelector('#journey-detail').textContent = throughProxy
    ? '回到家庭网络后自动开启系统代理，流量经由本地代理转发。' : '连上公司网络后自动关闭系统代理，流量直接访问互联网。';
  if (userPaused || motionPreference.matches || !diagramVisible) {
    position = target;
    drawRoute();
  }
}

function animate(time) {
  const dt = Math.min((time - lastFrame) / 1000, 0.05);
  lastFrame = time;
  if (!routeButtons.includes(document.activeElement)) elapsed += dt;
  if (elapsed >= 4.5) selectRoute(target ? 'direct' : 'proxy');
  position += (target - position) * (1 - Math.exp(-dt * 5));
  if (Math.abs(target - position) < 0.001) position = target;
  travel = (travel + dt / 3.5) % 1;
  drawRoute();
  frame = requestAnimationFrame(animate);
}

function updateMotion() {
  cancelAnimationFrame(frame);
  frame = 0;
  const paused = userPaused || !diagramVisible || document.hidden || motionPreference.matches;
  panel.dataset.motion = paused ? 'paused' : 'playing';
  if (motionPreference.matches) {
    position = target;
    drawRoute();
  }
  if (!paused) {
    lastFrame = performance.now();
    frame = requestAnimationFrame(animate);
  }
}
routeButtons.forEach(button => button.addEventListener('click', () => selectRoute(button.dataset.route)));
motionToggle.addEventListener('click', () => {
  userPaused = !userPaused;
  motionToggle.setAttribute('aria-pressed', String(userPaused));
  motionToggle.setAttribute('aria-label', userPaused ? '继续自动演示' : '暂停自动演示');
  motionToggle.textContent = userPaused ? '继续演示' : '暂停演示';
  if (userPaused) {
    position = target;
    drawRoute();
  }
  updateMotion();
});
new IntersectionObserver(entries => {
  diagramVisible = entries[0].isIntersecting;
  updateMotion();
}, { threshold: 0.1 }).observe(diagram);
document.addEventListener('visibilitychange', updateMotion);
motionPreference.addEventListener('change', updateMotion);
selectRoute('direct');
updateMotion();
