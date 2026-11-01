interface MarkdownChannelEnvelope { token: string; message: string; }

export function markdownChannelMessage(message: string, token: string): string | undefined {
  if (!token) return undefined;
  try {
    const envelope = JSON.parse(message) as MarkdownChannelEnvelope;
    return envelope && envelope.token === token && typeof envelope.message === 'string' ? envelope.message : undefined;
  } catch (error) { return undefined; }
}

// 只有顶层受信文档获得 native 凭据；不向任意 frame 注册 JavaScriptProxy。
export const MARKDOWN_CHANNEL_SCRIPT: string = `(() => {
  if (window !== window.top || location.href !== 'https://siyuan-markdown.local/stage/build/markdown/index.html') return;
  let port;
  let token;
  const queued = [];
  const send = message => port.postMessage(JSON.stringify({token, message}));
  const flush = () => {if (port && token) queued.splice(0).forEach(send);};
  const bridge = {postMessage(message) {
    if (typeof message !== 'string') throw new Error('Invalid Markdown message');
    if (port && token) send(message);
    else if (queued.length < 32) queued.push(message);
    else throw new Error('Markdown host unavailable');
  }};
  Object.defineProperty(window, 'siyuanMarkdownNative', {value: bridge, writable: false, configurable: false});
  Object.defineProperty(window, '__siyuanMarkdownConnect', {value(value) {
    if (token || typeof value !== 'string' || !value) return;
    token = value;
    flush();
  }, writable: false, configurable: false});
  const connect = event => {
    if (port || event.data !== 'siyuan-markdown-connect' || event.ports.length !== 1) return;
    port = event.ports[0];
    window.removeEventListener('message', connect);
    flush();
  };
  window.addEventListener('message', connect);
})();`;
