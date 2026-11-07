import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WatchlistStore } from '../store/WatchlistStore';
import { SettingsStore } from '../store/SettingsStore';
import { CloudSync } from '../store/CloudSync';
import { ThemeColors, ThemeNavParam, themeColors, themeName } from '../model/Theme';

/**
 * 个人中心：华为账号登录、自选股云同步（AGC）、主题入口、关于。
 * 未配置 AGC 时登录/同步失败均有友好提示，不影响其他功能。
 */
@Component
export struct PersonalPage {
  @State isLogged: boolean = false;
  @State isBusy: boolean = false;
  @State accountName: string = '';
  @State syncStatus: string = '';
  @State lastSyncTime: string = '';
  @State aiBaseUrl: string = '';
  @State aiApiKey: string = '';
  @State aiModel: string = '';
  @State aiSaving: boolean = false;
  @State aiStatus: string = '';
  @State aiStatusOk: boolean = true;
  @StorageLink('theme_index') themeIndex: number = 0;
  navPathStack: NavPathStack = new NavPathStack();
  onWatchlistSynced: () => void = () => {
  };
  private openId: string = '';
  private avatarGradColors: Array<[ResourceColor, number]> =
    [['#4E9CF8', 0], ['#2A5BD7', 1]];

  aboutToAppear(): void {
    this.initAccount();
    this.initSyncTime();
    this.initAiConfig();
  }

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  /**
   * 进入页面先静默检查华为账号登录态（不拉起登录页）。
   */
  private async initAccount(): Promise<void> {
    try {
      this.openId = await CloudSync.login(this.ctx(), false);
      this.isLogged = true;
      this.accountName = '华为用户';
      CloudSync.fetchNickname(this.ctx()).then((name: string) => {
        this.accountName = name;
      }).catch(() => {
      });
    } catch (error) {
      this.isLogged = false;
    }
  }

  private async initSyncTime(): Promise<void> {
    try {
      this.lastSyncTime = await SettingsStore.loadLastSyncTime(this.ctx());
    } catch (error) {
      this.lastSyncTime = '';
    }
  }

  private async initAiConfig(): Promise<void> {
    try {
      const context: common.Context = this.ctx();
      this.aiBaseUrl = await SettingsStore.loadAiBaseUrl(context);
      this.aiApiKey = await SettingsStore.loadAiApiKey(context);
      this.aiModel = await SettingsStore.loadAiModel(context);
    } catch (error) {
      // 保持默认值
    }
  }

  private async saveAiConfig(): Promise<void> {
    if (this.aiSaving) {
      return;
    }
    this.aiSaving = true;
    try {
      const context: common.Context = this.ctx();
      await SettingsStore.saveAiBaseUrl(context, this.aiBaseUrl.trim());
      await SettingsStore.saveAiApiKey(context, this.aiApiKey.trim());
      await SettingsStore.saveAiModel(context, this.aiModel.trim());
      this.aiStatus = 'AI 配置已保存，个股详情页可使用 AI 解读';
      this.aiStatusOk = true;
    } catch (error) {
      this.aiStatus = 'AI 配置保存失败，请重试';
      this.aiStatusOk = false;
    }
    this.aiSaving = false;
  }

  private aiStatusColor(): string {
    if (this.aiStatusOk) {
      return '#1DBF60';
    }
    return '#FF6B6B';
  }

  private avatarChar(): string {
    if (this.accountName !== '') {
      return this.accountName.charAt(0);
    }
    return '我';
  }

  private accountSubText(): string {
    if (this.isLogged) {
      return '已登录 · 自选股可云同步';
    }
    return '未登录 · 登录后可同步自选股';
  }

  private statusColor(): string {
    if (this.syncStatus.indexOf('失败') >= 0 || this.syncStatus.indexOf('请先') >= 0) {
      return '#FF6B6B';
    }
    return '#1DBF60';
  }

