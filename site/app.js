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
    ? '家庭网络，流量经过代理服务器。' : '公司网络，直接连接互联网。';
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
  motionToggle.setAttribute('aria-label', userPaused ? '播放自动演示' : '暂停自动演示');
  motionToggle.textContent = userPaused ? '播放演示' : '暂停演示';
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
