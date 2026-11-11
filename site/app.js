const names = { office: 'Office Ethernet', home: 'Home Wi-Fi', cafe: 'Café Wi-Fi' };
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
    const badge = document.querySelector('#state-badge');
    badge.textContent = proxyEnabled ? 'ON' : 'OFF';
    badge.classList.toggle('off', !proxyEnabled);
    document.querySelector('#demo-result').textContent = scene === 'cafe'
      ? '没有匹配规则，保持此前的代理状态。'
      : scene === 'home' ? '已匹配家庭网络规则，开启系统代理。' : '已匹配公司网络规则，关闭系统代理。';
  });
});
