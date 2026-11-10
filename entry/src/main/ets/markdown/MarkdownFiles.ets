import { newMarkdownId, newMarkdownToken } from './MarkdownIds';
import { fileIo as fs, fileShare, fileUri, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import { MarkdownFile, MarkdownIO, MarkdownSnapshot, MarkdownDecoded, MarkdownFormat, MarkdownStore,
  MarkdownRecord, MarkdownOperation, MARKDOWN_LIMIT, MARKDOWN_IMAGE_LIMIT, MARKDOWN_RECOVERY_LIMIT,
  MARKDOWN_RECOVERY_CONTENT_LIMIT, validMarkdownId, validMarkdownFormat } from './MarkdownTypes';

export function markdownFileIdentity(stat: fs.Stat, uri: string): string {
  const authority = uri.slice(0, uri.indexOf('/', 7));
  return stat.ino > 0 ? authority + ':' + String(stat.ino) : uri;
}
function version(stat: fs.Stat, uri: string): string {
  return markdownFileIdentity(stat, uri) + ':' + stat.size + ':' + String(stat.mtimeNs ?? stat.mtime) + ':' + String(stat.ctimeNs ?? stat.ctime);
}
function digest(bytes: Uint8Array): string {
  const stream: hash.HashStream = hash.createHash('sha256');
  stream.update(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  return stream.digest();
}

class HarmonyMarkdownFile implements MarkdownFile {
  private file: fs.File;
  private closed: boolean = false;
  private uri: string;
  private limit: number;
  constructor(file: fs.File, uri: string, limit: number = MARKDOWN_LIMIT) { this.file = file; this.uri = uri; this.limit = limit; }
  async fileIdentity(): Promise<string> { return markdownFileIdentity(await fs.stat(this.file.fd), this.uri); }
  async snapshot(): Promise<MarkdownSnapshot> {
    const before: fs.Stat = await fs.stat(this.file.fd);
    if (!before.isFile()) throw new Error('unavailable');
    if (before.size < 0 || before.size > this.limit) throw new Error('size');
    const bytes = new Uint8Array(before.size);
    let offset = 0;
    while (offset < bytes.length) {
      const chunk = new ArrayBuffer(Math.min(65536, bytes.length - offset));
      const count: number = await fs.read(this.file.fd, chunk, { offset: offset, length: chunk.byteLength });
      if (count <= 0 || count > chunk.byteLength) throw new Error('short read');
      bytes.set(new Uint8Array(chunk, 0, count), offset);
      offset += count;
    }
    const after: fs.Stat = await fs.stat(this.file.fd);
    if (version(before, this.uri) !== version(after, this.uri)) throw new Error('changed during read');
    return { bytes: bytes, baseline: digest(bytes), fileIdentity: markdownFileIdentity(after, this.uri) };
  }
  write(bytes: Uint8Array, offset: number): Promise<number> {
    return fs.write(this.file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), { offset: offset });
  }
  truncate(length: number): Promise<void> { return fs.truncate(this.file.fd, length); }
  sync(): Promise<void> { return fs.fsync(this.file.fd); }
  async close(): Promise<void> {
    if (this.closed) return;
    await fs.close(this.file);
    this.closed = true;
  }
}

export class HarmonyMarkdownIO implements MarkdownIO {
  async openResource(uri: string, writable: boolean = false): Promise<MarkdownFile> {
    const file: fs.File = await fs.open(uri, (writable ? fs.OpenMode.READ_WRITE : fs.OpenMode.READ_ONLY) | fs.OpenMode.NOFOLLOW);
    return new HarmonyMarkdownFile(file, uri, MARKDOWN_IMAGE_LIMIT);
  }
  async open(uri: string, writable: boolean, create: boolean): Promise<MarkdownFile> {
    const mode: number = writable ? fs.OpenMode.READ_WRITE : fs.OpenMode.READ_ONLY;
    const file: fs.File = await fs.open(uri, mode | fs.OpenMode.NOFOLLOW | (create ? fs.OpenMode.CREATE : 0));
    return new HarmonyMarkdownFile(file, uri);
  }
  decode(bytes: Uint8Array): MarkdownDecoded {
    if (bytes.length > MARKDOWN_LIMIT) throw new Error('size');
    let content: string;
    try { content = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes); }
    catch (error) { throw new Error('encoding'); }
    if (content.includes('\u0000')) throw new Error('encoding');
    const bom = bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf;
    if (bom && content.charCodeAt(0) === 0xfeff) content = content.slice(1);
    const firstNewline = content.match(new RegExp("\\r\\n|\\r|\\n"));
    const format: MarkdownFormat = { bom: bom, newline: firstNewline ? firstNewline[0] : '\n' };
    return { content: content.replace(new RegExp("\\r\\n|\\r", "g"), '\n'), format: format };
  }
  encode(content: string, format: MarkdownFormat, maximum: number = MARKDOWN_LIMIT): Uint8Array {
    if (!validMarkdownFormat(format) || content.includes('\u0000')) throw new Error('encoding');
    for (let index = 0; index < content.length; index++) {
      const point = content.charCodeAt(index);
      if (point >= 0xd800 && point <= 0xdbff) {
        const next = content.charCodeAt(++index);
        if (!(next >= 0xdc00 && next <= 0xdfff)) throw new Error('encoding');
      } else if (point >= 0xdc00 && point <= 0xdfff) throw new Error('encoding');
    }
    const normalized = content.replace(new RegExp("\\r\\n|\\r|\\n", "g"), format.newline);
    const bytes: Uint8Array = new util.TextEncoder().encodeInto((format.bom ? '\ufeff' : '') + normalized);
    if (bytes.length > maximum) throw new Error('size');
    return bytes;
  }
  digest(bytes: Uint8Array): string { return digest(bytes); }
  newId(): string { return newMarkdownId(); }
  token(): string { return newMarkdownToken(); }
}

