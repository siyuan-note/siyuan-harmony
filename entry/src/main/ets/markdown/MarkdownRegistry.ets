import { MarkdownTarget, MarkdownOperation, MarkdownSnapshot } from './MarkdownTypes';

export class MarkdownGrant {
  uri: string = '';
  owner: string = '';
  target: MarkdownTarget;
  fileIdentity: string = '';
  reservationId: string = '';
  operationId: string = '';
  pending?: MarkdownOperation;
  original?: MarkdownSnapshot;
  resultBaseline: string = '';
  committed: boolean = false;
  lastOperationId: string = '';
  lastRevision: number = -1;
  lastFingerprint: string = '';
  operationNamespace: string = '';
  highestSequence: number = -1;
  generation: number = 0;
  created: boolean = false;
  constructor(target: MarkdownTarget) { this.target = target; }
}

// 所有 Ability 共用登记表；URI 与真实文件身份都占用，检查和预留之间不能 await。
export class MarkdownRegistry {
  private grants: Map<string, MarkdownGrant> = new Map();
  private owners: Map<string, string> = new Map();

  reserve(grant: MarkdownGrant): string {
    const keys: string[] = ['uri:' + grant.uri];
    if (grant.fileIdentity) keys.push('file:' + grant.fileIdentity);
    for (const key of keys) {
      const handle = this.owners.get(key);
      if (handle && handle !== grant.target.handle) return this.grants.get(handle)?.owner ?? grant.owner;
    }
    this.grants.set(grant.target.handle, grant);
    for (const key of keys) this.owners.set(key, grant.target.handle);
    return '';
  }

  get(handle: string, owner: string): MarkdownGrant | undefined {
    const grant = this.grants.get(handle);
    return grant?.owner === owner ? grant : undefined;
  }

  release(grant: MarkdownGrant): boolean {
    if (grant.pending) return false;
    this.grants.delete(grant.target.handle);
    this.owners.forEach((handle: string, key: string) => {
      if (handle === grant.target.handle) this.owners.delete(key);
    });
    return true;
  }

  releaseOwner(owner: string): boolean {
    const grants = Array.from(this.grants.values()).filter((grant: MarkdownGrant) => grant.owner === owner);
    if (grants.some((grant: MarkdownGrant) => grant.pending !== undefined)) return false;
    grants.forEach((grant: MarkdownGrant) => this.release(grant));
    return true;
  }
  pending(owner: string): MarkdownGrant[] {
    return Array.from(this.grants.values()).filter((grant: MarkdownGrant) => grant.owner === owner && grant.pending !== undefined);
  }
}

export const markdownRegistry: MarkdownRegistry = new MarkdownRegistry();
