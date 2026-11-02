import { MarkdownPreferences } from './MarkdownTypes';

export function markdownThemeDark(preference: string, systemDark: boolean): boolean {
  return preference === 'dark' || preference === 'system' && systemDark;
}

export function markdownInitialPage(html: string, dark: boolean): string {
  return dark ? html.replace('./appearance/themes/daylight/theme.css', './appearance/themes/midnight/theme.css') : html;
}

interface MarkdownPreferenceFile { version: number; value: MarkdownPreferences; }

export class MarkdownPreferenceStore {
  private value: MarkdownPreferences = { mode: 'ir', theme: 'system', fontSize: 16 };
  private writable: boolean = true;
  private queue: Promise<void> = Promise.resolve();
  private persist: (text: string) => Promise<void>;
  constructor(text: string | undefined, persist: (text: string) => Promise<void>) {
    this.persist = persist;
    if (text === undefined) return;
    try {
      const record = JSON.parse(text) as MarkdownPreferenceFile;
      if (record.version !== 1 || !record.value || !this.valid(record.value)) throw new Error('preferences format');
      this.value = record.value;
    } catch (error) { this.writable = false; }
  }
  private valid(value: MarkdownPreferences): boolean {
    return ['ir', 'wysiwyg', 'sv'].includes(value.mode) && ['system', 'light', 'dark'].includes(value.theme) &&
      [14, 16, 18, 20, 24, 28, 32].includes(value.fontSize);
  }
  get(): MarkdownPreferences { return { mode: this.value.mode, theme: this.value.theme, fontSize: this.value.fontSize }; }
  update(patch: MarkdownPreferences): Promise<MarkdownPreferences> {
    const operation = this.queue.then(async () => {
      if (!this.writable) throw new Error('preferences unavailable');
      const value = this.get();
      if (patch.mode !== undefined) value.mode = patch.mode;
      if (patch.theme !== undefined) value.theme = patch.theme;
      if (patch.fontSize !== undefined) value.fontSize = patch.fontSize;
      if (!this.valid(value)) throw new Error('preferences format');
      const record: MarkdownPreferenceFile = { version: 1, value: value };
      await this.persist(JSON.stringify(record));
      this.value = value;
      return this.get();
    });
    this.queue = operation.then(() => {}, () => {});
    return operation;
  }
}
