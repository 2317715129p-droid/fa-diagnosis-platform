// =============================================================
// FA 前端排错 snippet —— 粘贴到报错页面的 浏览器 DevTools Console 运行
// (按 F12 -> Console, 粘贴回车即可)
// 它会打印: 当前页面地址 / 实际 API 地址 / 实际 WS 地址 / 一次真实请求结果 / 任何崩溃错误
// 把输出截图或复制发我。
// =============================================================
(async () => {
  const out = (...a) => console.log('%c[FA-DIAG]', 'color:#0a0;font-weight:bold', ...a);
  out('当前页面地址 window.location.href =', window.location.href);
  out('当前 host =', window.location.host, '| protocol =', window.location.protocol);

  // 复刻 constants.js 的逻辑, 看前端"以为"自己该请求哪个地址
  const host = window.location.hostname;
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}`;
  const httpUrl = wsUrl.replace(/^ws/, 'http');
  out('前端将请求的 API 基址 (httpUrl) =', httpUrl);
  out('前端将请求的 WS 地址  =', wsUrl + '/ws/diagnose');

  // 抓全局错误 (React 渲染崩溃会冒泡到这里)
  window.onerror = (msg, src, line, col, err) => {
    out('!! window.onerror 捕获到渲染错误:', msg, '|', err && err.stack);
  };
  window.addEventListener('unhandledrejection', (e) => {
    out('!! 未处理的 Promise 拒绝:', e.reason && (e.reason.stack || e.reason));
  });

  // 真实打一次 API, 看后端到底通不通 / 返回什么
  try {
    out('正在请求:', httpUrl + '/api/assets');
    const r = await fetch(httpUrl + '/api/assets', { credentials: 'include' });
    const t = await r.text();
    out('API 响应 HTTP', r.status, '| 前 300 字符:', t.slice(0, 300));
  } catch (e) {
    out('!! fetch /api/assets 失败 (这就是组件崩溃的根因之一):', e.message);
  }

  // 探测 WebSocket 能否连上
  try {
    const ws = new WebSocket(wsUrl + '/ws/diagnose');
    ws.onopen = () => { out('WS 连接成功 ✓'); ws.close(); };
    ws.onerror = (e) => out('!! WS 连接错误 (浏览器通常只报 error, 无细节)');
    ws.onclose = (e) => out('WS 关闭 code=', e.code, 'wasClean=', e.wasClean);
    setTimeout(() => out('(WS 探测 3s 内无 open/error 说明被防火墙或代理挡住)'), 3000);
  } catch (e) {
    out('!! 创建 WS 失败:', e.message);
  }
})();
