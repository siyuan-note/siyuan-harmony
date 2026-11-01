import { AbilityStage, Want } from '@kit.AbilityKit';

export function markdownInstanceKey(want: Want): string {
  const key = want.parameters?.markdownInstanceKey;
  return typeof key === 'string' && key.length ? key : want.uri || 'blank';
}

// specified 模式在 API 18 起可按键复用指定容器，不依赖新版本的前置自身接口。
export default class MarkdownStage extends AbilityStage {
  onAcceptWant(want: Want): string { return markdownInstanceKey(want); }
}
