import {
  MarkdownIO, MarkdownStore, MarkdownOperation, MarkdownReceipt, MarkdownTarget, MarkdownFormat,
  MarkdownWatermark, MarkdownCommit, MarkdownPrepared, MarkdownRecord, MarkdownSnapshot, MarkdownFile,
  MARKDOWN_LIMIT, MARKDOWN_RECOVERY_CONTENT_LIMIT, cloneMarkdownTarget, validMarkdownId, validMarkdownFormat, markdownBlocked,
  markdownUncertain, sameMarkdownVersion, MarkdownIOError, markdownErrorCode
} from './MarkdownTypes';
import { MarkdownRegistry, MarkdownGrant } from './MarkdownRegistry';

// 原生写入端不信任页面提交的路径、权限、身份、格式和版本；仅消费宿主发放的句柄。
export class MarkdownTransactions {
  private current?: MarkdownGrant;
  private generation: number = 0;
  private queue: Promise<void> = Promise.resolve();
  private closed: boolean = false;
  private rendererNamespace: string = '';
  private allowNewRenderer: boolean = true;
  private durableBinding?: MarkdownGrant;
  private unknownBinding: boolean = false;
  readonly sessionId: string;
  private io: MarkdownIO;
  private store: MarkdownStore;
  private registry: MarkdownRegistry;

  constructor(sessionId: string, io: MarkdownIO, store: MarkdownStore, registry: MarkdownRegistry) {
    this.sessionId = sessionId;
    this.io = io;
    this.store = store;
    this.registry = registry;
  }

  getTarget(): MarkdownTarget | undefined { return this.current ? cloneMarkdownTarget(this.current.target) : undefined; }
  getURI(): string { return this.current?.uri ?? ''; }
  getPhysicalIdentity(): string { return this.current?.fileIdentity ?? ''; }
  getGeneration(): number { return this.generation; }
  hasPending(): boolean { return this.registry.pending(this.sessionId).length > 0; }
  beginRenderer(): void { this.allowNewRenderer = true; }
  settled(): Promise<void> { return this.queue; }
  async recoverPending(): Promise<boolean> {
    await this.queue;
    const grants = this.registry.pending(this.sessionId);
    for (const grant of grants) {
      const request = grant.pending;
      const receipt = await this.reconcile(request);
      if (receipt.kind === 'committed' && grant.reservationId) {
        const commit = await this.commit({ operation: request, receipt: receipt, previousTarget: this.current?.target,
          nextTargetGeneration: grant.generation });
        if (commit.kind !== 'committed') return false;
      } else if (receipt.kind === 'blocked') {
        if (grant.reservationId) this.releaseCandidate(grant.target.handle);
      } else if (receipt.kind !== 'committed') return false;
    }
    return true;
  }

  async authorize(uri: string, name: string, persistent: boolean, candidate: boolean,
    format: MarkdownFormat = { bom: false, newline: '\n' }, create: boolean = false): Promise<MarkdownReceipt> {
    if (this.closed || !uri.startsWith('file://') || !validMarkdownFormat(format)) return markdownBlocked();
    const target: MarkdownTarget = { handle: this.io.uuid(), identity: this.io.uuid(), displayName: name, baseline: '',
      writable: true, format: format, capabilities: { persistentPermission: persistent, conditionalWrite: false,
        atomicReplace: false, coordinatedAccess: false } };
    const grant = new MarkdownGrant(target);
    grant.owner = this.sessionId;
    grant.uri = uri;
    grant.reservationId = candidate ? this.io.uuid() : '';
    grant.generation = candidate ? this.generation + 1 : this.generation;
    grant.created = create;
    const occupied = this.registry.reserve(grant);
    if (occupied) return { kind: 'occupied', sessionId: occupied };
    let file: MarkdownFile | undefined;
    let accepted = false;
    try {
      try { file = await this.io.open(uri, true, create); }
      catch (error) {
        if (candidate) throw error as Error;
        file = await this.io.open(uri, false, false);
        target.writable = false;
      }
      const snapshot = await file.snapshot();
      // 另存为的新文件只接收空对象；避免无 EXCL 的提供方创建时竞态覆盖已有内容。
      if (create && snapshot.bytes.length > 0) return markdownBlocked('unavailable');
      const decoded = this.io.decode(snapshot.bytes);
      target.baseline = snapshot.baseline;
      target.format = candidate ? format : decoded.format;
      grant.fileIdentity = snapshot.fileIdentity;
      const owner = this.registry.reserve(grant);
      if (owner) return { kind: 'occupied', sessionId: owner };
      await file.close();
      file = undefined;
      if (!candidate) this.current = grant;
      else this.trackCandidate(target);
      accepted = true;
      return { kind: candidate ? 'selected' : 'read', target: cloneMarkdownTarget(target), content: decoded.content };
    } catch (error) {
      return markdownBlocked(markdownErrorCode(error as MarkdownIOError));
    } finally {
      if (file) {
        try { await file.close(); } catch (error) { /* 尚未写入，只释放打开阶段的授权。 */ }
      }
      if (!accepted) this.registry.release(grant);
    }
  }

