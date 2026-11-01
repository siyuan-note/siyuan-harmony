import type { MarkdownHost } from './MarkdownHost';

export class MarkdownWindows {
  private static hosts: Map<string, MarkdownHost> = new Map();
  private static focusers: Map<string, () => Promise<void>> = new Map();
  static add(host: MarkdownHost, focus?: () => Promise<void>): void {
    MarkdownWindows.hosts.set(host.containerId, host);
    if (focus) MarkdownWindows.focusers.set(host.containerId, focus);
  }
  static get(id: string): MarkdownHost | undefined { return MarkdownWindows.hosts.get(id); }
  static remove(id: string): void { MarkdownWindows.hosts.delete(id); MarkdownWindows.focusers.delete(id); }
  static async focus(sessionId: string, valid: () => boolean = () => true): Promise<boolean> {
    for (const host of MarkdownWindows.hosts.values()) {
      if (host.sessionId !== sessionId) continue;
      const focus = MarkdownWindows.focusers.get(host.containerId);
      if (!focus || !await host.canFocus(sessionId)) return false;
      if (!valid()) return false;
      try { await focus(); return true; } catch (error) { return false; }
    }
    return false;
  }
}