export function canonicalMarkdownURI(value: string): string {
  if (!value.startsWith('file://') || new RegExp("[\\u0000-\\u001f\\\\?#]").test(value)) throw new Error('invalid URI');
  const parsed: fileUri.FileUri = new fileUri.FileUri(value);
  const normalized: string = parsed.normalize().toString();
  const decoded = decodeURIComponent(normalized);
  if (new RegExp("\\/(?:\\.|\\.\\.)(?:\\/|$)").test(decoded) || new RegExp("[\\u0000-\\u001f\\\\?#]").test(decoded)) throw new Error('invalid URI');
  return normalized;
}

export async function persistMarkdownPermission(uri: string, writable: boolean): Promise<boolean> {
  if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) return false;
  const policy: fileShare.PolicyInfo = { uri: uri, operationMode: fileShare.OperationMode.READ_MODE |
    (writable ? fileShare.OperationMode.WRITE_MODE : 0) };
  try {
    await fileShare.persistPermission([policy]);
    await fileShare.activatePermission([policy]);
    const granted: boolean[] = await fileShare.checkPersistentPermission([policy]);
    return granted[0] === true;
  } catch (error) { return false; }
}

export async function activateMarkdownPermission(uri: string, writable: boolean): Promise<boolean> {
  if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) return false;
  try {
    await fileShare.activatePermission([{ uri: uri, operationMode: fileShare.OperationMode.READ_MODE |
      (writable ? fileShare.OperationMode.WRITE_MODE : 0) }]);
    return true;
  } catch (error) { return false; }
}

export function writeMarkdownAtomic(path: string, text: string): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const atomic: fs.AtomicFile = new fs.AtomicFile(path);
    let settled = false;
    const fail = (error: Error): void => {
      if (settled) return;
      settled = true;
      try { atomic.failWrite(); } catch (ignored) {}
      reject(error);
    };
    try {
      const stream: fs.WriteStream = atomic.startWrite();
      stream.on('error', () => fail(new Error('draft write failed')));
      stream.write(text, 'utf-8', () => {
        if (settled) return;
        try { atomic.finishWrite(); settled = true; resolve(); }
        catch (error) { fail(new Error((error as BusinessError).message)); }
      });
    } catch (error) { fail(new Error((error as BusinessError).message)); }
  });
}

export function markdownDirectory(context: common.UIAbilityContext): string {
  return context.filesDir + '/workspaces/home/.config/siyuan/markdown';
}

