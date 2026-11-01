import { MarkdownFailure, markdownErrorCode, MarkdownIOError } from './MarkdownTypes';

export interface MarkdownTreeStat { identity: string; directory: boolean; file: boolean; symlink: boolean; }
export interface MarkdownTreeIO {
  stat: (uri: string) => Promise<MarkdownTreeStat>;
  list: (uri: string) => Promise<string[]>;
  parent: (uri: string) => string;
  name: (uri: string) => string;
  join: (uri: string, name: string) => string;
  hash: (text: string) => string;
  restore: (uri: string) => Promise<boolean>;
  persist: (uri: string) => Promise<boolean>;
}
export interface MarkdownTreeLocation { rootId: string; generation: number; nodeId: string; }
export interface MarkdownTreeView { rootId?: string; generation?: number; expanded?: string[]; width?: number; visible?: boolean; }
export interface MarkdownTreeNode { id: string; name: string; kind: string; }
interface TreeEntry { id: string; uri: string; identity: string; directory: boolean; parents: string[]; }
export interface MarkdownTreeRootView { id: string; uri: string; identity: string; expanded: string[]; }
interface TreeViewFile { version: number; width: number; visible: boolean; roots: MarkdownTreeRootView[]; }
export interface MarkdownTreeState {
  kind: string; generation: number; expanded: string[]; width: number; visible: boolean;
  rootId?: string; rootName?: string; currentNodeId?: string; currentPath?: string[]; error?: MarkdownFailure;
}
export interface MarkdownTreeListing {
  kind: string; rootId?: string; generation?: number; nodeId?: string; entries?: MarkdownTreeNode[]; error?: MarkdownFailure;
}

function validID(value: string): boolean { return typeof value === 'string' && new RegExp('^[a-f0-9]{64}$').test(value); }
function failure(error: MarkdownIOError): MarkdownFailure { return { code: markdownErrorCode(error), recoverable: true }; }

// 与正文偏好隔离。所有容器共享串行读合并写，损坏或未知版本保持原件并拒绝覆盖。
export class MarkdownTreeStore {
  private value: TreeViewFile = { version: 1, width: 240, visible: true, roots: [] };
  private writable: boolean = true;
  private queue: Promise<void> = Promise.resolve();
  private persist: (text: string) => Promise<void>;
  constructor(text: string | undefined, persist: (text: string) => Promise<void>) {
    this.persist = persist;
    if (text === undefined) return;
    try {
      const record = JSON.parse(text) as TreeViewFile;
      if (record.version !== 1 || !Number.isInteger(record.width) || record.width < 180 || record.width > 480 ||
        typeof record.visible !== 'boolean' || !Array.isArray(record.roots) || record.roots.length > 16) throw new Error('protocol');
      for (const root of record.roots) {
        if (!validID(root.id) || typeof root.uri !== 'string' || typeof root.identity !== 'string' ||
          !Array.isArray(root.expanded) || root.expanded.length > 256 || !root.expanded.every(validID)) throw new Error('protocol');
      }
      this.value = record;
    } catch (error) { this.writable = false; }
  }
  get(): TreeViewFile {
    if (!this.writable) throw new Error('protocol');
    return JSON.parse(JSON.stringify(this.value)) as TreeViewFile;
  }
  update(patch: MarkdownTreeView, root?: MarkdownTreeRootView): Promise<void> {
    const task = this.queue.then(async () => {
      const value = this.get();
      if (patch.width !== undefined) {
        if (!Number.isInteger(patch.width) || patch.width < 180 || patch.width > 480) throw new Error('protocol');
        value.width = patch.width;
      }
      if (patch.visible !== undefined) { if (typeof patch.visible !== 'boolean') throw new Error('protocol'); value.visible = patch.visible; }
      if (root) {
        const previous = value.roots.find((item: MarkdownTreeRootView) => item.id === root.id);
        const expanded = patch.expanded ?? previous?.expanded ?? [];
        if (!Array.isArray(expanded) || expanded.length > 256 || !expanded.every(validID)) throw new Error('protocol');
        const saved: MarkdownTreeRootView = { id: root.id, uri: root.uri, identity: root.identity, expanded: expanded.slice() };
        value.roots = [saved].concat(value.roots.filter((item: MarkdownTreeRootView) => item.id !== root.id)).slice(0, 16);
      }
      await this.persist(JSON.stringify(value)); this.value = value;
    });
    this.queue = task.then(() => {}, () => {});
    return task;
  }
}

