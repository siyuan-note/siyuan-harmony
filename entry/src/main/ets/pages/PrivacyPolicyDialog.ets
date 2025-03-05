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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI'
import { Utils } from './Utils'

/**
 * 隐私政策弹窗。
 *
 * 鸣谢 https://github.com/ansen666/PrivacyPolicy
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.1, Mar 4, 2025
 * @since 3.1.24
 */
@Component
export default struct PrivacyPolicyDialog {
  cancel = defaultCallback
  confirm = defaultCallback

  build() {
    Stack() {
      Column() {
        Text($r('app.string.simple_user_policy'))
          .fontSize(18)
          .fontColor($r('app.color.title_color'))
          .margin({ top: 30, bottom: 19 })

        Scroll() {
          Text() {
            Span($r('app.string.privacy_policy_start'))
            Span($r('app.string.user_agreement_two')).fontColor($r('app.color.mainColor')).onClick(() => {
              Utils.openByDefaultBrowser("https://b3log.org/siyuan/eula.html");
            })
            Span($r('app.string.and'))
            Span($r('app.string.privacy_policy_two')).fontColor($r('app.color.mainColor')).onClick(() => {
              Utils.openByDefaultBrowser("https://b3log.org/siyuan/privacy.html");
            })
          }.fontSize(16).fontColor($r('app.color.body_color')).margin({ left: 25, right: 25 })
        }.height(120)

        Column() {
          Button($r('app.string.disagree_privacy_policy')).onClick(() => {
            this.cancel();
          }).fontColor($r('app.color.other_color')).fontSize(15).backgroundColor(Color.Transparent)

          Button($r('app.string.agree_privacy_policy'))
            .onClick(() => {
              this.confirm();
            })
            .backgroundColor($r('app.color.start_main_color'))
            .fontColor($r('app.color.white'))
            .fontSize(17)
            .width('80%')
            .margin({ top: 15, bottom: 21 })
        }
      }.backgroundColor($r('app.color.white')).borderRadius(13).width('80%')
    }.width('100%').height('100%').backgroundColor("#4D000000") // 黑色背景 透明度约为 30%
  }
}

function defaultCallback(): void {
}