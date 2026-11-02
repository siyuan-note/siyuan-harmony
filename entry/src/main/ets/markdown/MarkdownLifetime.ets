export interface MarkdownParticipant {
  prepare: () => Promise<boolean>;
  cancel: () => void;
  close: () => Promise<boolean>;
}

// 主窗口的原生 exit 会终止整个进程；独立文档存活时先完成编辑器的退出协议。
export class MarkdownLifetime {
  private static participants: Map<string, MarkdownParticipant> = new Map();
  private static deferredWorkspaceExit?: () => Promise<void>;
  private static quitting: boolean = false;
  private static deferredExitInProgress: boolean = false;
  private static workspaceGeneration: number = 0;
  static workspaceOpened(): void {
    MarkdownLifetime.workspaceGeneration++;
    MarkdownLifetime.deferredWorkspaceExit = undefined;
    if (MarkdownLifetime.deferredExitInProgress) {
      MarkdownLifetime.deferredExitInProgress = false;
      MarkdownLifetime.quitting = false;
    }
  }
  static workspaceToken(): number { return MarkdownLifetime.workspaceGeneration; }
  static isCurrentWorkspace(token: number): boolean { return token === MarkdownLifetime.workspaceGeneration; }
  static add(id: string, participant: MarkdownParticipant): void {
    if (MarkdownLifetime.participants.has(id)) throw new Error('identifier collision');
    if (MarkdownLifetime.quitting) throw new Error('Markdown is closing');
    MarkdownLifetime.participants.set(id, participant);
  }
  static remove(id: string): void {
    MarkdownLifetime.participants.delete(id);
    if (MarkdownLifetime.participants.size === 0 && MarkdownLifetime.deferredWorkspaceExit) {
      const finish = MarkdownLifetime.deferredWorkspaceExit;
      MarkdownLifetime.deferredWorkspaceExit = undefined;
      MarkdownLifetime.deferredExitInProgress = true;
      MarkdownLifetime.quitting = true;
      void finish();
    }
  }
  // 文档切换不产生“零文档”的瞬间，否则待执行的工作空间退出会中断新文稿。
  static replace(previous: string, next: string): void {
    const participant = MarkdownLifetime.participants.get(previous);
    if (!participant) throw new Error('Markdown container unavailable');
    MarkdownLifetime.participants.set(next, participant);
    MarkdownLifetime.participants.delete(previous);
  }
  static hasDocuments(): boolean { return MarkdownLifetime.participants.size > 0; }
  static isActive(id: string): boolean { return MarkdownLifetime.participants.has(id); }
  static deferWorkspaceExit(finish: () => Promise<void>): boolean {
    if (!MarkdownLifetime.hasDocuments()) return false;
    const token = MarkdownLifetime.workspaceGeneration;
    MarkdownLifetime.deferredWorkspaceExit = async () => {
      if (MarkdownLifetime.isCurrentWorkspace(token)) await finish();
    };
    return true;
  }
  static async prepareQuit(): Promise<boolean> {
    if (MarkdownLifetime.quitting) return false;
    MarkdownLifetime.quitting = true;
    const participants = Array.from(MarkdownLifetime.participants.values());
    try {
      for (const participant of participants) {
        if (!await participant.prepare()) throw new Error('cancelled');
      }
      for (const participant of participants) {
        if (!await participant.close()) throw new Error('cancelled');
      }
      return true;
    } catch (error) {
      MarkdownLifetime.quitting = false;
      participants.forEach((value: MarkdownParticipant) => value.cancel());
      return false;
    }
  }
}