  private async doLogin(): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    this.syncStatus = '';
    try {
      this.openId = await CloudSync.login(this.ctx(), true);
      this.isLogged = true;
      try {
        this.accountName = await CloudSync.fetchNickname(this.ctx());
      } catch (error) {
        this.accountName = '华为用户';
      }
      this.syncStatus = '登录成功';
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      this.syncStatus = '登录失败：' + (err.message ?? '未知错误')
        + '（code ' + err.code + '）。需配置 AGC（client_id + 签名），且需真机。';
    }
    this.isBusy = false;
  }

  private logout(): void {
    this.isLogged = false;
    this.openId = '';
    this.accountName = '';
    this.syncStatus = '已退出登录';
  }

  private async doUpload(): Promise<void> {
    if (!this.isLogged) {
      this.syncStatus = '请先登录华为账号';
      return;
    }
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      const codes: string[] = await WatchlistStore.loadCodes(this.ctx());
      if (codes.length === 0) {
        this.syncStatus = '本地自选股为空，未上传';
        this.isBusy = false;
        return;
      }
      await CloudSync.uploadWatchlist(this.ctx(), this.openId, codes);
      this.lastSyncTime = this.nowText();
      SettingsStore.saveLastSyncTime(this.ctx(), this.lastSyncTime).catch(() => {
      });
      this.syncStatus = '已上传 ' + codes.length + ' 只自选股到云端';
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      this.syncStatus = '上传失败：' + (err.message ?? '未知错误')
        + '（code ' + err.code + '）。需在 AGC 开通云数据库并配置签名。';
    }
    this.isBusy = false;
  }

  private async doDownload(): Promise<void> {
    if (!this.isLogged) {
      this.syncStatus = '请先登录华为账号';
      return;
    }
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      const remoteCodes: string[] =
        await CloudSync.downloadWatchlist(this.ctx(), this.openId);
      if (remoteCodes.length === 0) {
        this.syncStatus = '云端暂无同步数据';
        this.isBusy = false;
        return;
      }
      const localCodes: string[] = await WatchlistStore.loadCodes(this.ctx());
      const merged: string[] = localCodes.slice();
      let added: number = 0;
      for (const c of remoteCodes) {
        if (merged.indexOf(c) < 0) {
          merged.push(c);
          added++;
        }
      }
      await WatchlistStore.saveCodes(this.ctx(), merged);
      this.lastSyncTime = this.nowText();
      SettingsStore.saveLastSyncTime(this.ctx(), this.lastSyncTime).catch(() => {
      });
      this.syncStatus = '已从云端恢复：新增 ' + added + ' 只，共 ' + merged.length + ' 只';
      this.onWatchlistSynced();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      this.syncStatus = '恢复失败：' + (err.message ?? '未知错误')
        + '（code ' + err.code + '）。需在 AGC 开通云数据库并配置签名。';
    }
    this.isBusy = false;
  }

  private nowText(): string {
    const d: Date = new Date();
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    const mm: number = d.getMonth() + 1;
    const dd: number = d.getDate();
    const hStr: string = h < 10 ? '0' + h : '' + h;
    const mStr: string = m < 10 ? '0' + m : '' + m;
    const mmStr: string = mm < 10 ? '0' + mm : '' + mm;
    const ddStr: string = dd < 10 ? '0' + dd : '' + dd;
    return d.getFullYear() + '-' + mmStr + '-' + ddStr + ' ' + hStr + ':' + mStr;
  }

  private lastSyncText(): string {
    if (this.lastSyncTime === '') {
      return '上次同步：尚未同步';
    }
    return '上次同步：' + this.lastSyncTime;
  }

  private openThemeSetting(): void {
    this.navPathStack.pushPathByName('ThemeSetting', new ThemeNavParam());
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text('个人中心')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.t().textPrimary)
          Blank()
        }
        .width('100%')

        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Text(this.avatarChar())
              .width(48)
              .height(48)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .linearGradient({ angle: 135, colors: this.avatarGradColors })
              .borderRadius(24)

            Column() {
              Text(this.isLogged ? this.accountName : '未登录')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.t().textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.accountSubText())
                .fontSize(11)
                .fontColor(this.t().textTertiary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.isLogged) {
              Text('退出')
                .fontSize(13)
                .fontColor(this.t().textSecondary)
                .padding({ left: 10, top: 6, right: 10, bottom: 6 })
                .onClick(() => {
                  this.logout();
                })
            }
          }
          .width('100%')

          if (!this.isLogged) {
            Row() {
              if (this.isBusy) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color('#4E9CF8')
                  .margin({ right: 6 })
              }
              Button('登录华为账号', { type: ButtonType.Capsule })
                .height(36)
                .fontSize(14)
                .backgroundColor('#2A5BD7')
                .enabled(!this.isBusy)
                .onClick(() => {
                  this.doLogin();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.t().card)
        .borderRadius(12)

        Column({ space: 10 }) {
          Row() {
            Text('自选股云同步')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
            Blank()
            Text(this.lastSyncText())
              .fontSize(11)
              .fontColor(this.t().textTertiary)
          }
          .width('100%')

          Text('登录华为账号后可将自选股上传云端、跨设备恢复，换机不丢失。完整云同步需在 AGC 开通云数据库（对象类型 WatchlistRecord）并配置签名包。')
            .fontSize(11)
            .fontColor(this.t().textTertiary)
            .width('100%')

          Row({ space: 10 }) {
            Button('上传到云端', { type: ButtonType.Capsule })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .backgroundColor('#2A5BD7')
              .enabled(!this.isBusy)
              .onClick(() => {
                this.doUpload();
              })
            Button('从云端恢复', { type: ButtonType.Capsule })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .fontColor('#4E9CF8')
              .backgroundColor(this.t().inputBg)
              .enabled(!this.isBusy)
              .onClick(() => {
                this.doDownload();
              })
          }
          .width('100%')

          if (this.syncStatus !== '') {
            Text(this.syncStatus)
              .fontSize(12)
              .fontColor(this.statusColor())
              .width('100%')
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.t().card)
        .borderRadius(12)

        Column({ space: 10 }) {
          Row() {
            Text('AI 智能分析')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
            Blank()
            Text('DeepSeek 等兼容接口')
              .fontSize(11)
              .fontColor(this.t().textTertiary)
          }
          .width('100%')

          Text('配置 OpenAI 协议兼容的大模型平台（如 DeepSeek），配置后个股详情页提供 AI 解读。API Key 仅保存在本机，不会上传。')
            .fontSize(11)
            .fontColor(this.t().textTertiary)
            .width('100%')

          TextInput({ text: this.aiBaseUrl, placeholder: '接口地址，如 https://api.deepseek.com' })
            .fontSize(13)
            .height(40)
            .width('100%')
            .backgroundColor(this.t().inputBg)
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.aiBaseUrl = value;
            })

          TextInput({ text: this.aiApiKey, placeholder: 'API Key（如 sk-xxx）' })
            .type(InputType.Password)
            .fontSize(13)
            .height(40)
            .width('100%')
            .backgroundColor(this.t().inputBg)
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.aiApiKey = value;
            })

          TextInput({ text: this.aiModel, placeholder: '模型，如 deepseek-chat' })
            .fontSize(13)
            .height(40)
            .width('100%')
            .backgroundColor(this.t().inputBg)
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.aiModel = value;
            })

          Row() {
            Button('保存配置', { type: ButtonType.Capsule })
              .height(36)
              .fontSize(14)
              .backgroundColor('#2A5BD7')
              .enabled(!this.aiSaving)
              .onClick(() => {
                this.saveAiConfig();
              })
            Blank()
          }
          .width('100%')

          if (this.aiStatus !== '') {
            Text(this.aiStatus)
              .fontSize(12)
              .fontColor(this.aiStatusColor())
              .width('100%')
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.t().card)
        .borderRadius(12)

        Column() {
          Row() {
            Text('主题外观')
              .fontSize(15)
              .fontColor(this.t().textPrimary)
            Blank()
            Text(themeName(this.themeIndex))
              .fontSize(12)
              .fontColor(this.t().textTertiary)
            Text(' >')
              .fontSize(13)
              .fontColor(this.t().textTertiary)
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            this.openThemeSetting();
          })

          Divider()
            .color(this.t().inputBg)
            .strokeWidth(1)

          Row() {
            Text('关于')
              .fontSize(15)
              .fontColor(this.t().textPrimary)
            Blank()
            Text('股票分析 v1.0.0')
              .fontSize(12)
              .fontColor(this.t().textTertiary)
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.t().card)
        .borderRadius(12)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 120 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
