import kernel from 'libentry.so';
import { MarkdownPreferences, MarkdownFonts, MarkdownAppearanceSources, MarkdownIndependentAppearance, MARKDOWN_ORIGIN } from './MarkdownTypes';
export interface MarkdownWorkspace { id: string; name: string; }
export interface MarkdownCustomFont { family: string; weight: number; url: string; }
export interface MarkdownAppearanceValue {
  theme: string; fontSize: number; fonts: MarkdownFonts; sources: MarkdownAppearanceSources;
  independent: MarkdownIndependentAppearance; workspaces: MarkdownWorkspace[]; customFonts: MarkdownCustomFont[];
}
export interface MarkdownAppearanceResult { preferences: MarkdownPreferences; appearance: MarkdownAppearanceValue; }

export class MarkdownAppearance {
  private handle: string;
  private closed: boolean = false;
  private generation: number = 0;
  private grantEpoch: number = 0;
  private resolving: boolean = false;
  private tokens: Set<string> = new Set();
  private prefix: string;
  constructor(root: string, containerId: string) {
    this.prefix = MARKDOWN_ORIGIN + '/appearance-font/' + containerId + '/';
    this.handle = kernel.newMarkdownAppearance(root + '/home/.config/siyuan/markdown', root);
  }
  available(): boolean { return !this.closed && this.handle.length > 0; }
  async resolve(preferences: MarkdownPreferences, patch?: Object): Promise<MarkdownAppearanceResult> {
    if (!this.available()) throw new Error('Workspace appearance unavailable');
    const generation = ++this.generation;
    this.resolving = true;
    this.grantEpoch++;
    this.tokens.clear();
    try {
      const raw = await kernel.resolveMarkdownAppearance(this.handle, JSON.stringify(preferences), patch ? JSON.stringify(patch) : '');
      if (this.closed || generation !== this.generation) throw new Error('Workspace appearance closed');
      const result = JSON.parse(raw) as MarkdownAppearanceResult;
      const tokens: Set<string> = new Set();
      result.appearance.customFonts.forEach((font: MarkdownCustomFont) => {
        const match = new RegExp('^/appearance-font/([a-f0-9]{48})$').exec(font.url);
        if (!match) throw new Error('Invalid appearance font');
        tokens.add(match[1]);
        font.url = this.prefix + match[1];
      });
      this.grantEpoch++;
      this.tokens = tokens;
      return result;
    } finally {
      if (generation === this.generation) this.resolving = false;
    }
  }
  owns(url: string): boolean { return url.startsWith(this.prefix); }
  async read(url: string): Promise<Uint8Array | undefined> {
    if (!this.available() || this.resolving || !this.owns(url)) return undefined;
    const token = url.slice(this.prefix.length);
    if (!new RegExp('^[a-f0-9]{48}$').test(token) || !this.tokens.has(token)) return undefined;
    const grantEpoch = this.grantEpoch;
    try {
      const bytes = await kernel.readMarkdownAppearanceFont(this.handle, token);
      return !this.closed && !this.resolving && grantEpoch === this.grantEpoch && this.tokens.has(token) ? new Uint8Array(bytes) : undefined;
    } catch (error) { return undefined; }
  }
  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.generation++;
    this.grantEpoch++;
    this.tokens.clear();
    const handle = this.handle;
    this.handle = '';
    if (handle) kernel.closeMarkdownAppearance(handle);
  }
}
