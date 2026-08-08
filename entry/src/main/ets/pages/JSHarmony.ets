/*
 * SiYuan - From thought to insight, with agents
 * Copyright (c) 2020-present, b3log.org
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import { Utils } from './Utils';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import { BusinessError } from '@ohos.base';
import { emitter, pasteboard } from '@kit.BasicServicesKit';
import napi from 'libentry.so';
import { Want, WantAgent, wantAgent, wantConstant } from '@kit.AbilityKit';
import { fileUri, fileIo as fs, picker } from '@kit.CoreFileKit';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';

interface ExportFileResult {
  status: string;
  name?: string;
}

export interface SaveExportFileResultEventData {
  requestID: string;
  resultJSON: string;
}

let nativeTextSelectionMenuDisabled = false;

export function isNativeTextSelectionMenuDisabled(): boolean {
  return nativeTextSelectionMenuDisabled;
}

/**
 * JavaScript 接口。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.6.0.0, May 3, 2026
 * @since 3.1.14
 */
@Component
export struct JSHarmony {
  setNativeTextSelectionMenuDisabled(disabled: boolean): void {
    nativeTextSelectionMenuDisabled = disabled;
  }

  async cancelNotification(id: number) {
    try {
      await notificationManager.cancel(id);
    } catch (e) {
      // 忽略
    }
    try {
      await reminderAgentManager.cancelReminder(id);
    } catch (e) {
      // 忽略
    }
  }

  async sendNotification(channel: string, title: string, body: string, delayInSeconds: number) {
    try {
      const isAllowed = notificationManager.isNotificationEnabledSync();
      if (!isAllowed) {
        try {
          await notificationManager.requestEnableNotification(Utils.getContext());
        } catch (e) {
          hilog.error(0x0000, "siyuan", "request enable notification failed: " + e);
        }
        return -1;
      }
    } catch (e) {
      hilog.error(0x0000, "siyuan", "check notification enable failed: " + e);
      return -1;
    }

    if (delayInSeconds > 0) {
      let timer: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: delayInSeconds,
        title: title,
        content: body,
        wantAgent: {
          pkgName: Utils.bundleName,
          abilityName: "EntryAbility"
        },
        ringDuration: 7,
        slotType: notificationManager.SlotType.SERVICE_INFORMATION
      };
      try {
        return await reminderAgentManager.publishReminder(timer);
      } catch (e) {
        hilog.error(0x0000, "siyuan", "publish reminder failed: " + e);
        return -1;
      }
    }

    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: Utils.bundleName,
          abilityName: 'EntryAbility',
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    let clickAgent: WantAgent = await wantAgent.getWantAgent(info);

