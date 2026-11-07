import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { THEME_IDS, ThemeColors, themeColors, themeName } from '../model/Theme';
import { SettingsStore } from '../store/SettingsStore';

const DOMAIN: number = 0x0004;
const TAG: string = 'ThemeSetting';

@Builder
export function ThemeSettingBuilder(): void {
  ThemeSetting()
}

/**
 * 背景主题选择页。选择后立即通过 AppStorage('theme_index') 同步到所有页面，
 * 并持久化到 Preferences。
 */
@Component
export struct ThemeSetting {
  @StorageLink('theme_index') themeIndex: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private selectTheme(id: number): void {
    this.themeIndex = id;
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    if (context !== null && context !== undefined) {
      SettingsStore.saveThemeId(context, id).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'saveThemeId failed: %{public}s', `${error.message}`);
      });
    }
  }

  private rowBorder(id: number): string {
    if (this.themeIndex === id) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        Text('选择背景主题，全应用即时生效')
          .fontSize(12)
          .fontColor(this.t().textTertiary)
          .width('100%')
          .padding({ left: 4, bottom: 2 })

        ForEach(THEME_IDS, (id: number) => {
          Row({ space: 12 }) {
            Column({ space: 8 }) {
              Text(themeName(id))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.t().textPrimary)
              Row({ space: 6 }) {
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(5)
                  .backgroundColor(themeColors(id).bg)
                  .border({ width: 1, color: this.t().textTertiary })
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(5)
                  .backgroundColor(themeColors(id).card)
                  .border({ width: 1, color: this.t().textTertiary })
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(5)
                  .backgroundColor(themeColors(id).inputBg)
                  .border({ width: 1, color: this.t().textTertiary })
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .backgroundColor(themeColors(id).textPrimary)
                Row()
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .backgroundColor(themeColors(id).textSecondary)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.themeIndex === id) {
              Text('当前')
                .fontSize(12)
                .fontColor('#4E9CF8')
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(this.t().card)
          .borderRadius(12)
          .border({ width: 1.5, color: this.rowBorder(id) })
          .onClick(() => {
            this.selectTheme(id);
          })
        }, (id: number) => id.toString())
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .backgroundColor(this.t().bg)
    }
    .title('背景主题')
    .backgroundColor(this.t().bg)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
    })
  }
}