  private grant(request: MarkdownOperation, writing: boolean = false): MarkdownGrant | undefined {
    if (this.closed || request.sessionId !== this.sessionId || !validMarkdownId(request.operationId) ||
      !Number.isSafeInteger(request.targetGeneration) || !request.target) return undefined;
    const grant = this.registry.get(request.target.handle, this.sessionId);
    if (!grant || grant.target.identity !== request.target.identity || request.targetGeneration !== grant.generation) return undefined;
    if (writing && (!Number.isSafeInteger(request.revision) || request.revision < 0 ||
      typeof request.content !== 'string' ||
      !validMarkdownFormat(request.target.format) ||
      (grant.reservationId && request.reservationId !== grant.reservationId))) return undefined;
    return grant;
  }

  async read(request: MarkdownOperation): Promise<MarkdownReceipt> {
    const grant = this.grant(request);
    if (!grant || grant.pending) return markdownBlocked();
    let file: MarkdownFile | undefined;
    try {
      file = await this.io.open(grant.uri, false, false);
      const snapshot = await file.snapshot();
      if (snapshot.fileIdentity !== grant.fileIdentity) return markdownBlocked('identity-changed');
      const decoded = this.io.decode(snapshot.bytes);
      const target = cloneMarkdownTarget(grant.target);
      target.baseline = snapshot.baseline;
      target.format = decoded.format;
      // 重载是否应用由状态层票据决定；不改变尚未应用重载的编辑器所持格式。
      return { kind: 'read', content: decoded.content, target: target };
    } catch (error) { return markdownBlocked(markdownErrorCode(error as MarkdownIOError)); }
    finally { if (file) await file.close(); }
  }

  private serialize<T>(task: () => Promise<T>): Promise<T> {
    const pending = this.queue.then(task);
    this.queue = pending.then(() => {}, () => {});
    return pending;
  }

  private record(): MarkdownRecord { return this.store.read(this.sessionId); }
  private async verifyBinding(grant: MarkdownGrant, operation: MarkdownOperation): Promise<void> {
    this.unknownBinding = true;
    const saved = await this.store.reload(this.sessionId);
    if (saved.targetGeneration === grant.generation && saved.binding?.handle === grant.target.handle &&
      saved.binding?.identity === grant.target.identity && saved.journal?.operation.operationId === operation.operationId) {
      this.durableBinding = grant;
      this.unknownBinding = false;
    } else if (saved.targetGeneration === this.generation && saved.binding?.handle === this.current?.target.handle) {
      this.unknownBinding = false;
    }
  }

  reserve(request: MarkdownOperation): MarkdownReceipt {
    const grant = request.target ? this.registry.get(request.target.handle, this.sessionId) : undefined;
    if (!grant || !grant.reservationId || grant.pending || grant.generation !== this.generation + 1 || request.sessionId !== this.sessionId ||
      !validMarkdownId(request.operationId) || !validMarkdownFormat(request.format)) return markdownBlocked();
    for (const handle of this.candidates) {
      const other = this.registry.get(handle, this.sessionId);
      if (other && other !== grant && other.operationId) return markdownBlocked();
    }
    if (grant.operationId && grant.operationId !== request.operationId) return markdownBlocked();
    grant.operationId = request.operationId;
    grant.target.format = request.format;
    return { kind: 'reserved', reservation: { id: grant.reservationId, target: cloneMarkdownTarget(grant.target) } };
  }

