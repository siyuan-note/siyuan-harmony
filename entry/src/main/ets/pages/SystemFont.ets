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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import { text } from "@kit.ArkGraphics2D";
import { hilog } from "@kit.PerformanceAnalysisKit";

interface SystemFont {
  family: string;
  weight: number;
  displayName: string;
  aliases: string[];
  spacing: string;
}

interface SystemFontEntry {
  font: SystemFont;
  italic: boolean;
}

export async function loadSystemFonts(): Promise<string> {
  // ALL 包含系统预置和用户安装的字体，不受设备类型限制。
  const names = await text.getSystemFontFullNamesByType(text.SystemFontType.ALL);
  const entries = new Map<string, SystemFontEntry>();
  const uniqueNames = Array.from(new Set(names));
  for (let offset = 0; offset < uniqueNames.length; offset += 16) {
    await Promise.all(uniqueNames.slice(offset, offset + 16).map(async (name: string) => {
      try {
        const descriptor = await text.getFontDescriptorByFullName(name, text.SystemFontType.ALL);
        const family = descriptor.fontFamily?.trim() || "";
        if (!family || family.startsWith(".")) {
          return;
        }
        // 字体引擎的字重枚举为 0 到 8，转换为 CSS 的 100 到 900。
        const nativeWeight = descriptor.weight ?? text.FontWeight.W400;
        const weight = nativeWeight >= text.FontWeight.W100 && nativeWeight <= text.FontWeight.W900 ?
          (nativeWeight + 1) * 100 : 400;
        const aliases = [name, descriptor.fullName || "", descriptor.postScriptName || "", family]
          .filter((alias: string) => alias.length > 0);
        const font: SystemFont = {
          family: family,
          weight: weight,
          displayName: descriptor.fullName || name,
          aliases: Array.from(new Set(aliases)),
          spacing: descriptor.monoSpace ? "monospace" : ""
        };
        const key = family.toLowerCase() + "\n" + weight;
        const italic = descriptor.italic === 1;
        const current = entries.get(key);
        if (current) {
          font.aliases = Array.from(new Set(current.font.aliases.concat(font.aliases)));
          if (!current.italic || italic) {
            current.font.aliases = font.aliases;
            return;
          }
        }
        entries.set(key, { font: font, italic: italic });
      } catch (error) {
        // 单个字体的信息读取失败不影响其他字体。
        hilog.warn(0x0000, "siyuan", "read system font descriptor failed: " + name + ", " + error);
      }
    }));
  }
  const fonts = Array.from(entries.values()).map((entry: SystemFontEntry) => entry.font);
  fonts.sort((left: SystemFont, right: SystemFont) => left.displayName.localeCompare(right.displayName));
  return JSON.stringify(fonts);
}