    const id = Date.now();
    let request: notificationManager.NotificationRequest = {
      id: id,
      wantAgent: clickAgent,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: body, additionalText: '' }
      }
    };
    try {
      await notificationManager.publish(request);
      return id;
    } catch (e) {
      hilog.error(0x0000, "siyuan", "publish notification failed: " + e);
      return -1;
    }
  }

  showKeyboard() {
    emitter.emit("isFocusableTrue");
  }

  hideKeyboard() {
    emitter.emit("isFocusableFalse");
  }

  setWebViewFocusable(focusable: boolean) {
    if (focusable) {
      emitter.emit("isFocusableTrue");
    } else {
      emitter.emit("isFocusableFalse");
    }
  }

  exit() {
    Utils.exit();
  }

  returnDesktop() {
    const context = Utils.getContext();
    context.moveAbilityToBackground();
  }

  writeSiYuanHTMLClipboard(text: string, html: string, siyuanHTML: string) {
    try {
      const pasteData: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_HTML, html + "__@text/siyuan@__" + siyuanHTML);
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setDataSync(pasteData);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "failed to set PasteData. Cause: " + e.message);
    }
  }

  writeHTMLClipboard(text: string, html: string) {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_HTML, html);
      systemPasteboard.setDataSync(pasteData);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "failed to set PasteData. Cause: " + e.message);
    }
  }

  writeClipboard(text: string) {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      systemPasteboard.setDataSync(pasteData);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "failed to set PasteData. Cause: " + e.message);
    }
  }

  readClipboard(): string {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const result: pasteboard.PasteData = systemPasteboard.getDataSync();
      if (!result) {
        return "";
      }
      let ret = result.getPrimaryText();
      if (!ret) {
        ret = "";
      }
      return ret;
    } catch (e) {
      hilog.error(0x0000, "siyuan", "read clipboard failed: " + e);
      return ""
    }
  }

  readHTMLClipboard(): string {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const result: pasteboard.PasteData = systemPasteboard.getDataSync();
      let ret = result.getPrimaryHtml();
      if (!ret) {
        ret = "";
      }
      return ret;
    } catch (e) {
      hilog.error(0x0000, "siyuan", "read HTML clipboard failed: " + e);
      return ""
    }
  }

  readSiYuanHTMLClipboard(): string {
    try {
      const result = pasteboard.getSystemPasteboard().getDataSync();
      let html = result.getPrimaryHtml();
      const parts = html.split("__@text/siyuan@__");
      if (2 === parts.length) {
        return parts[1];
      }
      return "";
    } catch (e) {
      hilog.error(0x0000, "siyuan", "read siyuan HTML clipboard failed: " + e);
      return "";
    }
  }

  exportByDefault(url: string) {
    if (!url.startsWith("assets/")) {
      Utils.openByDefaultBrowser(url);
      return;
    }

    Utils.openByDefaultBrowser(url);
  }

  async saveExportFile(url: string) {
    await this.saveExportFileV2(url, "");
  }

  async saveExportFileV2(url: string, requestID: string) {
    if (!url) {
      this.notifyExportFileResult(requestID, "error");
      return;
    }

    let fileName = url.substring(url.lastIndexOf('/') + 1);
    const queryIdx = fileName.indexOf('?');
    if (-1 !== queryIdx) {
      fileName = fileName.substring(0, queryIdx);
    }
    try {
      fileName = decodeURIComponent(fileName);
    } catch (e) {
      hilog.warn(0x0000, "siyuan", "decode export file name failed: " + e);
    }
    if (!fileName) {
      fileName = "export";
    }
    let leaseId = "";
    let destinationUri = "";
    let copySucceeded = false;
    try {
      const leaseJSON = await napi.acquireExportFile(url);
      if (!leaseJSON) {
        napi.showMsg(napi.language(291), 5000);
        this.notifyExportFileResult(requestID, "error");
        return;
      }
      const lease = JSON.parse(leaseJSON) as Record<string, string | number>;
      leaseId = lease.leaseID as string;
      const srcPath = lease.path as string;
      const expectedSize = lease.size as number;
      if (lease.name) {
        fileName = lease.name as string;
      }
      if (!leaseId || !srcPath || typeof expectedSize !== "number" || expectedSize < 0) {
        napi.showMsg(napi.language(291), 5000);
        this.notifyExportFileResult(requestID, "error");
        return;
      }

      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [fileName];
      const documentPicker = new picker.DocumentViewPicker(Utils.getContext());
      const result = await documentPicker.save(documentSaveOptions);
      if (!result || result.length === 0) {
        hilog.info(0x0000, "siyuan", "User cancelled file save");
        this.notifyExportFileResult(requestID, "canceled");
        return;
      }

      let srcFd: number = -1;
      let dstFd: number = -1;
      let closeFailed = false;
      try {
        srcFd = fs.openSync(srcPath, fs.OpenMode.READ_ONLY).fd;
        const fileSize = fs.statSync(srcPath).size;
        if (fileSize !== expectedSize) {
          throw new Error("Export file size does not match its lease");
        }

        destinationUri = result[0];
        dstFd = fs.openSync(destinationUri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC).fd;
        const bufSize = 65536;
        const readBuf = new ArrayBuffer(bufSize);
        let readOffset = 0;
        let writtenSize = 0;
        while (readOffset < fileSize) {
          const chunkSize = Math.min(bufSize, fileSize - readOffset);
          const bytesRead = fs.readSync(srcFd, readBuf, { length: chunkSize });
          if (bytesRead <= 0) {
            break;
          }
          let chunkOffset = 0;
          while (chunkOffset < bytesRead) {
            const toWrite = chunkOffset === 0 && bytesRead === bufSize ?
              readBuf : readBuf.slice(chunkOffset, bytesRead);
            const bytesWritten = fs.writeSync(dstFd, toWrite);
            if (bytesWritten <= 0) {
              throw new Error("Export file write made no progress");
            }
            chunkOffset += bytesWritten;
            writtenSize += bytesWritten;
          }
          readOffset += bytesRead;
        }
        if (readOffset !== fileSize || writtenSize !== fileSize) {
          throw new Error("Incomplete export file copy");
        }
      } finally {
        if (-1 !== dstFd) {
          try {
            fs.closeSync(dstFd);
          } catch (closeErr) {
            closeFailed = true;
            hilog.error(0x0000, "siyuan", "saveExportFile destination close failed: " + closeErr);
          }
        }
        if (-1 !== srcFd) {
          try {
            fs.closeSync(srcFd);
          } catch (closeErr) {
            closeFailed = true;
            hilog.error(0x0000, "siyuan", "saveExportFile close failed: " + closeErr);
          }
        }
      }
      if (closeFailed) {
        throw new Error("Failed to close export file");
      }
      copySucceeded = true;
      this.notifyExportFileResult(requestID, "success", fileName);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "saveExportFile failed: " + e);
      if (destinationUri && !copySucceeded) {
        try {
          fs.unlinkSync(destinationUri);
        } catch (unlinkErr) {
          hilog.error(0x0000, "siyuan", "remove incomplete export file failed: " + unlinkErr);
        }
      }
      napi.showMsg(napi.language(290), 5000);
      this.notifyExportFileResult(requestID, "error");
    } finally {
      if (leaseId) {
        napi.releaseExportFile(leaseId);
      }
    }
  }

  private notifyExportFileResult(requestID: string, status: string, name: string = "") {
    if (!requestID) {
      return;
    }
    const result: ExportFileResult = { status: status };
    if (name) {
      result.name = name;
    }
    const eventData: emitter.GenericEventData<SaveExportFileResultEventData> = {
      data: {
        requestID: requestID,
        resultJSON: JSON.stringify(result)
      }
    };
    emitter.emit<SaveExportFileResultEventData>("saveExportFileResult", eventData);
  }

  async print(title: string, html: string) {
    const filename = title + ".pdf";
    try {
      await Utils.print(filename, html);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "print failed: " + e);
    }
  }

  async getScreenWidthPx(): Promise<number> {
    const context = Utils.getContext();
    const win = await window.getLastWindow(context);
    return win.getWindowProperties().windowRect.width;
  }

  openExternal(url: string) {
    if (!url.startsWith("assets/")) {
      Utils.openByDefaultBrowser(url);
      return;
    }

    // Support opening assets through other apps on HarmonyOS NEXT https://github.com/siyuan-note/siyuan/issues/15691
    const assetAbsPath = napi.getAssetAbsPath(url);
    if (!fs.accessSync(assetAbsPath)) {
      url = "http://127.0.0.1:6806/" + url;
      Utils.openByDefaultBrowser(url);
      return;
    }

    const uri = fileUri.getUriFromPath(assetAbsPath);
    const context = Utils.getContext();
    const wantInfo: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: uri,
      flags: wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION | wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    }
    context.startAbility(wantInfo);
    return;
  }

  openAuthURL(url: string) {
    if (!/^https?:\/\//i.test(url)) {
      hilog.error(0x0000, "siyuan", "open OIDC authorization URL failed: invalid URL");
      return;
    }
    Utils.openByDefaultBrowser(url);
  }

  getOIDCCallback(): string {
    const callback = AppStorage.get<string>("oidcCallback") ?? "";
    AppStorage.delete("oidcCallback");
    return callback;
  }

  changeStatusBarColor(color: string, appearanceMode: number) {
    if (Utils.isTablet() || Utils.isPC()) {
      return;
    }

    const context = Utils.getContext();
    window.getLastWindow(context).then((wnd: window.Window) => {
      try {
        const parsedColor = this.parseColor(color);
        hilog.info(0x0000, "siyuan",
          "change system bar [color=" + color + ", parsedColor=" + parsedColor + ", appearanceMode=" + appearanceMode +
            "]");
        wnd.setWindowSystemBarProperties({
          statusBarColor: parsedColor,
          statusBarContentColor: 0 !== appearanceMode ? "#ffffff" : "#000000",
          navigationBarColor: parsedColor,
          navigationBarContentColor: 0 !== appearanceMode ? "#ffffff" : "#000000",
        }).catch((e: BusinessError) => {
          hilog.error(0x0000, "siyuan", "set system bar failed: " + e);
        })
        wnd.setWindowBackgroundColor(parsedColor);
        wnd.setWindowLayoutFullScreen(false);

        setTimeout(() => {
          wnd.setSpecificSystemBarEnabled('status', true);
          wnd.setSpecificSystemBarEnabled('navigationIndicator', true);
        }, 256);
      } catch (e) {
        hilog.error(0x0000, "siyuan", "change system bar color failed: " + e);
      }
    });
  }

  private parseColor(color: string): string {
    try {
      color = color.trim();
      if (color.length !== 9 || color.charAt(0) !== '#') {
        throw new Error("invalid color format");
      }
      // Convert #RRGGBBAA to #AARRGGBB
      return "#" + color.substring(7, 9) + color.substring(1, 7);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "parse color [" + color + "] failed", e);
      return "#ffffffff";
    }
  }

  build() {
  }
}