  prepare(request: MarkdownPrepared): Promise<void> {
    return this.serialize(async () => {
      const grant = this.grant(request.operation, true);
      if (!grant || !grant.reservationId || grant.operationId !== request.operation.operationId) throw new Error('protocol');
      const record = this.record();
      record.binding = this.current?.target;
      record.updatedAt = Date.now();
      record.prepared = request;
      await this.store.write(record);
    });
  }

  write(request: MarkdownOperation): Promise<MarkdownReceipt> {
    return this.serialize(async () => {
      const grant = this.grant(request, true);
      if (!grant) return markdownBlocked();
      if (request.content.length > MARKDOWN_LIMIT) return markdownBlocked('size');
      if (this.unknownBinding || (this.durableBinding && this.durableBinding.generation > this.generation)) return markdownUncertain();
      if (!grant.target.writable) return markdownBlocked('readonly');
      if (grant.pending) return markdownUncertain();
      if (grant.reservationId && (grant.operationId !== request.operationId || grant.generation !== this.generation + 1 ||
        !this.sameOperation(request, this.record().prepared?.operation))) return markdownBlocked();
      let bytes: Uint8Array;
      let fingerprint: string;
      try { bytes = this.io.encode(request.content, request.target.format); fingerprint = this.fingerprint(request); }
      catch (error) { return markdownBlocked((error as Error).message === 'size' ? 'size' : 'encoding'); }
      const separator = request.operationId.lastIndexOf(':');
      const namespace = request.operationId.slice(0, separator);
      const sequence = Number(request.operationId.slice(separator + 1));
      if (separator < 0 || !Number.isSafeInteger(sequence) || sequence < 1) return markdownBlocked();
      if (namespace !== this.rendererNamespace) {
        if (!this.allowNewRenderer) return markdownBlocked();
        this.rendererNamespace = namespace;
        this.allowNewRenderer = false;
      }
      if (grant.operationNamespace !== namespace) {
        grant.operationNamespace = namespace;
        grant.highestSequence = -1;
      }
      if (grant.lastOperationId === request.operationId) {
        if (fingerprint !== grant.lastFingerprint) return markdownBlocked();
        return { kind: 'committed', baseline: grant.resultBaseline, durability: 'provider' };
      }
      if (sequence <= grant.highestSequence) return markdownBlocked();
      grant.highestSequence = sequence;
      let file: MarkdownFile | undefined;
      let attempted = false;
      let result: MarkdownReceipt = markdownBlocked('io');
      try {
        file = await this.io.open(grant.uri, true, false);
        const snapshot = await file.snapshot();
        if (snapshot.fileIdentity !== grant.fileIdentity) return markdownBlocked('identity-changed');
        if (snapshot.baseline !== request.expectedBaseline) return { kind: 'conflict', baseline: snapshot.baseline };
        const record = this.record();
        const original = this.io.decode(snapshot.bytes);
        record.journal = { operation: request, uri: grant.uri, original: original.content, originalFormat: original.format,
          baseline: snapshot.baseline, resultBaseline: this.io.digest(bytes), fileIdentity: snapshot.fileIdentity,
          attempted: true, committed: false };
        record.updatedAt = Date.now();
        // 原内容和待写内容在第一次破坏性调用前落盘；被系统终止也能恢复为副本。
        await this.store.write(record);
        const checked = await file.snapshot();
        if (!sameMarkdownVersion(snapshot, checked)) return { kind: 'conflict', baseline: checked.baseline };
        grant.pending = request;
        grant.committed = false;
        grant.original = snapshot;
        grant.resultBaseline = record.journal.resultBaseline;
        attempted = true;
        await file.truncate(0);
        let offset = 0;
        while (offset < bytes.length) {
          const count = await file.write(bytes.subarray(offset), offset);
          if (!Number.isInteger(count) || count <= 0 || count > bytes.length - offset) throw new Error('short write');
          offset += count;
        }
        await file.truncate(bytes.length);
        await file.sync();
        const written = await file.snapshot();
        if (written.baseline !== grant.resultBaseline || written.fileIdentity !== snapshot.fileIdentity) throw new Error('verify');
        await file.close();
        file = undefined;
        // 关闭可能是远端提供方提交点，再以新描述符读回确认。
        const verification = await this.io.open(grant.uri, false, false);
        let finalSnapshot: MarkdownSnapshot;
        try { finalSnapshot = await verification.snapshot(); } finally { await verification.close(); }
        if (finalSnapshot.baseline !== grant.resultBaseline || finalSnapshot.fileIdentity !== snapshot.fileIdentity) throw new Error('verify');
        grant.target.baseline = finalSnapshot.baseline;
        grant.target.format = request.target.format;
        grant.committed = true;
        record.journal.committed = true;
        await this.store.write(record);
        grant.lastOperationId = request.operationId;
        grant.lastRevision = request.revision;
        grant.lastFingerprint = fingerprint;
        if (!grant.reservationId) { grant.pending = undefined; grant.original = undefined; }
        result = { kind: 'committed', baseline: finalSnapshot.baseline, durability: 'provider' };
      } catch (error) {
        result = attempted ? markdownUncertain() : markdownBlocked(markdownErrorCode(error as MarkdownIOError));
      } finally {
        if (file) {
          try { await file.close(); } catch (error) { if (attempted) result = markdownUncertain(); }
        }
      }
      return result;
    });
  }