// 只接收宿主生成的 ID。目录权限不传给图片解析器，也不接受渲染进程提供的路径。
export class MarkdownTree {
  private io: MarkdownTreeIO;
  private store: MarkdownTreeStore;
  private root?: TreeEntry;
  private nodes: Map<string, TreeEntry> = new Map();
  private signatures: Map<string, string> = new Map();
  private current: string = '';
  private manual: boolean = false;
  private unavailable: boolean = false;
  private rootName: string = '';
  private epoch: number = 0;
  private generation: number = 0;
  constructor(io: MarkdownTreeIO, store: MarkdownTreeStore) { this.io = io; this.store = store; }
  private async validate(node: TreeEntry): Promise<void> {
    const current = await this.io.stat(node.uri);
    if (current.symlink || current.directory !== node.directory || current.identity !== node.identity) throw new Error('identity-changed');
  }
  private async checked(location: MarkdownTreeLocation): Promise<TreeEntry> {
    if (!this.root || location.rootId !== this.root.id || location.generation !== this.generation) throw new Error('protocol');
    const node = this.nodes.get(location.nodeId);
    if (!node) throw new Error('protocol');
    for (const id of [this.root.id].concat(node.parents)) {
      const ancestor = this.nodes.get(id);
      if (!ancestor) throw new Error('protocol');
      await this.validate(ancestor);
    }
    await this.validate(node);
    return node;
  }
  private async children(node: TreeEntry, root: TreeEntry): Promise<TreeEntry[]> {
    if (!node.directory || node.parents.length >= 64) throw new Error('size');
    const parents = node.parents.concat(node.id);
    await this.validate(root); await this.validate(node);
    for (const id of node.parents) { const ancestor = this.nodes.get(id); if (!ancestor) throw new Error('protocol'); await this.validate(ancestor); }
    const names = await this.io.list(node.uri);
    if (names.length > 10000) throw new Error('size');
    const entries: TreeEntry[] = [];
    for (const name of names) {
      if (!name || name === '.' || name === '..' || new RegExp('[\\/\u0000-\u001f]').test(name)) continue;
      const uri = this.io.join(node.uri, name);
      if (!uri.startsWith(root.uri + '/')) throw new Error('permission');
      let stat: MarkdownTreeStat;
      try { stat = await this.io.stat(uri); }
      catch (error) { continue; } // 单个子项消失或撤权不能使仍可用的父目录失效。
      if (stat.symlink || (!stat.directory && (!stat.file || !new RegExp('\\.(md|markdown)$', 'i').test(name)))) continue;
      if (stat.directory && (stat.identity === root.identity || parents.some((id: string) => this.nodes.get(id)?.identity === stat.identity))) continue;
      const id = this.io.hash(root.id + '\u0000' + uri.slice(root.uri.length) + '\u0000' + stat.identity);
      entries.push({ id: id, uri: uri, identity: stat.identity, directory: stat.directory, parents: parents });
    }
    await this.validate(root); await this.validate(node);
    for (const id of node.parents) { const ancestor = this.nodes.get(id); if (!ancestor) throw new Error('protocol'); await this.validate(ancestor); }
    return entries.sort((a: TreeEntry, b: TreeEntry): number => {
      if (a.directory !== b.directory) return a.directory ? -1 : 1;
      const order = this.io.name(a.uri).localeCompare(this.io.name(b.uri), 'en', { numeric: true, sensitivity: 'base' });
      return order || a.id.localeCompare(b.id);
    });
  }
  private signature(entries: TreeEntry[]): string { return entries.map((entry: TreeEntry) => entry.id).join(':'); }
  async choose(uri: string): Promise<void> {
    const ticket = ++this.epoch;
    await this.install(uri, true, ticket);
  }
  private async install(uri: string, manual: boolean, ticket: number): Promise<void> {
    const stat = await this.io.stat(uri);
    if (stat.symlink || !stat.directory) throw new Error('permission');
    const id = this.io.hash(uri + '\u0000' + stat.identity);
    const root: TreeEntry = { id: id, uri: uri, identity: stat.identity, directory: true, parents: [] };
    const entries = await this.children(root, root);
    if (ticket !== this.epoch) throw new Error('protocol');
    await this.io.persist(uri);
    const saved: MarkdownTreeRootView = { id: id, uri: uri, identity: stat.identity, expanded: [] };
    await this.store.update({}, saved);
    if (ticket !== this.epoch) throw new Error('protocol');
    this.generation++; this.root = root; this.rootName = this.io.name(uri); this.manual = manual; this.unavailable = false;
    this.nodes.clear(); this.signatures.clear(); this.nodes.set(id, root);
    entries.forEach((entry: TreeEntry) => this.nodes.set(entry.id, entry));
    this.signatures.set(id, this.signature(entries));
  }
  async follow(uri: string, authorizedDirectory: string = ''): Promise<void> {
    this.current = uri;
    if (this.manual || (this.root && uri.startsWith(this.root.uri + '/'))) return;
    const ticket = ++this.epoch;
    this.generation++; this.root = undefined; this.nodes.clear(); this.signatures.clear();
    this.unavailable = uri.length > 0; this.rootName = uri ? this.io.name(this.io.parent(uri)) : '';
    if (!uri) return;
    if (authorizedDirectory && uri.startsWith(authorizedDirectory + '/')) {
      await this.install(this.io.parent(uri), false, ticket); return;
    }
    const saved = this.store.get();
    for (const root of saved.roots) {
      if (!uri.startsWith(root.uri + '/') || !await this.io.restore(root.uri)) continue;
      const stat = await this.io.stat(root.uri);
      if (stat.symlink || !stat.directory || stat.identity !== root.identity) continue;
      await this.install(this.io.parent(uri), false, ticket); return;
    }
  }
  async file(location: MarkdownTreeLocation): Promise<string> {
    const node = await this.checked(location);
    if (node.directory) throw new Error('protocol');
    return node.uri;
  }
  async list(location: MarkdownTreeLocation): Promise<MarkdownTreeListing> {
    try {
      const node = await this.checked(location);
      const root = this.root;
      const ticket = this.generation;
      const entries = await this.children(node, root);
      if (ticket !== this.generation || root !== this.root) throw new Error('protocol');
      const removed = new Set<string>();
      this.nodes.forEach((item: TreeEntry) => {
        if (item.parents[item.parents.length - 1] === node.id && !entries.some((next: TreeEntry) => next.id === item.id)) removed.add(item.id);
      });
      this.nodes.forEach((item: TreeEntry) => { if (removed.has(item.id) || item.parents.some((id: string) => removed.has(id))) this.nodes.delete(item.id); });
      if (this.nodes.size + entries.filter((entry: TreeEntry) => !this.nodes.has(entry.id)).length > 10000) throw new Error('size');
      entries.forEach((entry: TreeEntry) => this.nodes.set(entry.id, entry));
      this.signatures.set(node.id, this.signature(entries));
      const output = entries.map((entry: TreeEntry): MarkdownTreeNode => {
        return { id: entry.id, name: this.io.name(entry.uri), kind: entry.directory ? 'directory' : 'file' };
      });
      return { kind: 'listed', rootId: root.id, generation: ticket, nodeId: node.id, entries: output };
    } catch (error) { return { kind: 'blocked', error: failure(error as MarkdownIOError) }; }
  }
  async state(): Promise<MarkdownTreeState> {
    let state: MarkdownTreeState = { kind: this.root ? 'ready' : this.unavailable ? 'permission-required' : 'empty',
      generation: this.generation, width: 240, visible: true, expanded: [], rootName: this.rootName };
    try {
      const saved = this.store.get();
      state.width = saved.width; state.visible = saved.visible;
      const root = this.root;
      if (!root) return state;
      const generation = this.generation;
      await this.validate(root);
      state.rootId = root.id;
      state.expanded = saved.roots.find((item: MarkdownTreeRootView) => item.id === root.id)?.expanded ?? [];
      if (this.current.startsWith(root.uri + '/')) {
        const parts = this.current.slice(root.uri.length + 1).split('/'); parts.pop();
        let parent = root.id;
        let resolved = true;
        state.currentPath = [root.id];
        for (const part of parts) {
          const listed = await this.list({ rootId: root.id, generation: generation, nodeId: parent });
          if (listed.kind !== 'listed') {
            if (parent === root.id) { state.kind = 'blocked'; state.error = listed.error; }
            resolved = false; break;
          }
          let next: TreeEntry | undefined;
          this.nodes.forEach((node: TreeEntry) => { if (node.parents[node.parents.length - 1] === parent && node.directory && this.io.name(node.uri) === decodeURIComponent(part)) next = node; });
          if (!next) { resolved = false; break; }
          parent = next.id; state.currentPath.push(parent);
        }
        if (resolved) {
          const listed = await this.list({ rootId: root.id, generation: generation, nodeId: parent });
          if (listed.kind === 'listed') this.nodes.forEach((node: TreeEntry) => { if (node.uri === this.current) state.currentNodeId = node.id; });
          else if (parent === root.id) { state.kind = 'blocked'; state.error = listed.error; }
        }
      }
      await this.validate(root);
      if (generation !== this.generation || root !== this.root) throw new Error('protocol');
      return state;
    } catch (error) { state.kind = 'blocked'; state.error = failure(error as MarkdownIOError); return state; }
  }
  async saveView(view: MarkdownTreeView): Promise<void> {
    if (view.expanded !== undefined && (!this.root || view.rootId !== this.root.id || view.generation !== this.generation)) throw new Error('protocol');
    const root: MarkdownTreeRootView | undefined = this.root ? { id: this.root.id, uri: this.root.uri, identity: this.root.identity, expanded: [] } : undefined;
    await this.store.update(view, root);
  }
  async poll(): Promise<boolean> {
    const root = this.root;
    if (!root) return false;
    const ticket = this.generation;
    try {
      const expanded = this.store.get().roots.find((item: MarkdownTreeRootView) => item.id === root.id)?.expanded ?? [];
      for (const id of [root.id].concat(expanded)) {
        const node = this.nodes.get(id);
        if (!node?.directory) continue;
        const entries = await this.children(node, root);
        if (ticket !== this.generation) return false;
        if (this.signatures.get(id) !== this.signature(entries)) return true;
      }
      return false;
    } catch (error) { return ticket === this.generation; }
  }
  watchDirectories(): string[] {
    if (!this.root) return [];
    const expanded = this.store.get().roots.find((item: MarkdownTreeRootView) => item.id === this.root.id)?.expanded ?? [];
    const result: string[] = [];
    for (const id of [this.root.id].concat(expanded)) {
      const node = this.nodes.get(id);
      if (node?.directory) result.push(node.uri);
    }
    return result;
  }
}
