export const MARKDOWN_LIMIT: number = 8 * 1024 * 1024;
export const MARKDOWN_ASSET_LIMIT: number = 16 * 1024 * 1024;
export const MARKDOWN_IMAGE_LIMIT: number = 32 * 1024 * 1024;
export const MARKDOWN_RECOVERY_LIMIT: number = 256 * 1024 * 1024;
export const MARKDOWN_RECOVERY_CONTENT_LIMIT: number = 16 * 1024 * 1024;
export const MARKDOWN_ORIGIN: string = 'https://siyuan-markdown.local';
export const MARKDOWN_PAGE: string = MARKDOWN_ORIGIN + '/stage/build/markdown/index.html';

export interface MarkdownFormat { bom: boolean; newline: string; }
export interface MarkdownCapabilities {
  persistentPermission: boolean; conditionalWrite: boolean; atomicReplace: boolean; coordinatedAccess: boolean;
}
export interface MarkdownTarget {
  handle: string; identity: string; displayName: string; baseline: string; writable: boolean;
  format: MarkdownFormat; capabilities: MarkdownCapabilities;
}
export interface MarkdownOperation {
  sessionId: string; operationId: string; targetGeneration: number; revision: number; content: string;
  target?: MarkdownTarget; expectedBaseline?: string; reservationId?: string; format?: MarkdownFormat;
}
export interface MarkdownReceipt {
  kind: string; baseline?: string; durability?: string; error?: MarkdownFailure; target?: MarkdownTarget;
  content?: string; reservation?: MarkdownReservation; sessionId?: string;
}
export interface MarkdownReservation { id: string; target: MarkdownTarget; }
export interface MarkdownFailure { code: string; recoverable: boolean; }
export interface MarkdownWatermark { sessionId: string; targetGeneration: number; revision: number; }
export interface MarkdownCommit {
  operation: MarkdownOperation; receipt: MarkdownReceipt; previousTarget?: MarkdownTarget; nextTargetGeneration: number;
}
export interface MarkdownPrepared { operation: MarkdownOperation; previousTarget?: MarkdownTarget; }
export interface MarkdownSnapshot { bytes: Uint8Array; baseline: string; fileIdentity: string; }
export interface MarkdownDecoded { content: string; format: MarkdownFormat; }
export interface MarkdownJournal {
  operation: MarkdownOperation; uri: string; original: string; originalFormat: MarkdownFormat; baseline: string;
  resultBaseline: string; fileIdentity: string; attempted: boolean; committed: boolean;
}
export interface MarkdownRecord {
  version: number; sessionId: string; revision: number; targetGeneration: number; updatedAt: number;
  displayName: string; draft?: MarkdownOperation; journal?: MarkdownJournal; binding?: MarkdownTarget; prepared?: MarkdownPrepared;
}
export interface MarkdownFile {
  fileIdentity(): Promise<string>;
  snapshot(): Promise<MarkdownSnapshot>;
  write(bytes: Uint8Array, offset: number): Promise<number>;
  truncate(length: number): Promise<void>;
  sync(): Promise<void>;
  close(): Promise<void>;
}
export interface MarkdownIO {
  open(uri: string, writable: boolean, create: boolean): Promise<MarkdownFile>;
  decode(bytes: Uint8Array): MarkdownDecoded;
  encode(content: string, format: MarkdownFormat, maximum?: number): Uint8Array;
  digest(bytes: Uint8Array): string;
  newId(): string;
  token(): string;
}
export interface MarkdownStore {
  read(sessionId: string): MarkdownRecord;
  reload(sessionId: string): Promise<MarkdownRecord>;
  write(record: MarkdownRecord): Promise<void>;
  list(): MarkdownRecord[];
  remove(sessionId: string): Promise<void>;
}
export interface MarkdownPreferences { mode: string; theme: string; fontSize: number; }
export interface MarkdownIOError { code?: number; message?: string; }
export interface MarkdownState { status: string; revision: number; savedRevision: number; draftRevision: number;
  targetGeneration: number; composing: boolean; }

export function markdownBlocked(code: string = 'protocol'): MarkdownReceipt {
  return { kind: 'blocked', error: { code: code, recoverable: code !== 'protocol' && code !== 'encoding' && code !== 'size' } };
}
export function markdownUncertain(): MarkdownReceipt {
  return { kind: 'indeterminate', error: { code: 'io', recoverable: true } };
}
export function markdownErrorCode(error: MarkdownIOError): string {
  if (error.message === 'size' || error.message === 'encoding') return error.message;
  if (error.code === 13900012) return 'permission';
  if (error.code === 13900025) return 'space';
  if (error.code === 13900044) return 'offline';
  if (error.code === 13900002) return 'deleted';
  return 'unavailable';
}
export function validMarkdownFormat(format: MarkdownFormat): boolean {
  return format !== undefined && typeof format.bom === 'boolean' && ['\n', '\r\n', '\r'].includes(format.newline);
}
export function cloneMarkdownTarget(target: MarkdownTarget): MarkdownTarget {
  return JSON.parse(JSON.stringify(target)) as MarkdownTarget;
}
export function validMarkdownId(id: string): boolean {
  return typeof id === 'string' && new RegExp("^[a-zA-Z0-9:_-]{1,160}$").test(id);
}
export function sameMarkdownVersion(left: MarkdownSnapshot, right: MarkdownSnapshot): boolean {
  return left.fileIdentity === right.fileIdentity && left.baseline === right.baseline;
}