  reconcile(request: MarkdownOperation): Promise<MarkdownReceipt> {
    return this.serialize(async () => {
      const grant = this.grant(request, true);
      if (!grant || !this.sameOperation(request, grant.pending) || !grant.original) return markdownBlocked();
      if (this.unknownBinding) {
        try { await this.verifyBinding(grant, request); } catch (error) { return markdownUncertain(); }
        if (this.unknownBinding) return markdownUncertain();
      }
      let file: MarkdownFile | undefined;
      try {
        file = await this.io.open(grant.uri, false, false);
        const snapshot = await file.snapshot();
        await file.close();
        file = undefined;
        if (snapshot.fileIdentity !== grant.fileIdentity) return markdownUncertain();
        if (snapshot.baseline === grant.resultBaseline) {
          const record = this.record();
          if (record.journal) record.journal.committed = true;
          await this.store.write(record);
          grant.target.baseline = snapshot.baseline;
          grant.target.format = request.target.format;
          grant.committed = true;
          grant.lastOperationId = request.operationId;
          grant.lastRevision = request.revision;
          grant.lastFingerprint = this.fingerprint(request);
          if (!grant.reservationId) { grant.pending = undefined; grant.original = undefined; }
          return { kind: 'committed', baseline: snapshot.baseline, durability: 'provider' };
        }
        if (sameMarkdownVersion(snapshot, grant.original)) {
          grant.pending = undefined;
          grant.original = undefined;
          return markdownBlocked('io');
        }
      } catch (error) { /* 不确定时保留登记与恢复日志，不重发写入。 */ }
      finally { if (file) { try { await file.close(); } catch (error) {} } }
      return markdownUncertain();
    });
  }

  commit(request: MarkdownCommit): Promise<MarkdownReceipt> {
    return this.serialize(async () => {
      const grant = this.grant(request.operation, true);
      if (!grant || !grant.committed || request.receipt.kind !== 'committed' ||
        request.receipt.baseline !== grant.target.baseline || request.nextTargetGeneration !== grant.generation) return markdownBlocked();
      if (this.current === grant && !grant.reservationId) {
        if (this.fingerprint(request.operation) !== grant.lastFingerprint) return markdownBlocked();
        return { kind: 'committed', target: cloneMarkdownTarget(grant.target) };
      }
      if (grant.generation !== this.generation + 1 || !this.sameOperation(request.operation, grant.pending)) return markdownBlocked();
      if (this.unknownBinding) {
        try { await this.verifyBinding(grant, request.operation); } catch (error) { return markdownUncertain(); }
        if (this.unknownBinding) return markdownUncertain();
      }
      const record = this.record();
      record.binding = cloneMarkdownTarget(grant.target);
      record.targetGeneration = grant.generation;
      record.revision = Math.max(record.revision, request.operation.revision);
      // 新输入可能已在旧目标代次的草稿中持久化；绑定提交不能降低它的水位。
      if (record.draft && record.draft.revision > request.operation.revision) {
        record.draft.targetGeneration = grant.generation;
        record.draft.target = cloneMarkdownTarget(grant.target);
        record.draft.format = grant.target.format;
      }
      record.updatedAt = Date.now();
      try { await this.store.write(record); }
      catch (error) {
        // AtomicFile 可能已替换文件再报告失败；必须读回真实记录，不能继续使用旧缓存确认草稿。
        try { await this.verifyBinding(grant, request.operation); } catch (ignored) { this.unknownBinding = true; }
        return markdownUncertain();
      }
      this.durableBinding = grant;
      this.unknownBinding = false;
      const previous = this.current;
      this.current = grant;
      this.generation = grant.generation;
      grant.reservationId = '';
      grant.pending = undefined;
      grant.original = undefined;
      this.candidates.delete(grant.target.handle);
      if (previous && previous !== grant) this.registry.release(previous);
      return { kind: 'committed', target: cloneMarkdownTarget(grant.target) };
    });
  }

