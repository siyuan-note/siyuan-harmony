import { MarkdownPreferences, MarkdownFonts } from './MarkdownTypes';

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
      Number.isInteger(value.fontSize) && value.fontSize >= 9 && value.fontSize <= 72 && this.validFonts(value.fonts);
  }
  private validFonts(fonts?: MarkdownFonts): boolean {
    if (fonts === undefined) return true;
    if (!fonts || Object.keys(fonts).length !== 3) return false;
    return [fonts.global, fonts.editor, fonts.code].every(items => Array.isArray(items) && items.length <= 64 &&
      items.every(item => item && typeof item.family === 'string' && item.family.trim().length > 0 &&
        item.family.length <= 256 && Number.isInteger(item.weight) && item.weight >= 1 && item.weight <= 1000));
  }
  get(): MarkdownPreferences { return JSON.parse(JSON.stringify(this.value)) as MarkdownPreferences; }
  update(patch: MarkdownPreferences): Promise<MarkdownPreferences> {
    const operation = this.queue.then(async () => {
      if (!this.writable) throw new Error('preferences unavailable');
      const value = this.get();
      if (patch.mode !== undefined) value.mode = patch.mode;
      if (patch.theme !== undefined) value.theme = patch.theme;
      if (patch.fontSize !== undefined) value.fontSize = patch.fontSize;
      if (patch.fonts !== undefined) value.fonts = patch.fonts;
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
