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

import PrivacyPolicyDialog from './PrivacyPolicyDialog';
import { Utils } from './Utils';

/**
 * 引导启动。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.1, Dec 18, 2024
 * @since 3.1.14
 */
@Entry
@Component
struct Agreement {
  build() {
    RelativeContainer() {
      Row({ space: 10 }) {
        Image($r('app.media.app_icon')).width(60).height(60)
        Column({ space: 5 }) {
          Text($r('app.string.app_name')).fontSize(22).fontColor($r('app.color.title_color'))
          Text($r('app.string.slogan')).fontSize(14).fontColor($r('app.color.other_color'))
        }.alignItems(HorizontalAlign.Start)
      }.alignRules({
        bottom: { anchor: "__container__", align: VerticalAlign.Bottom },
        middle: { anchor: '__container__', align: HorizontalAlign.Center }
      }).margin({
        bottom: 30
      })

      PrivacyPolicyDialog({
        cancel: this.onCancel,
        confirm: this.onAgree,
      })
    }.width('100%')
    .height('100%').backgroundColor($r('app.color.white'))
  }

  onCancel(): void {
    Utils.getContext().getApplicationContext().clearUpApplicationData();
  }

  onAgree(): void {
    this.getUIContext().getRouter().pushUrl({
      url: "pages/Main"
    });
  }
}