import { MarkdownHost } from './MarkdownHost';

export class MarkdownWindows {
  private static hosts: Map<string, MarkdownHost> = new Map();
  static add(host: MarkdownHost): void { MarkdownWindows.hosts.set(host.containerId, host); }
  static get(id: string): MarkdownHost | undefined { return MarkdownWindows.hosts.get(id); }
  static remove(id: string): void { MarkdownWindows.hosts.delete(id); }
}
