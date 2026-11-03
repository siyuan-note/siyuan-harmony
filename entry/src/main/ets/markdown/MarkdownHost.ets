import { common, bundleManager, ConfigurationConstant } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { i18n } from '@kit.LocalizationKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { MarkdownTransactions } from './MarkdownTransactions';
import { markdownRegistry } from './MarkdownRegistry';
import { MarkdownLifetime, MarkdownParticipant } from './MarkdownLifetime';
import { HarmonyMarkdownIO, HarmonyMarkdownStore, MarkdownAssets, canonicalMarkdownURI,
  persistMarkdownPermission, activateMarkdownPermission, writeMarkdownAtomic, markdownFileIdentity, markdownDirectory } from './MarkdownFiles';
import { MarkdownTree, MarkdownTreeStore, MarkdownTreeIO, MarkdownTreeStat, MarkdownTreeLocation, MarkdownTreeView } from './MarkdownTree';
import { MarkdownResourceAccess, MarkdownResourceGrant, MarkdownResourceIO, MarkdownResourceStat, MarkdownImageIO, copyMarkdownImage } from './MarkdownResources';
import { MarkdownPreferenceStore, markdownThemeDark, markdownInitialPage } from './MarkdownPreferences';
import { MarkdownRecoveryTransfers, latestMarkdownRecovery } from './MarkdownRecovery';
import { MarkdownWindows } from './MarkdownWindows';
import { MarkdownOperation, MarkdownFormat, MarkdownCommit, MarkdownPrepared, MarkdownWatermark,
  MarkdownReceipt, MarkdownPreferences, MarkdownRecord, MarkdownState, MarkdownFailure, MARKDOWN_ORIGIN, MARKDOWN_PAGE,
  MARKDOWN_RECOVERY_CONTENT_LIMIT, MARKDOWN_ASSET_LIMIT, validMarkdownFormat, validMarkdownId, markdownErrorCode, MarkdownIOError } from './MarkdownTypes';

interface NativeRequest { id: string; action: string; payload?: Object; }
interface NativeResponse { id: string; result?: Object | string | boolean; error?: string; }
interface NativeCommand { id: string; type: string; dark?: boolean; }
interface CommandReply { id: string; accepted: boolean; }
interface ReleaseRequest { sessionId: string; reservationId: string; operationId: string; targetGeneration: number; }
interface RecoveryItem { id: string; displayName: string; updatedAt: number; }
interface RecoveryVersion { revision: number; targetGeneration: number; }
interface ImageResult { kind: string; reference?: string; }
interface Bootstrap {
  sessionId: string; content: string; target?: Object; format: MarkdownFormat; recovered?: RecoveryVersion;
  preferences: MarkdownPreferences; languages: Record<string, string>; lang: string; platform: string; dark: boolean;
}
interface PendingCommand { resolve: (accepted: boolean) => void; timer: number; }
interface TreeCandidate { ticket: string; transactions: MarkdownTransactions; content: string; format: MarkdownFormat; epoch: number; }
interface TreeOpenResult { kind: string; ticket?: string; sessionId?: string; error?: MarkdownFailure; }

export interface MarkdownNativeUI {
  theme?: (dark: boolean) => void;
  confirm: (title: string, message: string, choices: string[]) => Promise<number>;
  filename: (title: string, initial: string, accept: string, cancel: string) => Promise<string>;
  failure: (message: string) => void;
  notice: (message: string) => void;
}

export class MarkdownOccupiedError extends Error {
  readonly sessionId: string;
  constructor(sessionId: string) { super('occupied'); this.sessionId = sessionId; }
}

