import { MarkdownFile } from './MarkdownTypes';

export interface MarkdownResourceStat { identity: string; symlink: boolean; directory: boolean; }
export interface MarkdownResourceIO {
  stat: (uri: string) => Promise<MarkdownResourceStat>;
  open: (uri: string) => Promise<MarkdownFile>;
}
export interface MarkdownResourceNode { uri: string; identity: string; }
export interface MarkdownResourceGrant {
  uri: string; generation: number; identity: string; ancestry: MarkdownResourceNode[]; mime: string;
}
export interface MarkdownImageIO {
  open: (uri: string, writable: boolean) => Promise<MarkdownFile>;
  digest: (bytes: Uint8Array) => string;
}

// 目标由宿主先预留；导入成功回执必须晚于关闭和重新打开核验。
export async function copyMarkdownImage(io: MarkdownImageIO, sourceURI: string, destinationURI: string,
  identity: string): Promise<string> {
  let file: MarkdownFile | undefined;
  try {
    file = await io.open(sourceURI, false);
    const source = (await file.snapshot()).bytes;
    await file.close();
    file = undefined;
    if (!markdownImageMime(source)) throw new Error('image format');
    file = await io.open(destinationURI, true);
    const before = await file.snapshot();
    if (before.bytes.length || before.fileIdentity !== identity) throw new Error('image target changed');
    let offset = 0;
    while (offset < source.length) {
      const count = await file.write(source.subarray(offset), offset);
      if (!Number.isInteger(count) || count <= 0 || count > source.length - offset) throw new Error('short image write');
      offset += count;
    }
    await file.truncate(source.length);
    await file.sync();
    await file.close();
    file = undefined;
    file = await io.open(destinationURI, false);
    const copied = await file.snapshot();
    if (copied.baseline !== io.digest(source) || copied.fileIdentity !== identity) throw new Error('image target changed');
    await file.close();
    file = undefined;
    return identity;
  } finally { if (file) await file.close(); }
}

export function markdownImageMime(bytes: Uint8Array): string {
  if (bytes.length >= 8 && bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 &&
    bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10) return 'image/png';
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'image/jpeg';
  if (bytes.length >= 6 && bytes[0] === 71 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 56 &&
    (bytes[4] === 55 || bytes[4] === 57) && bytes[5] === 97) return 'image/gif';
  if (bytes.length >= 12 && bytes[0] === 82 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 70 &&
    bytes[8] === 87 && bytes[9] === 69 && bytes[10] === 66 && bytes[11] === 80) return 'image/webp';
  if (bytes.length >= 14 && bytes[0] === 66 && bytes[1] === 77) return 'image/bmp';
  if (bytes.length >= 6 && bytes[0] === 0 && bytes[1] === 0 && bytes[2] === 1 && bytes[3] === 0) return 'image/x-icon';
  return '';
}

// token 绑定授权目录链和最终对象身份；每次实际读取都重核，而非仅在生成 URL 时检查。
export class MarkdownResourceAccess {
  private io: MarkdownResourceIO;
  constructor(io: MarkdownResourceIO) { this.io = io; }

  async capture(uri: string, root: string, generation: number, fileIdentity: string = ''): Promise<MarkdownResourceGrant> {
    if (!root && !fileIdentity) throw new Error('resource permission');
    const ancestry: MarkdownResourceNode[] = [];
    if (root) {
      if (!uri.startsWith(root + '/')) throw new Error('resource scope');
      let current = root;
      const paths = [root];
      const children = uri.slice(root.length + 1).split('/');
      children.pop();
      for (const part of children) { current += '/' + part; paths.push(current); }
      for (const path of paths) {
        const info = await this.io.stat(path);
        if (info.symlink || !info.directory) throw new Error('resource scope');
        ancestry.push({ uri: path, identity: info.identity });
      }
    }
    const info = await this.io.stat(uri);
    if (info.symlink || info.directory || (fileIdentity && info.identity !== fileIdentity)) throw new Error('resource identity');
    const grant: MarkdownResourceGrant = { uri: uri, generation: generation, identity: info.identity, ancestry: ancestry, mime: '' };
    const bytes = await this.read(grant, generation, true);
    grant.mime = markdownImageMime(bytes);
    if (!grant.mime) throw new Error('resource format');
    return grant;
  }

  private async validate(grant: MarkdownResourceGrant): Promise<void> {
    for (const node of grant.ancestry) {
      const current = await this.io.stat(node.uri);
      if (current.symlink || !current.directory || current.identity !== node.identity) throw new Error('resource scope');
    }
    const current = await this.io.stat(grant.uri);
    if (current.symlink || current.directory || current.identity !== grant.identity) throw new Error('resource identity');
  }

  async read(grant: MarkdownResourceGrant, generation: number, detecting: boolean = false): Promise<Uint8Array> {
    if (grant.generation !== generation) throw new Error('resource expired');
    await this.validate(grant);
    const file = await this.io.open(grant.uri);
    try {
      // 首次内容读取之前核验 fd 身份，祖先被替换也不能把其他文件内容发给页面。
      if (await file.fileIdentity() !== grant.identity) throw new Error('resource identity');
      await this.validate(grant);
      const snapshot = await file.snapshot();
      await this.validate(grant);
      if (snapshot.fileIdentity !== grant.identity || (!detecting && markdownImageMime(snapshot.bytes) !== grant.mime)) throw new Error('resource identity');
      return snapshot.bytes;
    } finally { await file.close(); }
  }
}
