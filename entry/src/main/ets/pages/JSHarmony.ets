/*
 * SiYuan - 源于思考，饮水思源
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
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import { BusinessError } from '@ohos.base';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * JavaScript 接口。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.2.1.0, Mar 23, 2025
 * @since 3.1.14
 */
export class JSHarmony {
  returnDesktop() {
    const context = getContext() as common.UIAbilityContext;
    context.moveAbilityToBackground();
  }

  writeHTMLClipboard(text: string, html: string) {
    try {
      let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_HTML, html);
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setDataSync(pasteData);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "Failed to set PasteData. Cause: " + e.message);
    }
  }

  writeClipboard(text: string) {
    try {
      let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setDataSync(pasteData);
    } catch (e) {
      hilog.error(0x0000, "siyuan", "Failed to set PasteData. Cause: " + e.message);
    }
  }

  readClipboard(): string {
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let result: pasteboard.PasteData = systemPasteboard.getDataSync();
      if (!result) {
        return "";
      }
      let ret = result.getPrimaryText();
      if (!ret) {
        ret = "";
      }
      return ret;
    } catch (e) {
      hilog.error(0x0000, "siyuan", "Failed to get PasteData. Cause: " + e.message);
      return ""
    }
  }

  readHTMLClipboard(): string {
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let result: pasteboard.PasteData = systemPasteboard.getDataSync();
      let ret = result.getPrimaryHtml();
      if (!ret) {
        ret = "";
      }
      return ret;
    } catch (e) {
      hilog.error(0x0000, "siyuan", "Failed to get PasteData. Cause: " + e.message);
      return ""
    }
  }

  exportByDefault(url: string) {
    if (!url.startsWith("assets/")) {
      Utils.openByDefaultBrowser(url);
      return;
    }

    Utils.openByDefaultBrowser(url);
  }

  openExternal(url: string) {
    if (!url.startsWith("assets/")) {
      Utils.openByDefaultBrowser(url);
      return;
    }

    Utils.openByDefaultBrowser(url);
  }

  changeStatusBarColor(color: string, appearanceMode: number) {
    const context = getContext() as common.UIAbilityContext;
    window.getLastWindow(context).then((windowStyle: window.Window) => {
      try {
        const parsedColor = this.parseColor(color);
        hilog.info(0x0000, "siyuan",
          "Change statusbar [color=" + color + ", parsedColor=" + parsedColor + ", appearanceMode=" + appearanceMode +
            "]");
        windowStyle.setWindowSystemBarProperties({
          statusBarColor: parsedColor,
          statusBarContentColor: 0 !== appearanceMode ? "#ffffff" : "#000000",
        }).catch((error: BusinessError) => {
          hilog.error(0x0000, "siyuan", JSON.stringify(error))
        })
      } catch (e) {
        hilog.error(0x0000, "siyuan", JSON.stringify(e))
      }
    });
  }

  private parseColor(color: string): string {
    try {
      color = color.trim();
      if (color.toLowerCase().includes("rgb")) {
        const splitStr = color.substring(color.indexOf('(') + 1, color.indexOf(')'));
        const splitString = splitStr.split(",");
        const colorValues = splitString.map(value => parseInt(value.trim(), 10));
        return `rgb(${colorValues[0]}, ${colorValues[1]}, ${colorValues[2]})`;
      }
      if (color.length < 7) {
        // Convert 3-digit hex colors to 6-digit
        color = color.replace(/#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])/, "#$1$1$2$2$3$3");
      }
      if (color.length === 9 && color.charAt(0) === '#') {
        // Convert #RRGGBBAA to #AARRGGBB
        color = "#" + color.substring(7, 9) + color.substring(1, 7);
      }
      return color;
    } catch (e) {
      hilog.error(0x0000, "siyuan", "parse color [" + color + "] failed", e);
      return "#ffffff";
    }
  }
}