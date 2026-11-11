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
let userPaused = false;
let diagramVisible = false;
function updateMotion() {
  if (userPaused || !diagramVisible || document.hidden || motionPreference.matches) {
    diagram.pauseAnimations();
  } else {
    diagram.unpauseAnimations();
  }
}
document.querySelectorAll('button[data-route]').forEach(button => {
  button.addEventListener('click', () => {
    const throughProxy = button.dataset.route === 'proxy';
    panel.dataset.route = button.dataset.route;
    document.querySelectorAll('button[data-route]').forEach(item => {
      item.setAttribute('aria-pressed', String(item === button));
    });
    document.querySelector('#journey-label').textContent = throughProxy ? '家庭网络' : '公司网络';
    document.querySelector('#journey-state').textContent = throughProxy ? '经过代理' : '直接连接';
    document.querySelector('#journey-detail').textContent = throughProxy
      ? '家庭网络，流量经过代理服务器。' : '公司网络，直接连接互联网。';
  });
});
motionToggle.addEventListener('click', () => {
  userPaused = !userPaused;
  motionToggle.setAttribute('aria-pressed', String(userPaused));
  motionToggle.setAttribute('aria-label', userPaused ? '播放线路动画' : '暂停线路动画');
  motionToggle.textContent = userPaused ? '播放动画' : '暂停动画';
  updateMotion();
});
new IntersectionObserver(entries => {
  diagramVisible = entries[0].isIntersecting;
  updateMotion();
}, { threshold: 0.1 }).observe(diagram);
document.addEventListener('visibilitychange', updateMotion);
motionPreference.addEventListener('change', updateMotion);
updateMotion();
