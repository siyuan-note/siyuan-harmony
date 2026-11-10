import { MarkdownRecord, MarkdownOperation, validMarkdownFormat } from './MarkdownTypes';

export function latestMarkdownRecovery(record: MarkdownRecord): MarkdownOperation | undefined {
  const candidates: MarkdownOperation[] = [];
  if (record.draft) candidates.push(record.draft);
  if (record.journal) candidates.push(record.journal.operation);
  if (record.prepared) candidates.push(record.prepared.operation);
  let latest: MarkdownOperation | undefined;
  for (const operation of candidates) {
    if (!operation) throw new Error('recovery format');
    const format = operation.format ?? operation.target?.format;
    if (typeof operation.content !== 'string' || !Number.isSafeInteger(operation.revision) ||
      operation.revision < 0 || !format || !validMarkdownFormat(format)) throw new Error('recovery format');
    if (!latest || operation.revision > latest.revision) latest = operation;
  }
  return latest;
}

interface RecoveryTransfer { recordId: string; expires: number; }

// 外部 Want 不能凭恢复记录 ID 读取私有草稿；只消费应用内明确操作创建的一次性票据。
export class MarkdownRecoveryTransfers {
  private grants: Map<string, RecoveryTransfer> = new Map();
  grant(token: string, recordId: string, now: number): void {
    this.grants.forEach((value: RecoveryTransfer, key: string) => { if (value.expires <= now) this.grants.delete(key); });
    if (this.grants.size >= 32) throw new Error('recovery busy');
    this.grants.set(token, { recordId: recordId, expires: now + 30000 });
  }
  consume(token: string, now: number): string {
    const grant = this.grants.get(token);
    this.grants.delete(token);
    if (!grant || grant.expires <= now) throw new Error('recovery unavailable');
    return grant.recordId;
  }
  cancel(token: string): void { this.grants.delete(token); }
}
