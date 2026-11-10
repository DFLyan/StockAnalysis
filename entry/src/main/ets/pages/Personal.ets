import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WatchlistStore } from '../store/WatchlistStore';
import { SettingsStore } from '../store/SettingsStore';
import { CloudSync } from '../store/CloudSync';
import { ReminderService } from '../store/ReminderService';
import { ALL_KLINE_LEVELS, KLineLevel, kLineLevelLabel } from '../model/StockModels';
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
  @State reminderEnabled: boolean = false;
  @State reminderInterval: number = 30;
  @State reminderLevels: KLineLevel[] = [KLineLevel.DAY];
  @State reminderDivType: string = 'all';
  @State reminderIntervalText: string = '';
  @State showCustomInterval: boolean = false;
  @State showLevelPanel: boolean = false;
  @State reminderStatus: string = '';
  @State showCloudSync: boolean = false;
  @State showAiConfig: boolean = false;
  @State showReminder: boolean = false;
  @StorageLink('theme_index') themeIndex: number = 0;
  navPathStack: NavPathStack = new NavPathStack();
  onWatchlistSynced: () => void = () => {
  };
  private openId: string = '';

  /** 头像渐变，跟随主题强调色。 */
  private avatarGradColors(): Array<[ResourceColor, number]> {
    return [[this.t().accentFrom, 0], [this.t().accentTo, 1]];
  }

  aboutToAppear(): void {
    this.initAccount();
    this.initSyncTime();
    this.initAiConfig();
    this.initReminder();
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

  private lastSyncSummary(): string {
    if (this.lastSyncTime === '') {
      return '尚未同步';
    }
    return '上次 ' + this.lastSyncTime.slice(5);
  }

  private aiConfigSummary(): string {
    if (this.aiBaseUrl.trim() !== '') {
      return '已配置';
    }
    return '未配置';
  }

  private openThemeSetting(): void {
    this.navPathStack.pushPathByName('ThemeSetting', new ThemeNavParam());
  }

  private async initReminder(): Promise<void> {
    try {
      const context: common.Context = this.ctx();
      this.reminderEnabled = await SettingsStore.loadReminderEnabled(context);
      this.reminderInterval = await SettingsStore.loadReminderIntervalMin(context);
      this.reminderLevels = await SettingsStore.loadReminderLevels(context);
      this.reminderDivType = await SettingsStore.loadReminderDivType(context);
      this.reminderIntervalText = this.reminderIntervalOptions().indexOf(this.reminderInterval) >= 0
        ? '' : `${this.reminderInterval}`;
      this.showCustomInterval =
        this.reminderIntervalOptions().indexOf(this.reminderInterval) < 0;
    } catch (error) {
      // 保持默认值
    }
  }

  private async setReminderEnabled(on: boolean): Promise<void> {
    if (on === this.reminderEnabled) {
      return;
    }
    const context: common.Context = this.ctx();
    if (on) {
      await ReminderService.ensureNotificationEnabled();
    } else {
      ReminderService.stop();
    }
    this.reminderEnabled = on;
    await SettingsStore.saveReminderEnabled(context, on);
    this.reminderStatus = on ? '背离提醒已开启，检测到新背离将发送系统通知' : '背离提醒已关闭';
    if (on) {
      ReminderService.restart(context).catch(() => {
      });
    }
  }

  private async toggleReminderLevel(level: KLineLevel): Promise<void> {
    const idx: number = this.reminderLevels.indexOf(level);
    if (idx >= 0) {
      if (this.reminderLevels.length <= 1) {
        return; // 至少保留一个级别
      }
      this.reminderLevels.splice(idx, 1);
    } else {
      this.reminderLevels.push(level);
    }
    const context: common.Context = this.ctx();
    await SettingsStore.saveReminderLevels(context, this.reminderLevels);
    // 检测范围变化后重建基线，只提醒之后新出现的背离
    await SettingsStore.saveReminderBaselineDone(context, false);
    if (this.reminderEnabled) {
      ReminderService.restart(context).catch(() => {
      });
    }
  }

  private isReminderLevelSelected(level: KLineLevel): boolean {
    return this.reminderLevels.indexOf(level) >= 0;
  }

  /** 级别行文案：单级别显示名称，多级别显示数量。 */
  private reminderLevelMenuLabel(): string {
    if (this.reminderLevels.length === 1) {
      return kLineLevelLabel(this.reminderLevels[0]);
    }
    return this.reminderLevels.length + '个级别';
  }

  private reminderDivTypeSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const option of this.reminderDivTypeOptions()) {
      const opt: SelectOption = { value: this.reminderDivTypeLabel(option) };
      opts.push(opt);
    }
    return opts;
  }

  private reminderDivTypeSelectedIndex(): number {
    return this.reminderDivTypeOptions().indexOf(this.reminderDivType);
  }

  private reminderDivTypeOptions(): string[] {
    return ['all', 'top', 'bottom'];
  }

  private reminderDivTypeLabel(option: string): string {
    if (option === 'top') {
      return '顶背离';
    }
    if (option === 'bottom') {
      return '底背离';
    }
    return '全部';
  }

  private async setReminderDivType(option: string): Promise<void> {
    if (option === this.reminderDivType) {
      return;
    }
    this.reminderDivType = option;
    const context: common.Context = this.ctx();
    await SettingsStore.saveReminderDivType(context, option);
    // 检测范围变化后重建基线，只提醒之后新出现的背离
    await SettingsStore.saveReminderBaselineDone(context, false);
    if (this.reminderEnabled) {
      ReminderService.restart(context).catch(() => {
      });
    }
  }

  private async setReminderInterval(minutes: number): Promise<void> {
    if (minutes === this.reminderInterval) {
      return;
    }
    this.reminderInterval = minutes;
    this.showCustomInterval =
      this.reminderIntervalOptions().indexOf(minutes) < 0;
    this.reminderIntervalText = this.showCustomInterval ? `${minutes}` : '';
    const context: common.Context = this.ctx();
    await SettingsStore.saveReminderIntervalMin(context, minutes);
    if (this.reminderEnabled) {
      ReminderService.restart(context).catch(() => {
      });
    }
  }

  /** 间隔下拉选择：预设档直接生效，"自定义"展开输入框。 */
  private onIntervalSelect(index: number): void {
    const options: number[] = this.reminderIntervalOptions();
    if (index >= options.length) {
      this.showCustomInterval = true;
      this.reminderIntervalText =
        options.indexOf(this.reminderInterval) >= 0 ? '' : `${this.reminderInterval}`;
      return;
    }
    this.setReminderInterval(options[index]);
  }

  private intervalSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const minutes of this.reminderIntervalOptions()) {
      const opt: SelectOption = { value: this.intervalLabel(minutes) };
      opts.push(opt);
    }
    const customOpt: SelectOption = { value: '自定义' };
    opts.push(customOpt);
    return opts;
  }

  private intervalSelectedIndex(): number {
    const idx: number = this.reminderIntervalOptions().indexOf(this.reminderInterval);
    if (idx >= 0) {
      return idx;
    }
    return this.reminderIntervalOptions().length;
  }

  private intervalValueText(): string {
    if (this.reminderIntervalOptions().indexOf(this.reminderInterval) >= 0) {
      return this.intervalLabel(this.reminderInterval);
    }
    return '自定义 ' + this.reminderInterval + '分钟';
  }

  private applyCustomInterval(): void {
    const raw: string = this.reminderIntervalText.trim();
    if (raw === '') {
      return;
    }
    const val: number = Number(raw);
    if (isNaN(val) || Math.floor(val) !== val || val < 1 || val > 240) {
      this.reminderStatus = '间隔需为 1-240 的整数分钟';
      return;
    }
    this.setReminderInterval(val);
  }

  private reminderIntervalOptions(): number[] {
    return [5, 15, 30, 60];
  }

  private intervalLabel(minutes: number): string {
    return minutes + '分钟';
  }

  private chipGrad(active: boolean): Array<[ResourceColor, number]> {
    if (active) {
      return [[this.t().accentFrom, 0], [this.t().accentTo, 1]];
    }
    return [[this.t().inputBg, 0], [this.t().inputBg, 1]];
  }

  private reminderStatusColor(): string {
    if (this.reminderStatus.indexOf('关闭') >= 0 || this.reminderStatus.indexOf('需为') >= 0) {
      return '#FF6B6B';
    }
    return '#1DBF60';
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
            Stack() {
              Column()
                .width(56)
                .height(56)
                .backgroundColor(this.t().inputBg)
                .borderRadius(28)
              Text(this.avatarChar())
                .width(48)
                .height(48)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .linearGradient({ angle: 135, colors: this.avatarGradColors() })
                .borderRadius(24)
            }

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
                  .color(this.t().accent)
                  .margin({ right: 6 })
              }
              Button('登录华为账号', { type: ButtonType.Capsule })
                .height(36)
                .fontSize(14)
                .backgroundColor(this.t().accentFrom)
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
        .padding(16)
        .backgroundColor(this.t().card)
        .borderRadius(16)
        .border({ width: 1, color: this.t().cardBorder })
        .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })

        Column() {
          Row() {
            Text('自选股云同步')
              .fontSize(15)
              .fontColor(this.t().textPrimary)
            Blank()
            Text(this.lastSyncSummary())
              .fontSize(12)
              .fontColor(this.t().textTertiary)
            Text(this.showCloudSync ? ' ▴' : ' ▾')
              .fontSize(13)
              .fontColor(this.t().textTertiary)
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            this.showCloudSync = !this.showCloudSync;
          })

          if (this.showCloudSync) {
            Column({ space: 10 }) {
              Text('登录华为账号后可将自选股上传云端、跨设备恢复，换机不丢失。完整云同步需在 AGC 开通云数据库（对象类型 WatchlistRecord）并配置签名包。')
                .fontSize(11)
                .fontColor(this.t().textTertiary)
                .width('100%')

              Row({ space: 10 }) {
                Button('上传到云端', { type: ButtonType.Capsule })
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(14)
                  .backgroundColor(this.t().accentFrom)
                  .enabled(!this.isBusy)
                  .onClick(() => {
                    this.doUpload();
                  })
                Button('从云端恢复', { type: ButtonType.Capsule })
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(14)
                  .fontColor(this.t().accent)
                  .backgroundColor(this.t().inputBg)
                  .border({ width: 1, color: this.t().cardBorder })
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
            .padding({ bottom: 14 })
            .alignItems(HorizontalAlign.Start)
          }

          Divider()
            .color(this.t().inputBg)
            .strokeWidth(1)

          Row() {
            Text('AI 智能分析')
              .fontSize(15)
              .fontColor(this.t().textPrimary)
            Blank()
            Text(this.aiConfigSummary())
              .fontSize(12)
              .fontColor(this.t().textTertiary)
            Text(this.showAiConfig ? ' ▴' : ' ▾')
              .fontSize(13)
              .fontColor(this.t().textTertiary)
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            this.showAiConfig = !this.showAiConfig;
          })

          if (this.showAiConfig) {
            Column({ space: 10 }) {
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
                  .backgroundColor(this.t().accentFrom)
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
            .padding({ bottom: 14 })
            .alignItems(HorizontalAlign.Start)
          }

          Divider()
            .color(this.t().inputBg)
            .strokeWidth(1)

          Row() {
            Text('背离提醒')
              .fontSize(15)
              .fontColor(this.t().textPrimary)
            Blank()
            Text(this.reminderEnabled ? '已开启' : '已关闭')
              .fontSize(12)
              .fontColor(this.reminderEnabled ? '#1DBF60' : this.t().textTertiary)
            Text(this.showReminder ? ' ▴' : ' ▾')
              .fontSize(13)
              .fontColor(this.t().textTertiary)
              .margin({ left: 6 })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            this.showReminder = !this.showReminder;
          })

          if (this.showReminder) {
            Column({ space: 10 }) {
              Row() {
                Text('接收背离通知')
                  .fontSize(14)
                  .fontColor(this.t().textPrimary)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
                  .selectedColor(this.t().accent)
                  .onChange((isOn: boolean) => {
                    this.setReminderEnabled(isOn);
                  })
              }
              .width('100%')

              Text('开启后按下方级别与背离类型定时检查自选股，发现新出现的背离时发送系统通知。检测在应用运行期间进行；首次开启及调整级别/类型后仅建立基线，不提醒历史背离。')
                .fontSize(11)
                .fontColor(this.t().textTertiary)
                .width('100%')

              Row({ space: 6 }) {
                Text('级别：' + this.reminderLevelMenuLabel())
                  .fontSize(12)
                  .fontColor(this.t().textPrimary)
                  .maxLines(1)
                Blank()
                Text(this.showLevelPanel ? '▴ 收起' : '▾ 多选')
                  .fontSize(11)
                  .fontColor(this.t().textTertiary)
              }
              .width('100%')
              .height(34)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.t().inputBg)
              .borderRadius(10)
              .border({ width: 1, color: this.t().cardBorder })
              .onClick(() => {
                this.showLevelPanel = !this.showLevelPanel;
              })

              if (this.showLevelPanel) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(ALL_KLINE_LEVELS, (level: KLineLevel) => {
                    Text(kLineLevelLabel(level))
                      .fontSize(12)
                      .fontWeight(this.isReminderLevelSelected(level) ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(this.isReminderLevelSelected(level)
                        ? '#FFFFFF' : this.t().textSecondary)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .margin(3)
                      .borderRadius(12)
                      .linearGradient({ angle: 90,
                        colors: this.chipGrad(this.isReminderLevelSelected(level)) })
                      .onClick(() => {
                        this.toggleReminderLevel(level);
                      })
                  }, (level: KLineLevel) => level.toString() + '-'
                    + (this.isReminderLevelSelected(level) ? '1' : '0'))
                }
                .width('100%')
                .padding({ top: 4, bottom: 4, left: 4, right: 4 })
                .backgroundColor(this.t().inputBg)
                .borderRadius(10)
                .border({ width: 1, color: this.t().cardBorder })
              }

              Row({ space: 8 }) {
                Select(this.reminderDivTypeSelectOptions())
                  .selected(this.reminderDivTypeSelectedIndex())
                  .value('类型：' + this.reminderDivTypeLabel(this.reminderDivType))
                  .font({ size: 12 })
                  .fontColor(this.t().textPrimary)
                  .optionFont({ size: 13 })
                  .optionFontColor(this.t().textPrimary)
                  .selectedOptionFontColor(this.t().accent)
                  .selectedOptionBgColor(this.t().inputBg)
                  .backgroundColor(this.t().inputBg)
                  .borderRadius(10)
                  .border({ width: 1, color: this.t().cardBorder })
                  .height(34)
                  .layoutWeight(1)
                  .onSelect((index: number) => {
                    this.setReminderDivType(this.reminderDivTypeOptions()[index]);
                  })

                Select(this.intervalSelectOptions())
                  .selected(this.intervalSelectedIndex())
                  .value('间隔：' + this.intervalValueText())
                  .font({ size: 12 })
                  .fontColor(this.t().textPrimary)
                  .optionFont({ size: 13 })
                  .optionFontColor(this.t().textPrimary)
                  .selectedOptionFontColor(this.t().accent)
                  .selectedOptionBgColor(this.t().inputBg)
                  .backgroundColor(this.t().inputBg)
                  .borderRadius(10)
                  .border({ width: 1, color: this.t().cardBorder })
                  .height(34)
                  .layoutWeight(1)
                  .onSelect((index: number) => {
                    this.onIntervalSelect(index);
                  })
              }
              .width('100%')

              if (this.showCustomInterval) {
                Row({ space: 8 }) {
                  TextInput({ text: this.reminderIntervalText, placeholder: '输入 1-240 的整数分钟' })
                    .type(InputType.Number)
                    .fontSize(12)
                    .height(34)
                    .layoutWeight(1)
                    .backgroundColor(this.t().inputBg)
                    .borderRadius(8)
                    .padding({ left: 10, right: 10 })
                    .onChange((value: string) => {
                      this.reminderIntervalText = value;
                    })
                    .onSubmit(() => {
                      this.applyCustomInterval();
                    })
                    .onBlur(() => {
                      this.applyCustomInterval();
                    })
                  Text('确定')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                    .linearGradient({ angle: 135, colors: this.chipGrad(true) })
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .borderRadius(14)
                    .onClick(() => {
                      this.applyCustomInterval();
                    })
                }
                .width('100%')
              }

              if (this.reminderStatus !== '') {
                Text(this.reminderStatus)
                  .fontSize(12)
                  .fontColor(this.reminderStatusColor())
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ bottom: 14 })
            .alignItems(HorizontalAlign.Start)
          }

          Divider()
            .color(this.t().inputBg)
            .strokeWidth(1)

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
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.t().card)
        .borderRadius(16)
        .border({ width: 1, color: this.t().cardBorder })
        .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })
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