export class MarkdownHost {
  private static store?: HarmonyMarkdownStore;
  private static preferences?: MarkdownPreferenceStore;
  private static treeStore?: MarkdownTreeStore;
  private static recoveryTransfers: MarkdownRecoveryTransfers = new MarkdownRecoveryTransfers();
  private context: common.UIAbilityContext;
  private controller?: webview.WebviewController;
  private ui?: MarkdownNativeUI;
  private io: HarmonyMarkdownIO = new HarmonyMarkdownIO();
  private transactions: MarkdownTransactions;
  private runtime: string = '';
  private languages: Record<string, string> = {};
  private lang: string = 'en';
  private initialContent: string = '';
  private initializationError: string = '';
  private initialFormat: MarkdownFormat = { bom: false, newline: '\n' };
  private recovered: boolean = false;
  private preference: MarkdownPreferences = { mode: 'ir', theme: 'system', fontSize: 16 };
  private resources: Map<string, MarkdownResourceGrant> = new Map();
  private imageFiles: Map<string, string> = new Map();
  private resourceAccess: MarkdownResourceAccess;
  private directory: string = '';
  private pending: Map<string, PendingCommand> = new Map();
  private ready: boolean = false;
  private pageGeneration: number = 0;
  private destroyed: boolean = false;
  private protectedFailure: boolean = false;
  private requestIds: Set<string> = new Set();
  private polling: boolean = false;
  private foregroundActive: boolean = false;
  private pollTimer: number = -1;
  private observedVersion: string = '';
  private dark: boolean = false;
  private tree?: MarkdownTree;
  private treeCandidate?: TreeCandidate;
  private treeOpening: boolean = false;
  private treeRequestEpoch: number = 0;
  private treeCommitted: string = '';
  private documentEpoch: number = 0;
  private released: boolean = false;
  private treeTimer: number = -1;
  private treePolling: boolean = false;
  private treeWatchers: Map<string, fs.Watcher> = new Map();
  private saveAsDirectories: Map<string, string> = new Map();
  private treeFollowAfterCancel?: string;
  readonly containerId: string;
  get sessionId(): string { return this.transactions.sessionId; }
  get targetURI(): string { return this.transactions.getURI(); }
  reportOpenFailure(): void { this.ui?.notice(this.text('markdownFileUnavailable')); }
  async canFocus(sessionId: string): Promise<boolean> {
    await this.transactions.settled();
    return !this.destroyed && !this.released && this.sessionId === sessionId;
  }

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.dark = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.containerId = this.io.newId();
    const resourceIO: MarkdownResourceIO = {
      stat: async (uri: string): Promise<MarkdownResourceStat> => {
        const stat: fs.Stat = await fs.lstat(new fileUri.FileUri(uri).path);
        if (stat.ino <= 0) throw new Error('resource identity unavailable');
        return { identity: markdownFileIdentity(stat, uri), symlink: stat.isSymbolicLink(), directory: stat.isDirectory() };
      },
      open: (uri: string) => this.io.openResource(uri)
    };
    this.resourceAccess = new MarkdownResourceAccess(resourceIO);
    if (!MarkdownHost.store) MarkdownHost.store = new HarmonyMarkdownStore(context);
    if (MarkdownHost.store.list().some((record: MarkdownRecord) => record.sessionId === this.containerId)) throw new Error('identifier collision');
    this.transactions = new MarkdownTransactions(this.containerId, this.io, MarkdownHost.store, markdownRegistry);
    this.registerLifetime();
  }

  private registerLifetime(): void {
    const participant: MarkdownParticipant = {
      prepare: async () => { await this.cancelTreeCandidate(); return this.protectedFailure ? true : this.command('prepare-quit'); },
      cancel: () => { void this.command('cancel-quit'); }, close: () => this.close()
    };
    MarkdownLifetime.add(this.sessionId, participant);
  }

  async initialize(uri: string, recoveryId: string): Promise<void> {
    const bundle: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    this.runtime = await MarkdownAssets.initialize(this.context, String(bundle.versionCode));
    const requested: string = i18n.System.getSystemLanguage();
    const choices: string[] = [requested, requested.split('-')[0], 'en'];
    for (const language of choices) {
      if (!new RegExp("^[a-z]{2}(?:-[A-Z]{2})?$").test(language)) continue;
      const path = this.runtime + '/appearance/langs/' + language + '.json';
      if (fs.accessSync(path)) {
        this.languages = JSON.parse(fs.readTextSync(path)) as Record<string, string>;
        this.lang = language;
        break;
      }
    }
    const preferencePath = markdownDirectory(this.context) + '/preferences.conf';
    if (!MarkdownHost.preferences) {
      let contents: string | undefined;
      try { if (fs.accessSync(preferencePath)) contents = fs.readTextSync(preferencePath); }
      catch (error) { contents = ''; }
      MarkdownHost.preferences = new MarkdownPreferenceStore(contents, (text: string) => writeMarkdownAtomic(preferencePath, text));
    }
    this.preference = MarkdownHost.preferences.get();
    const treePath = markdownDirectory(this.context) + '/tree-view.conf';
    if (!MarkdownHost.treeStore) {
      let contents: string | undefined;
      try { if (fs.accessSync(treePath)) contents = fs.readTextSync(treePath); } catch (error) { contents = ''; }
      MarkdownHost.treeStore = new MarkdownTreeStore(contents, (text: string) => writeMarkdownAtomic(treePath, text));
    }
    const treeIO: MarkdownTreeIO = {
      stat: async (uri: string): Promise<MarkdownTreeStat> => {
        const stat = await fs.lstat(new fileUri.FileUri(canonicalMarkdownURI(uri)).path);
        if (stat.ino <= 0) throw new Error('unavailable');
        return { identity: markdownFileIdentity(stat, uri), symlink: stat.isSymbolicLink(), directory: stat.isDirectory(), file: stat.isFile() };
      },
      list: (uri: string) => fs.listFile(new fileUri.FileUri(canonicalMarkdownURI(uri)).path, { recursion: false }),
      parent: (uri: string) => new fileUri.FileUri(uri).getFullDirectoryUri().replace(new RegExp('/$'), ''),
      name: (uri: string) => new fileUri.FileUri(uri).name,
      join: (uri: string, name: string) => canonicalMarkdownURI(uri + '/' + encodeURIComponent(name)),
      hash: (text: string) => this.io.digest(new util.TextEncoder().encodeInto(text)),
      restore: (uri: string) => activateMarkdownPermission(uri, false),
      persist: (uri: string) => persistMarkdownPermission(uri, false)
    };
    this.tree = new MarkdownTree(treeIO, MarkdownHost.treeStore);
    if (recoveryId && validMarkdownId(recoveryId)) {
      const record = MarkdownHost.store.read(MarkdownHost.recoveryTransfers.consume(recoveryId, Date.now()));
      const operation = latestMarkdownRecovery(record);
      if (!operation) throw new Error(this.text('markdownNoRecovery'));
      this.initialContent = operation.content;
      this.initialFormat = operation.format ?? operation.target?.format ?? this.initialFormat;
      this.recovered = true;
      // 恢复始终新建副本；原记录由用户显式删除，不凭失效的 URI 自动写回。
    } else if (uri) {
      const canonical = canonicalMarkdownURI(uri);
      const name: string = new fileUri.FileUri(canonical).name;
      if (!new RegExp("\\.(md|markdown)$", "i").test(name)) throw new Error(this.text('markdownFileUnavailable'));
      const persistent = await persistMarkdownPermission(canonical, true);
      const result = await this.transactions.authorize(canonical, name, persistent, false);
      if (result.kind === 'occupied' && result.sessionId) throw new MarkdownOccupiedError(result.sessionId);
      if (result.kind !== 'read') {
        const keys: Record<string, string> = { 'size': 'markdownTooLarge', 'encoding': 'agentSkillEncodingTip',
          'permission': 'markdownPermissionDenied', 'offline': 'markdownFileOffline', 'deleted': 'markdownFileDeleted',
          'identity-changed': 'markdownFileReplaced', 'space': 'markdownNoSpace' };
        this.initializationError = this.text(keys[result.error?.code ?? ''] ?? 'markdownFileUnavailable');
        throw new Error(this.initializationError);
      }
      this.initialContent = result.content;
      this.initialFormat = result.target.format;
    }
    await this.tree.follow(this.transactions.getURI()).catch(() => {});
  }

  text(key: string): string { return this.languages[key] ?? key; }
  startupError(): string { return this.initializationError; }
  protect(): void {
    this.protectedFailure = true;
    this.ui?.failure(this.text(this.transactions.hasPending() ? 'markdownUncertain' : 'markdownLoadError'));
  }
  attach(controller: webview.WebviewController, ui: MarkdownNativeUI): void {
    this.controller = controller;
    this.ui = ui;
    this.ui.theme?.(this.effectiveDark());
  }
  effectiveDark(): boolean { return markdownThemeDark(this.preference.theme, this.dark); }
  detachUI(controller: webview.WebviewController): void { if (this.controller === controller) this.ui = undefined; }
  pageReady(url: string): void {
    this.pageGeneration++;
    this.ready = url === MARKDOWN_PAGE;
    if (this.ready) this.transactions.beginRenderer();
  }

  private currentPage(): boolean {
    try { return !this.destroyed && this.controller?.getUrl() === MARKDOWN_PAGE; }
    catch (error) { return false; }
  }

  private async sendScript(script: string): Promise<void> {
    if (!this.currentPage()) throw new Error('Markdown page unavailable');
    await this.controller.runJavaScript(script);
  }

  postMessage(message: string): void {
    if (!this.currentPage() ||
      typeof message !== 'string' || message.length > MARKDOWN_RECOVERY_CONTENT_LIMIT * 8) return;
    let request: NativeRequest;
    try { request = JSON.parse(message) as NativeRequest; }
    catch (error) { return; }
    if (!request || !validMarkdownId(request.id) || typeof request.action !== 'string' || this.requestIds.has(request.id)) return;
    const generation = this.pageGeneration;
    const epoch = this.documentEpoch;
    this.requestIds.add(request.id);
    void this.dispatch(request).then((result: Object | string | boolean | undefined) => {
      if (generation !== this.pageGeneration) return;
      if (epoch === this.documentEpoch || request.action === 'tree-commit-open') this.reply({ id: request.id, result: result });
      else this.reply({ id: request.id, error: 'Stale Markdown request' });
    }).catch((error: Error) => {
      if (generation !== this.pageGeneration) return;
      if (epoch !== this.documentEpoch) { this.reply({ id: request.id, error: 'Stale Markdown request' }); return; }
      if (request.action === 'bootstrap') {
        this.protect();
      }
      this.reply({ id: request.id, error: error.message || 'Markdown operation failed' });
    }).finally(() => this.requestIds.delete(request.id));
  }

  private reply(response: NativeResponse): void {
    void this.sendScript('window.__siyuanMarkdownResponse(' + JSON.stringify(response) + ')').catch(() => {});
  }

  private async dispatch(request: NativeRequest): Promise<Object | string | boolean | undefined> {
    const action = request.action;
    const epoch = this.documentEpoch;
    if (action === 'bootstrap') {
      if (!await this.transactions.recoverPending()) throw new Error(this.text('markdownUncertain'));
      const record = MarkdownHost.store.read(this.sessionId);
      const recovery = latestMarkdownRecovery(record);
      const bootstrap: Bootstrap = { sessionId: this.sessionId, content: this.initialContent,
        target: this.transactions.getTarget(), format: this.initialFormat, preferences: this.preference,
        languages: this.languages, lang: this.lang, platform: 'harmony', dark: this.dark };
      if (recovery) {
        bootstrap.content = recovery.content;
        bootstrap.format = recovery.format ?? recovery.target?.format ?? this.initialFormat;
        bootstrap.recovered = { revision: recovery.revision, targetGeneration: this.transactions.getGeneration() };
      } else if (bootstrap.target) {
        const request: MarkdownOperation = { sessionId: this.sessionId, operationId: this.io.newId(),
          targetGeneration: this.transactions.getGeneration(), revision: 0, content: '', target: this.transactions.getTarget() };
        const result = await this.transactions.read(request);
        if (result.kind !== 'read') throw new Error(this.text('markdownFileUnavailable'));
        bootstrap.content = result.content;
        bootstrap.target = result.target;
        bootstrap.format = result.target.format;
      } else if (this.recovered) bootstrap.recovered = { revision: 1, targetGeneration: 0 };
      return bootstrap;
    }
    if (action === 'tree-state') return this.tree.state();
    if (action === 'tree-list') {
      const result = await this.tree.list(request.payload as MarkdownTreeLocation);
      if (epoch !== this.documentEpoch) throw new Error('protocol');
      return result;
    }
    if (action === 'tree-choose-root') {
      if (this.treeCandidate || this.treeOpening) throw new Error('protocol');
      const uri = await this.chooseDirectory();
      if (!uri) return { kind: 'cancelled' } as TreeOpenResult;
      if (epoch !== this.documentEpoch) throw new Error('protocol');
      await this.tree.choose(uri); void this.command('tree-change'); return this.tree.state();
    }
    if (action === 'tree-save-view') { await this.tree.saveView(request.payload as MarkdownTreeView); return; }
    if (action === 'tree-prepare-open') return this.prepareTreeOpen(request.payload as MarkdownTreeLocation);
    if (action === 'tree-commit-open') {
      const ticket = request.payload as string;
      if (ticket === this.treeCommitted && ticket) return this.initialBootstrap();
      const candidate = this.treeCandidate;
      if (!candidate || candidate.ticket !== ticket || candidate.epoch !== this.documentEpoch || !this.released) throw new Error('protocol');
      MarkdownLifetime.replace(this.sessionId, candidate.transactions.sessionId);
      this.documentEpoch++; this.transactions = candidate.transactions; this.initialContent = candidate.content; this.initialFormat = candidate.format;
      this.treeCandidate = undefined; this.treeCommitted = ticket; this.released = false; this.recovered = false;
      this.treeFollowAfterCancel = undefined;
      this.resources.clear(); this.imageFiles.clear(); this.directory = ''; this.observedVersion = '';
      void this.tree.follow(this.transactions.getURI());
      return this.initialBootstrap();
    }
    if (action === 'tree-cancel-open') {
      if (this.treeCandidate?.ticket === request.payload as string) await this.cancelTreeCandidate();
      return;
    }
    if (action === 'host:read') return this.transactions.read(request.payload as MarkdownOperation);
    if (action === 'host:write') return this.transactions.write(request.payload as MarkdownOperation);
    if (action === 'host:reconcileWrite') return this.transactions.reconcile(request.payload as MarkdownOperation);
    if (action === 'host:reserveSaveAs') return this.transactions.reserve(request.payload as MarkdownOperation);
    if (action === 'host:prepareSaveAs') { await this.transactions.prepare(request.payload as MarkdownPrepared); return; }
    if (action === 'host:commitSaveAs') {
      const result = await this.transactions.commit(request.payload as MarkdownCommit);
      if (epoch !== this.documentEpoch) throw new Error('protocol');
      if (result.kind === 'committed') {
        this.resources.clear(); this.imageFiles.clear(); this.directory = '';
        const selectedDirectory = this.saveAsDirectories.get(this.transactions.getTarget()?.handle ?? '') ?? '';
        this.saveAsDirectories.clear();
        if (this.treeCandidate) this.treeFollowAfterCancel = selectedDirectory;
        else await this.tree.follow(this.transactions.getURI(), selectedDirectory, true).catch(() => {});
        void this.command('tree-change');
      }
      return result;
    }
    if (action === 'host:releaseSaveAs') {
      const payload = request.payload as ReleaseRequest;
      if (payload.sessionId !== this.sessionId) throw new Error('protocol');
      this.transactions.releaseReservation(payload.reservationId, payload.operationId); return;
    }
    if (action === 'host:putDraft') { await this.transactions.putDraft(request.payload as MarkdownOperation); return; }
    if (action === 'host:clearDraft') { await this.transactions.clearDraft(request.payload as MarkdownWatermark); return; }
    if (action === 'host:releaseSession') {
      const payload = request.payload as ReleaseRequest;
      if (payload.sessionId !== this.sessionId || payload.targetGeneration !== this.transactions.getGeneration()) throw new Error('protocol');
      await this.transactions.release(); this.released = true; return;
    }
    if (action === 'save-as') return this.saveAs(request.payload as MarkdownFormat);
    if (action === 'cancel-save-as') {
      this.transactions.releaseCandidate(request.payload as string); this.saveAsDirectories.delete(request.payload as string); return;
    }
    if (action === 'new') { await this.openAbility('', ''); return; }
    if (action === 'open') {
      const choice: string[] = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1, fileSuffixFilters: ['.md,.markdown'] });
      if (choice.length) await this.openAbility(canonicalMarkdownURI(choice[0]), '');
      return;
    }
    if (action === 'authorize-resources') {
      const directory = await this.chooseDirectory();
      if (!directory) return false;
      if (epoch !== this.documentEpoch) throw new Error('protocol');
      await persistMarkdownPermission(directory, false);
      if (epoch !== this.documentEpoch) throw new Error('protocol');
      this.directory = directory;
      this.resources.clear();
      return true;
    }
    if (action === 'resource') return this.resolveResource(request.payload as string);
    if (action === 'insert-image') return this.insertImage();
    if (action === 'link') {
      const url = request.payload as string;
      if (typeof url !== 'string' || !new RegExp("^(?:https?:\\/\\/|mailto:)", "i").test(url) || new RegExp("[\\u0000-\\u001f]").test(url)) throw new Error('protocol');
      await this.context.openLink(url); return;
    }
    if (action === 'preferences') {
      this.preference = await MarkdownHost.preferences.update(request.payload as MarkdownPreferences);
      this.ui?.theme?.(this.effectiveDark());
      return this.preference;
    }
    if (action === 'confirm') {
      const kind = request.payload as string;
      if (!['reload', 'overwrite', 'save-as'].includes(kind)) throw new Error('protocol');
      const key = kind === 'reload' ? 'markdownReload' : kind === 'overwrite' ? 'markdownOverwrite' : 'saveAs';
      const message = kind === 'save-as' ? 'markdownRelativeLinks' : kind === 'reload' ? 'markdownReloadConfirm' : 'markdownOverwriteConfirm';
      return await this.ui.confirm(this.text(key), this.text(message), [this.text('cancel'), this.text('confirm')]) === 1;
    }
    if (action === 'confirm-close') {
      const choice = await this.ui.confirm(this.text('markdownUnsaved'), this.text('markdownCloseDraft'),
        [this.text('cancel'), this.text('markdownKeepDraft'), this.text('saveAs')]);
      return choice === 1 ? 'keep' : choice === 2 ? 'save-as' : 'cancel';
    }
    if (action === 'recoveries') {
      const items: RecoveryItem[] = [];
      for (const record of MarkdownHost.store.list()) {
        if (!MarkdownLifetime.isActive(record.sessionId) && (record.draft || record.journal || record.prepared)) {
          items.push({ id: record.sessionId, displayName: record.displayName, updatedAt: record.updatedAt });
        }
      }
      return items;
    }
    if (action === 'recover') {
      const id = request.payload as string;
      if (MarkdownLifetime.isActive(id)) throw new Error('protocol');
      await this.openAbility('', id); return;
    }
    if (action === 'discard-recovery') {
      const id = request.payload as string;
      if (!validMarkdownId(id) || MarkdownLifetime.isActive(id)) throw new Error('protocol');
      if (await this.ui.confirm(this.text('delete'), this.text('markdownRecovery'), [this.text('cancel'), this.text('delete')]) === 1) {
        await MarkdownHost.store.remove(id);
      }
      return;
    }
    if (action === 'state') {
      const state = request.payload as MarkdownState;
      if ((request.payload as MarkdownOperation).sessionId !== this.sessionId || !Number.isSafeInteger(state.revision)) throw new Error('protocol');
      return;
    }
    if (action === 'response') {
      const response = request.payload as CommandReply;
      const pending = this.pending.get(response.id);
      if (pending) { clearTimeout(pending.timer); this.pending.delete(response.id); pending.resolve(response.accepted === true); }
      return;
    }
    throw new Error('Unknown Markdown operation');
  }

  private async cancelTreeCandidate(): Promise<void> {
    this.treeRequestEpoch++;
    const candidate = this.treeCandidate;
    if (!candidate) return;
    this.treeCandidate = undefined;
    await candidate.transactions.release();
    if (this.treeFollowAfterCancel !== undefined) {
      const directory = this.treeFollowAfterCancel; this.treeFollowAfterCancel = undefined;
      await this.tree.follow(this.transactions.getURI(), directory, true);
      void this.command('tree-change');
    }
  }
  private async prepareTreeOpen(location: MarkdownTreeLocation): Promise<TreeOpenResult> {
    if (this.treeOpening || this.treeCandidate || this.released || this.destroyed) throw new Error('protocol');
    this.treeOpening = true;
    const epoch = this.documentEpoch;
    const requestEpoch = this.treeRequestEpoch;
    let transactions: MarkdownTransactions | undefined;
    try {
      const uri = await this.tree.file(location);
      if (uri === this.transactions.getURI()) return { kind: 'current' };
      const sessionId = this.io.newId();
      if (MarkdownHost.store.list().some((record: MarkdownRecord) => record.sessionId === sessionId)) throw new Error('identifier collision');
      transactions = new MarkdownTransactions(sessionId, this.io, MarkdownHost.store, markdownRegistry);
      const persistent = await persistMarkdownPermission(uri, true);
      const result = await transactions.authorize(uri, new fileUri.FileUri(uri).name, persistent, false);
      if (result.kind === 'occupied' && result.sessionId) {
        await transactions.release();
        if (epoch !== this.documentEpoch || requestEpoch !== this.treeRequestEpoch || this.destroyed) throw new Error('protocol');
        if (!await MarkdownWindows.focus(result.sessionId, () => epoch === this.documentEpoch &&
          requestEpoch === this.treeRequestEpoch && !this.destroyed)) throw new Error('unavailable');
        if (epoch !== this.documentEpoch || requestEpoch !== this.treeRequestEpoch || this.destroyed) throw new Error('protocol');
        return { kind: 'occupied', sessionId: result.sessionId };
      }
      if (result.kind !== 'read') { await transactions.release(); return { kind: result.kind, error: result.error }; }
      if (epoch !== this.documentEpoch || requestEpoch !== this.treeRequestEpoch || this.destroyed || await this.tree.file(location) !== uri) throw new Error('protocol');
      const ticket = this.io.newId();
      if (ticket === this.treeCommitted) throw new Error('identifier collision');
      this.treeCandidate = { ticket: ticket, transactions: transactions, content: result.content, format: result.target.format, epoch: epoch };
      return { kind: 'ready', ticket: ticket, sessionId: transactions.sessionId };
    } catch (error) {
      if (transactions) await transactions.release();
      return { kind: 'blocked', error: { code: markdownErrorCode(error as MarkdownIOError), recoverable: true } };
    } finally { this.treeOpening = false; }
  }

  private initialBootstrap(): Bootstrap {
    return { sessionId: this.sessionId, content: this.initialContent, target: this.transactions.getTarget(), format: this.initialFormat,
      preferences: this.preference, languages: this.languages, lang: this.lang, platform: 'harmony', dark: this.dark };
  }

  private async openAbility(uri: string, recoveryId: string): Promise<void> {
    if (recoveryId && !validMarkdownId(recoveryId)) throw new Error('protocol');
    const token = recoveryId ? this.io.token() : '';
    if (token) MarkdownHost.recoveryTransfers.grant(token, recoveryId, Date.now());
    try {
      await this.context.startAbility({ bundleName: this.context.abilityInfo.bundleName, abilityName: 'MarkdownAbility',
        uri: uri, parameters: { markdownRecovery: token, markdownInstanceKey: uri || this.io.newId() } });
    } catch (error) { if (token) MarkdownHost.recoveryTransfers.cancel(token); throw error as Error; }
  }

  private async chooseDirectory(): Promise<string> {
    if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) throw new Error(this.text('markdownFileUnavailable'));
    const result: string[] = await new picker.DocumentViewPicker(this.context).select({ selectMode: picker.DocumentSelectMode.FOLDER, maxSelectNumber: 1 });
    return result.length ? canonicalMarkdownURI(result[0]).replace(new RegExp("\\/$"), '') : '';
  }

  private async chooseNewURI(name: string): Promise<string> {
    const directory = await this.chooseDirectory();
    if (!directory) return '';
    const filename = await this.ui.filename(this.text('saveAs'), name, this.text('save'), this.text('cancel'));
    if (!filename) return '';
    if (filename === '.' || filename === '..' || filename.length > 240 || new RegExp("[\\u0000-\\u001f\\\\/:*?\"<>|]").test(filename)) throw new Error('Invalid filename');
    const uri = canonicalMarkdownURI(directory + '/' + encodeURIComponent(filename));
    if (await fs.access(new fileUri.FileUri(uri).path)) throw new Error(this.text('markdownConflict'));
    return uri;
  }

  private async saveAs(format: MarkdownFormat): Promise<MarkdownReceipt> {
    const epoch = this.documentEpoch;
    const transactions = this.transactions;
    if (!validMarkdownFormat(format)) throw new Error('protocol');
    const uri = await this.chooseNewURI(this.transactions.getTarget()?.displayName ?? 'Untitled.md');
    if (!uri) return { kind: 'cancelled' };
    if (epoch !== this.documentEpoch) throw new Error('protocol');
    if (!new RegExp("\\.(md|markdown)$", "i").test(new fileUri.FileUri(uri).name)) throw new Error(this.text('markdownFileUnavailable'));
    const persistent = await persistMarkdownPermission(uri, true);
    if (epoch !== this.documentEpoch) throw new Error('protocol');
    const result = await transactions.authorize(uri, new fileUri.FileUri(uri).name, persistent, true, format, true);
    if (result.target) this.saveAsDirectories.set(result.target.handle, new fileUri.FileUri(uri).getFullDirectoryUri().replace(new RegExp('/$'), ''));
    return result;
  }

  private async resolveResource(reference: string): Promise<string | undefined> {
    const epoch = this.documentEpoch;
    if ((!this.directory && this.imageFiles.size === 0) || typeof reference !== 'string' || !reference ||
      new RegExp("^[a-z][a-z0-9+.-]*:|^[\\/\\\\#]", "i").test(reference) || new RegExp("[\\u0000-\\u001f]").test(reference)) return undefined;
    const targetURI = this.transactions.getURI();
    if (!targetURI) return undefined;
    const base: string = new fileUri.FileUri(targetURI).getFullDirectoryUri();
    const parts = decodeURIComponent(reference.split(new RegExp("[?#]"))[0]).replace(new RegExp("\\\\", "g"), '/').split('/');
    const resolved = base.replace(new RegExp("\\/$"), '').split('/');
    for (const part of parts) {
      if (!part || part === '.') continue;
      if (part === '..') resolved.pop();
      else resolved.push(encodeURIComponent(part));
    }
    const uri = canonicalMarkdownURI(resolved.join('/'));
    if (!new RegExp("\\.(png|jpe?g|gif|webp|bmp|ico)$", "i").test(uri)) return undefined;
    const generation = this.transactions.getGeneration();
    const fileIdentity = this.imageFiles.get(uri) ?? '';
    const grant = await this.resourceAccess.capture(uri, fileIdentity ? '' : this.directory, generation, fileIdentity);
    if (epoch !== this.documentEpoch || generation !== this.transactions.getGeneration()) return undefined;
    const token = this.io.token();
    if (this.resources.size >= 512) this.resources.delete(this.resources.keys().next().value);
    this.resources.set(token, grant);
    return MARKDOWN_ORIGIN + '/resource/' + this.sessionId + '/' + token;
  }

  private async insertImage(): Promise<ImageResult> {
    const epoch = this.documentEpoch;
    const target = this.transactions.getTarget();
    if (!target?.writable) return { kind: 'blocked' };
    const generation = this.transactions.getGeneration();
    const sources: string[] = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1,
      fileSuffixFilters: ['.png,.jpg,.jpeg,.gif,.webp,.bmp,.ico'] });
    if (!sources.length) return { kind: 'cancelled' };
    const sourceURI = canonicalMarkdownURI(sources[0]);
    const destination = await this.chooseNewURI(new fileUri.FileUri(sourceURI).name);
    if (!destination) return { kind: 'cancelled' };
    const parent: string = new fileUri.FileUri(this.transactions.getURI()).getFullDirectoryUri().replace(new RegExp("\\/$"), '');
    if (epoch !== this.documentEpoch || !destination.startsWith(parent + '/') || generation !== this.transactions.getGeneration()) return { kind: 'blocked' };
    const sessionId = this.io.newId();
    if (MarkdownHost.store.list().some((record: MarkdownRecord) => record.sessionId === sessionId)) throw new Error('identifier collision');
    const assetSession = new MarkdownTransactions(sessionId, this.io, MarkdownHost.store, markdownRegistry);
    const reserved = await assetSession.authorize(destination, new fileUri.FileUri(destination).name, false, false,
      { bom: false, newline: '\n' }, true);
    if (reserved.kind !== 'read') return { kind: 'blocked' };
    let copiedIdentity = '';
    try {
      const imageIO: MarkdownImageIO = { open: (uri: string, writable: boolean) => this.io.openResource(uri, writable),
        digest: (bytes: Uint8Array) => this.io.digest(bytes) };
      copiedIdentity = await copyMarkdownImage(imageIO, sourceURI, destination, assetSession.getPhysicalIdentity());
    } finally { await assetSession.release(); }
    if (epoch !== this.documentEpoch || generation !== this.transactions.getGeneration()) return { kind: 'blocked' };
    // 导入仅授权该图片；不能把文件选择或子目录选择扩大成文档父目录授权。
    this.imageFiles.set(destination, copiedIdentity);
    return { kind: 'inserted', reference: destination.slice(parent.length + 1) };
  }

  async data(url: string): Promise<Uint8Array | undefined> {
    const epoch = this.documentEpoch;
    if (!url.startsWith(MARKDOWN_ORIGIN + '/') || new RegExp("[?#\\\\]").test(url)) return undefined;
    const resourcePrefix = MARKDOWN_ORIGIN + '/resource/' + this.sessionId + '/';
    if (url.startsWith(resourcePrefix)) {
      const grant = this.resources.get(url.slice(resourcePrefix.length));
      if (!grant || grant.generation !== this.transactions.getGeneration()) return undefined;
      const bytes = await this.resourceAccess.read(grant, this.transactions.getGeneration());
      return epoch === this.documentEpoch && grant.generation === this.transactions.getGeneration() ? bytes : undefined;
    }
    let relative = decodeURIComponent(url.slice(MARKDOWN_ORIGIN.length + 1));
    if (!relative.startsWith('stage/build/markdown/') || relative.split('/').some((part: string) => part === '..' || part === '.') ||
      new RegExp("[\\u0000-\\u001f\\\\]").test(relative)) return undefined;
    // Only the exact bundled script URL may read outside the editor asset root.
    if (url === MARKDOWN_ORIGIN + '/stage/build/markdown/vditor/dist/js/lute/lute.min.js') {
      relative = 'stage/protyle/js/lute/lute.min.js';
    }
    const file: fs.File = await fs.open(this.runtime + '/' + relative, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
    try {
      const size: number = (await fs.stat(file.fd)).size;
      if (size > MARKDOWN_ASSET_LIMIT) return undefined;
      const data = new Uint8Array(size);
      let offset = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(65536, size - offset));
        const count: number = await fs.read(file.fd, chunk, { offset: offset });
        if (count <= 0) throw new Error('asset read');
        data.set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      if (url === MARKDOWN_PAGE) {
        const html = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(data);
        return new util.TextEncoder().encodeInto(markdownInitialPage(html, this.effectiveDark()));
      }
      return data;
    } finally { await fs.close(file); }
  }

  resourceMime(url: string): string {
    const prefix = MARKDOWN_ORIGIN + '/resource/' + this.sessionId + '/';
    return url.startsWith(prefix) ? this.resources.get(url.slice(prefix.length))?.mime ?? '' : '';
  }

  command(type: string): Promise<boolean> {
    if (this.destroyed || !this.controller || !this.ready) return Promise.resolve(false);
    const id = this.io.newId();
    if (this.pending.has(id)) return Promise.resolve(false);
    const command: NativeCommand = { id: id, type: type };
    if (type === 'theme') command.dark = this.dark;
    if (type === 'cancel-quit' || type === 'external-change' || type === 'theme' || type === 'tree-change') {
      void this.sendScript('window.__siyuanMarkdownCommand(' + JSON.stringify(command) + ')').catch(() => {});
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => { this.pending.delete(id); resolve(false); }, 30000);
      this.pending.set(id, { resolve: resolve, timer: timer });
      void this.sendScript('window.__siyuanMarkdownCommand(' + JSON.stringify(command) + ')').catch(() => {
        clearTimeout(timer); this.pending.delete(id); resolve(false);
      });
    });
  }

  async close(): Promise<boolean> {
    await this.cancelTreeCandidate();
    if (this.protectedFailure) {
      await this.transactions.settled();
      await this.context.terminateSelf();
      return true;
    }
    const accepted = await this.command('close');
    if (accepted) await this.context.terminateSelf();
    return accepted;
  }
  async background(): Promise<void> {
    this.foregroundActive = false;
    clearTimeout(this.pollTimer);
    clearTimeout(this.treeTimer);
    this.stopTreeWatchers();
    await this.command('background');
  }
  setDark(dark: boolean): void {
    this.dark = dark;
    this.ui?.theme?.(this.effectiveDark());
    void this.command('theme');
  }
  async recoverProtected(): Promise<void> {
    if (this.protectedFailure) await this.openAbility('', this.sessionId);
  }
  async retryProtected(): Promise<void> {
    if (this.protectedFailure && await this.transactions.recoverPending()) {
      this.protectedFailure = false;
      this.ui?.failure('');
    }
  }
  async foreground(): Promise<void> {
    this.foregroundActive = true;
    void this.pollTree();
    await this.poll();
  }
  private async pollTree(): Promise<void> {
    if (this.destroyed || this.treePolling || !this.foregroundActive) return;
    this.treePolling = true;
    const epoch = this.documentEpoch;
    clearTimeout(this.treeTimer);
    try {
      this.syncTreeWatchers();
      if (await this.tree?.poll() && epoch === this.documentEpoch && this.ready) void this.command('tree-change');
    }
    finally {
      this.treePolling = false;
      if (!this.destroyed && this.foregroundActive) this.treeTimer = setTimeout(() => { void this.pollTree(); }, 3000);
    }
  }
  private stopTreeWatchers(): void {
    this.treeWatchers.forEach((watcher: fs.Watcher) => { try { watcher.stop(); } catch (error) {} });
    this.treeWatchers.clear();
  }
  private syncTreeWatchers(): void {
    let directories: string[];
    try { directories = this.tree?.watchDirectories() ?? []; } catch (error) { return; }
    this.treeWatchers.forEach((watcher: fs.Watcher, uri: string) => {
      if (!directories.includes(uri)) { try { watcher.stop(); } catch (error) {}; this.treeWatchers.delete(uri); }
    });
    for (const uri of directories) {
      if (this.treeWatchers.has(uri)) continue;
      try {
        const watcher = fs.createWatcher(new fileUri.FileUri(uri).path, 0x00000fc6, () => {
          if (!this.destroyed && this.foregroundActive && this.treeWatchers.has(uri)) void this.command('tree-change');
        });
        watcher.start(); this.treeWatchers.set(uri, watcher);
      } catch (error) { /* 提供方不支持 watcher 时由独立目录轮询补偿。 */ }
    }
  }
  private async poll(): Promise<void> {
    if (this.destroyed || this.polling || !this.foregroundActive) return;
    clearTimeout(this.pollTimer);
    this.polling = true;
    const target = this.transactions.getTarget();
    const generation = this.transactions.getGeneration();
    let observed = '';
    try {
      if (!this.ready || !target || this.transactions.hasPending()) return;
      const file = await this.io.open(this.transactions.getURI(), false, false);
      try {
        const snapshot = await file.snapshot();
        observed = snapshot.fileIdentity + ':' + snapshot.baseline;
        if (snapshot.fileIdentity === this.transactions.getPhysicalIdentity() && snapshot.baseline === target.baseline) {
          this.observedVersion = observed;
          return;
        }
      } finally { await file.close(); }
    } catch (error) { observed = 'error:' + markdownErrorCode(error as MarkdownIOError); }
    finally {
      this.polling = false;
      if (!this.destroyed && this.foregroundActive) this.pollTimer = setTimeout(() => { void this.poll(); }, 3000);
    }
    if (observed && observed !== this.observedVersion && generation === this.transactions.getGeneration() && !this.transactions.hasPending()) {
      this.observedVersion = observed;
      await this.command('external-change');
    }
  }
  destroy(): void {
    this.destroyed = true;
    this.foregroundActive = false;
    clearTimeout(this.pollTimer);
    clearTimeout(this.treeTimer);
    this.stopTreeWatchers();
    void this.cancelTreeCandidate();
    this.pending.forEach((value: PendingCommand) => { clearTimeout(value.timer); value.resolve(false); });
    this.pending.clear();
    this.resources.clear();
    this.imageFiles.clear();
    // 平台强制销毁时已确认的草稿和写入日志保持；未结算写入不能释放登记。
    void this.transactions.settled().then(async () => {
      try { await this.transactions.release(); } catch (error) { /* 不确定授权保留到进程结束。 */ }
      MarkdownLifetime.remove(this.sessionId);
    });
  }
}
