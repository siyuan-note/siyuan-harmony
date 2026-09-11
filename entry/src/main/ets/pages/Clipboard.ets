import { util } from "@kit.ArkTS";

export interface ClipboardHTML {
  textHTML: string;
  siyuanHTML: string;
}

export function buildClipboardHTML(html: string, siyuanHTML: string): string {
  if (!siyuanHTML) {
    return html;
  }
  const encoded = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(siyuanHTML));
  return `<!--data-siyuan='${encoded}'-->${html}`;
}

export function parseClipboardHTML(html: string): ClipboardHTML {
  const match = html.match(/<!--data-siyuan='([^']+)'-->/);
  if (match) {
    try {
      const decoded = new util.Base64Helper().decodeSync(match[1]);
      return {
        textHTML: html.replace(/<!--data-siyuan='[^']+'-->/g, ""),
        siyuanHTML: new util.TextDecoder("utf-8", { fatal: true }).decodeWithStream(decoded)
      };
    } catch (e) {
      // 内部数据无法解码时保留原始 HTML，交给普通粘贴流程处理。
      return { textHTML: html, siyuanHTML: "" };
    }
  }
  // 兼容旧剪贴板；无法确定分隔位置时保留原始内容。
  const parts = html.split("__@text/siyuan@__");
  if (parts.length === 2 && parts[0].trimEnd().endsWith(">") && /^\s*<[a-zA-Z][^>]*>/.test(parts[1])) {
    return { textHTML: parts[0], siyuanHTML: parts[1] };
  }
  return { textHTML: html, siyuanHTML: "" };
}
