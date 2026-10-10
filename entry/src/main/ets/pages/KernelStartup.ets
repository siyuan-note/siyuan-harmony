/*
 * SiYuan - From thought to insight, with agents
 * Copyright (c) 2020-present, b3log.org
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { hilog } from "@kit.PerformanceAnalysisKit";
import napi from "libentry.so";

export class KernelStartup {
  private pending?: Promise<boolean>;
  private started: boolean = false;

  hasStarted(): boolean {
    return this.started || !!napi.isHttpServing();
  }

  // 同一进程只启动一次内核，取消的页面不会继续执行初始化。
  async start(start: () => void, isActive: () => boolean, onWaiting: (waiting: boolean) => void): Promise<boolean> {
    while (this.pending) {
      await this.pending;
    }
    if (!isActive()) {
      return false;
    }
    if (this.hasStarted()) {
      return true;
    }

    const pending = this.waitForPort(start, isActive, onWaiting);
    this.pending = pending;
    try {
      return await pending;
    } finally {
      this.pending = undefined;
    }
  }

  private async waitForPort(start: () => void, isActive: () => boolean,
    onWaiting: (waiting: boolean) => void): Promise<boolean> {
    let checks = 0;
    try {
      while (isActive()) {
        if (napi.isKernelPortAvailable()) {
          if (!isActive()) {
            return false;
          }
          start();
          this.started = true;
          return true;
        }
        onWaiting(true);
        if (checks++ % 25 === 0) {
          hilog.info(0x0000, "siyuan", "waiting for the previous kernel to release port 6806");
        }
        await new Promise<void>(resolve => setTimeout(resolve, 200));
      }
      return false;
    } finally {
      onWaiting(false);
    }
  }
}

export const kernelStartup = new KernelStartup();