  releaseCandidate(handle: string): void {
    const grant = this.registry.get(handle, this.sessionId);
    if (grant && grant !== this.current && this.registry.release(grant)) this.candidates.delete(handle);
  }
  releaseReservation(reservationId: string, operationId: string): void {
    // 仅页面持有的候选句柄能被取消；写入开始后 pending 会阻止释放。
    for (const record of this.candidates) {
      const grant = this.registry.get(record, this.sessionId);
      if (grant?.reservationId === reservationId && grant.operationId === operationId) this.releaseCandidate(record);
    }
  }
  private candidates: Set<string> = new Set();
  trackCandidate(target: MarkdownTarget): void { this.candidates.add(target.handle); }

  private sameOperation(left: MarkdownOperation, right: MarkdownOperation | undefined): boolean {
    return right !== undefined && this.fingerprint(left) === this.fingerprint(right);
  }
  private fingerprint(request: MarkdownOperation): string {
    // 请求转义最多把正文扩张六倍，指纹预算独立于恢复正文预算，并在任何写入前校验。
    return this.io.digest(this.io.encode(JSON.stringify(request), { bom: false, newline: '\n' }, 64 * 1024 * 1024));
  }

  putDraft(request: MarkdownOperation): Promise<void> {
    return this.serialize(async () => {
      if (this.closed || request.sessionId !== this.sessionId || !validMarkdownId(request.operationId) ||
        typeof request.content !== 'string' || !validMarkdownFormat(request.format) ||
        !Number.isSafeInteger(request.revision) || request.revision < 0 || this.unknownBinding ||
        (request.targetGeneration !== this.generation && request.targetGeneration !== (this.durableBinding?.generation ?? -1) - 1)) throw new Error('protocol');
      this.io.encode(request.content, request.format, MARKDOWN_RECOVERY_CONTENT_LIMIT);
      const draft = JSON.parse(JSON.stringify(request)) as MarkdownOperation;
      if (this.durableBinding && draft.targetGeneration === this.durableBinding.generation - 1) {
        draft.targetGeneration = this.durableBinding.generation;
        draft.target = cloneMarkdownTarget(this.durableBinding.target);
        draft.format = this.durableBinding.target.format;
      }
      const record = this.record();
      if (draft.targetGeneration < record.targetGeneration) throw new Error('unconfirmed binding');
      if (draft.targetGeneration === record.targetGeneration && draft.revision <= record.revision) return;
      record.targetGeneration = draft.targetGeneration;
      record.revision = draft.revision;
      record.draft = draft;
      record.displayName = this.current?.target.displayName ?? '';
      record.updatedAt = Date.now();
      await this.store.write(record);
    });
  }
  clearDraft(request: MarkdownWatermark): Promise<void> {
    return this.serialize(async () => {
      if (this.closed || this.unknownBinding || request.sessionId !== this.sessionId || request.targetGeneration !== this.generation ||
        !Number.isSafeInteger(request.revision) || request.revision < 0) throw new Error('protocol');
      const record = this.record();
      if (record.targetGeneration > request.targetGeneration ||
        (record.targetGeneration === request.targetGeneration && record.revision > request.revision)) return;
      record.revision = request.revision;
      record.targetGeneration = request.targetGeneration;
      record.draft = undefined;
      if (!this.current?.pending) record.journal = undefined;
      if (record.prepared && record.prepared.operation.targetGeneration <= request.targetGeneration &&
        record.prepared.operation.revision <= request.revision) record.prepared = undefined;
      await this.store.write(record);
    });
  }
  async release(): Promise<void> {
    await this.queue;
    if (!this.registry.releaseOwner(this.sessionId)) throw new Error('indeterminate');
    this.closed = true;
  }
}
