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
