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

/**
 * JavaScript 接口。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.0, Nov 27, 2024
 * @since 3.1.14
 */
export class JSHarmony {
  openExternal(url: string) {
    if (!url) {
      return;
    }

    if (url.startsWith("#")) {
      return;
    }

    if (url.startsWith("assets/")) {
      url = "http://127.0.0.1:6806/" + url;
    }

    if (url.startsWith("/")) {
      url = "http://127.0.0.1:6806" + url;
    }

    Utils.openWithBrowser(url);
  }
}