export class HarmonyMarkdownStore implements MarkdownStore {
  private directory: string;
  private records: Map<string, MarkdownRecord> = new Map();
  constructor(context: common.UIAbilityContext) {
    this.directory = markdownDirectory(context) + '/recovery';
    try { fs.mkdirSync(this.directory, true); } catch (error) {
      if ((error as BusinessError).code !== 13900015) throw new Error((error as BusinessError).message);
    }
    const names: string[] = fs.listFileSync(this.directory);
    for (const name of names) {
      if (!name.endsWith('.json') || !validMarkdownId(name.slice(0, -5))) continue;
      try {
        const data: ArrayBuffer = new fs.AtomicFile(this.directory + '/' + name).readFully();
        if (data.byteLength > MARKDOWN_RECOVERY_LIMIT / 2) throw new Error('recovery size');
        const record = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(data))) as MarkdownRecord;
        this.validate(record, name.slice(0, -5));
        this.records.set(record.sessionId, record);
      } catch (error) {
        // 不能把损坏的恢复记录当作空记录覆盖；初始化失败时原文件保持原样。
        throw new Error('recovery unavailable');
      }
    }
  }
  private validate(record: MarkdownRecord, sessionId: string): void {
    if (record.version !== 1 || record.sessionId !== sessionId || !Number.isSafeInteger(record.revision) ||
      record.revision < -1 || !Number.isSafeInteger(record.targetGeneration) || record.targetGeneration < 0) throw new Error('recovery format');
    const operations: MarkdownOperation[] = [];
    if (record.draft) operations.push(record.draft);
    if (record.prepared) operations.push(record.prepared.operation);
    if (record.journal) operations.push(record.journal.operation);
    const io = new HarmonyMarkdownIO();
    for (const operation of operations) {
      const format = operation.format ?? operation.target?.format;
      if (operation.sessionId !== sessionId || typeof operation.content !== 'string' || !format) throw new Error('recovery format');
      io.encode(operation.content, format, MARKDOWN_RECOVERY_CONTENT_LIMIT);
    }
  }
  read(sessionId: string): MarkdownRecord {
    if (!validMarkdownId(sessionId)) throw new Error('protocol');
    const record = this.records.get(sessionId);
    if (record) return JSON.parse(JSON.stringify(record)) as MarkdownRecord;
    return { version: 1, sessionId: sessionId, revision: -1, targetGeneration: 0, updatedAt: Date.now(), displayName: '' };
  }
  async reload(sessionId: string): Promise<MarkdownRecord> {
    if (!validMarkdownId(sessionId)) throw new Error('protocol');
    const data: ArrayBuffer = new fs.AtomicFile(this.directory + '/' + sessionId + '.json').readFully();
    if (data.byteLength > MARKDOWN_RECOVERY_LIMIT / 2) throw new Error('recovery size');
    const record = JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(data))) as MarkdownRecord;
    this.validate(record, sessionId);
    this.records.set(sessionId, record);
    return this.read(sessionId);
  }
  async write(record: MarkdownRecord): Promise<void> {
    if (!validMarkdownId(record.sessionId)) throw new Error('protocol');
    const text = JSON.stringify(record);
    let bytes = text.length * 2;
    this.records.forEach((other: MarkdownRecord, key: string) => { if (key !== record.sessionId) bytes += JSON.stringify(other).length * 2; });
    if (bytes > MARKDOWN_RECOVERY_LIMIT) throw new Error('recovery storage full');
    await writeMarkdownAtomic(this.directory + '/' + record.sessionId + '.json', text);
    this.records.set(record.sessionId, JSON.parse(text) as MarkdownRecord);
  }
  list(): MarkdownRecord[] { return Array.from(this.records.values()).map((value: MarkdownRecord) => this.read(value.sessionId)); }
  async remove(sessionId: string): Promise<void> {
    if (!validMarkdownId(sessionId)) throw new Error('protocol');
    new fs.AtomicFile(this.directory + '/' + sessionId + '.json').delete();
    this.records.delete(sessionId);
  }
}

export class MarkdownAssets {
  private static pending?: Promise<string>;
  static initialize(context: common.UIAbilityContext, versionCode: string): Promise<string> {
    if (!MarkdownAssets.pending) MarkdownAssets.pending = MarkdownAssets.extract(context, versionCode);
    return MarkdownAssets.pending;
  }
  private static async extract(context: common.UIAbilityContext, versionCode: string): Promise<string> {
    if (!new RegExp("^[0-9]+$").test(versionCode)) throw new Error('version');
    const root = context.cacheDir + '/markdown-runtime-' + versionCode;
    const parser = root + '/stage/protyle/js/lute/lute.min.js';
    const legacyParser = root + '/stage/build/markdown/vditor/dist/js/lute/lute.min.js';
    if (fs.accessSync(root + '/.ready') && fs.accessSync(parser) && !fs.accessSync(legacyParser)) return root;
    // Invalidate completion before extracting, including retries after a partial refresh.
    if (fs.accessSync(root + '/.ready')) await fs.unlink(root + '/.ready');
    fs.mkdirSync(root, true);
    const archive = root + '/app.zip';
    const file: fs.File = await fs.open(archive, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    try {
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync('app.zip');
      let offset = 0;
      while (offset < bytes.length) {
        const count: number = await fs.write(file.fd, bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.length));
        if (count <= 0) throw new Error('asset write');
        offset += count;
      }
      await fs.fsync(file.fd);
    } finally { await fs.close(file); }
    await zlib.decompressFile(archive, root);
    if (!fs.accessSync(root + '/stage/build/markdown/index.html')) throw new Error('Markdown assets unavailable');
    if (!fs.accessSync(parser)) throw new Error('Markdown parser unavailable');
    if (fs.accessSync(legacyParser)) await fs.unlink(legacyParser);
    await writeMarkdownAtomic(root + '/.ready', versionCode);
    await fs.unlink(archive);
    return root;
  }
}
