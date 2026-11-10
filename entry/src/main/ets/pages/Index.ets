import { hilog } from '@kit.PerformanceAnalysisKit';
import { ALL_KLINE_LEVELS, DetailNavParam, ImageScanNavParam, KLineLevel,
  ScanNavParam, SearchSuggest, StockQuote, kLineLevelLabel } from '../model/StockModels';
import { StockApi, normalizeStockCode } from '../data/StockApi';
import { WatchlistGroup, WatchlistStore } from '../store/WatchlistStore';
import { SettingsStore } from '../store/SettingsStore';
import { ThemeColors, ThemeNavParam, themeColors } from '../model/Theme';
import { PersonalPage } from './Personal';
import { CreateGroupDialog, GroupPickerDialog } from '../components/GroupDialogs';

const DOMAIN: number = 0x0001;
const TAG: string = 'WatchlistIndex';
const FILTER_ALL: string = '__all';
const FILTER_NONE: string = '__none';
const SCAN_COUNT_OPTIONS: number[] = [50, 100, 200, 500];
const SCAN_SORT_OPTIONS: string[] = ['f6', 'f20', 'f3', 'f8'];

/** 分组筛选 chip 的构建参数。 */
interface GroupChipParam {
  label: string;
  target: string;
  active: boolean;
  deletable: boolean;
  count: number;
}

@Entry
@Component
struct Index {
  @State quoteList: StockQuote[] = [];
  @State isLoading: boolean = false;
  @State isAdding: boolean = false;
  @State loadErr: string = '';
  @State inputCode: string = '';
  @State suggestions: SearchSuggest[] = [];
  @State activeTab: number = 0;
  @State groupFilter: string = FILTER_ALL;
  @State groupNames: string[] = [];
  @State pickerGroups: string[] = [];
  @State pickerHint: string = '';
  @State scanCategory: string = 'watchlist';
  @State scanLevels: KLineLevel[] = [KLineLevel.DAY];
  @State scanCount: number = SettingsStore.DEFAULT_SCAN_COUNT;
  @State scanSort: string = SettingsStore.DEFAULT_SCAN_SORT;
  @State showLevelPanel: boolean = false;
  @State showCustomCount: boolean = false;
  @State customCountInput: string = '';
  @State customCountErr: string = '';
  @StorageLink('theme_index') themeIndex: number = 0;
  @StorageLink('watchlist_version') @Watch('onWatchlistVersionChange') watchlistVersion: number = 0;
  private pathStack: NavPathStack = new NavPathStack();
  private storedCodes: string[] = [];
  private searchToken: number = 0;
  private groupList: WatchlistGroup[] = [];
  private pendingAddCode: string = '';
  private pendingAddVerified: boolean = false;
  private createGroupController: CustomDialogController = new CustomDialogController({
    builder: CreateGroupDialog({
      onCreate: (name: string) => {
        this.createGroup(name);
      }
    }),
    customStyle: true,
    autoCancel: true
  });
  private groupPickerController: CustomDialogController = new CustomDialogController({
    builder: GroupPickerDialog({
      hint: this.pickerHint,
      groups: this.pickerGroups,
      onPick: (group: string) => {
        this.onPickAddGroup(group);
      }
    }),
    customStyle: true,
    autoCancel: true
  });

  onWatchlistVersionChange(): void {
    this.reloadAfterSync();
  }

  /** 底部 dock 激活态渐变，跟随主题强调色。 */
  private dockGradColors(): Array<[ResourceColor, number]> {
    return [[this.t().accentFrom, 0], [this.t().accentTo, 1]];
  }

  private async reloadAfterSync(): Promise<void> {
    this.storedCodes = await WatchlistStore.loadCodes(getContext(this));
    await this.loadGroups();
    await this.refreshQuotes();
  }

  /** 轻提示 Toast（分组创建/删除等反馈）。 */
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  private dockLabelColor(tab: number): string {
    if (this.activeTab === tab) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private dockFontWeight(tab: number): FontWeight {
    if (this.activeTab === tab) {
      return FontWeight.Bold;
    }
    return FontWeight.Normal;
  }

  aboutToAppear(): void {
    this.initData();
  }

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private async initData(): Promise<void> {
    this.themeIndex = await SettingsStore.loadThemeId(getContext(this));
    this.storedCodes = await WatchlistStore.loadCodes(getContext(this));
    this.scanCategory = await SettingsStore.loadScanCategory(getContext(this));
    this.scanCount = await SettingsStore.loadScanCount(getContext(this));
    this.scanSort = await SettingsStore.loadScanSort(getContext(this));
    this.scanLevels = await SettingsStore.loadScanLevels(getContext(this));
    await this.loadGroups();
    await this.refreshQuotes();
  }

  /** 加载分组列表并同步筛选状态（当前筛选分组被删时回落到全部）。 */
  private async loadGroups(): Promise<void> {
    const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(getContext(this));
    this.groupList = groups;
    const names: string[] = [];
    for (const g of groups) {
      names.push(g.name);
    }
    this.groupNames = names;
    if (this.groupFilter !== FILTER_ALL && this.groupFilter !== FILTER_NONE
      && names.indexOf(this.groupFilter) < 0) {
      this.groupFilter = FILTER_ALL;
    }
    // 扫描标的指向已删分组时回落到全部自选
    if (this.scanCategory.indexOf('group:') === 0
      && names.indexOf(this.scanCategory.substring(6)) < 0) {
      this.scanCategory = 'watchlist';
      SettingsStore.saveScanCategory(getContext(this), 'watchlist').catch(() => {
      });
    }
  }

  private async createGroup(name: string): Promise<void> {
    try {
      const ok: boolean = await WatchlistStore.createGroup(getContext(this), name);
      if (!ok) {
        this.showToast('分组「' + name + '」已存在');
        return;
      }
      await this.loadGroups();
      this.groupFilter = name;
      this.showToast('已创建分组「' + name + '」');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'createGroup failed: %{public}s', `${error}`);
      this.showToast('创建分组失败，请重试');
    }
  }

  private async deleteGroup(name: string): Promise<void> {
    try {
      await WatchlistStore.deleteGroup(getContext(this), name);
      await this.loadGroups();
      this.showToast('已删除分组「' + name + '」');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'deleteGroup failed: %{public}s', `${error}`);
      this.showToast('删除分组失败，请重试');
    }
  }

  private confirmDeleteGroup(name: string): void {
    AlertDialog.show({
      title: '删除分组',
      message: `确定删除分组「${name}」吗？组内股票将保留在自选中（移至未分组）。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF6B6B',
        action: () => {
          this.deleteGroup(name);
        }
      }
    });
  }

  /** 个股所属分组名，空串表示未分组。 */
  private groupOfCode(code: string): string {
    for (const g of this.groupList) {
      if (g.codes.indexOf(code) >= 0) {
        return g.name;
      }
    }
    return '';
  }

  /** 按当前分组筛选行情列表。 */
  private filteredQuotes(): StockQuote[] {
    if (this.groupFilter === FILTER_ALL) {
      return this.quoteList;
    }
    const list: StockQuote[] = [];
    for (const q of this.quoteList) {
      if (this.groupFilter === FILTER_NONE) {
        if (this.groupOfCode(q.code) === '') {
          list.push(q);
        }
      } else if (this.groupOfCode(q.code) === this.groupFilter) {
        list.push(q);
      }
    }
    return list;
  }

  private async refreshQuotes(): Promise<void> {
    if (this.storedCodes.length === 0) {
      this.quoteList = [];
      return;
    }
    this.isLoading = true;
    this.loadErr = '';
    try {
      const quotes: StockQuote[] = await StockApi.fetchQuotes(this.storedCodes.slice());
      if (quotes.length === 0) {
        this.loadErr = '未获取到行情数据，请检查网络后重试';
      }
      this.quoteList = quotes;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'refreshQuotes failed: %{public}s', `${error}`);
      this.loadErr = '行情刷新失败，请检查网络后重试';
    }
    this.isLoading = false;
  }

  private async addStock(): Promise<void> {
    const normalized: string = normalizeStockCode(this.inputCode);
    if (normalized === '') {
      this.loadErr = '请输入正确的股票代码，如 600519 或 sz000001';
      return;
    }
    if (this.storedCodes.indexOf(normalized) >= 0) {
      this.loadErr = '该股票已在自选列表中';
      return;
    }
    if (this.groupNames.length > 0) {
      this.pendingAddCode = normalized;
      this.pendingAddVerified = false;
      this.pickerHint = '选择「' + normalized + '」加入的分组';
      this.pickerGroups = this.groupNames.slice();
      this.groupPickerController.open();
      return;
    }
    await this.finishAddCode(normalized, '');
  }

  /** 选定分组后落地添加（股票代码未经行情验证的路径，先验证存在再入库）。 */
  private async finishAddCode(code: string, group: string): Promise<void> {
    this.isAdding = true;
    this.loadErr = '';
    try {
      const quotes: StockQuote[] = await StockApi.fetchQuotes([code]);
      if (quotes.length === 0 || quotes[0].name === '') {
        this.loadErr = `未找到股票 ${code}，请确认代码是否正确`;
      } else {
        await WatchlistStore.addToGroup(getContext(this), code, group);
        this.inputCode = '';
        this.storedCodes = await WatchlistStore.loadCodes(getContext(this));
        await this.loadGroups();
        await this.refreshQuotes();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'finishAddCode failed: %{public}s', `${error}`);
      this.loadErr = '添加失败，请检查网络后重试';
    }
    this.isAdding = false;
  }

  /** 选定分组后落地添加（搜索联想结果，已确认存在）。 */
  private async finishAddVerified(code: string, group: string): Promise<void> {
    this.isAdding = true;
    try {
      await WatchlistStore.addToGroup(getContext(this), code, group);
      this.storedCodes = await WatchlistStore.loadCodes(getContext(this));
      await this.loadGroups();
      await this.refreshQuotes();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'finishAddVerified failed: %{public}s', `${error}`);
      this.loadErr = '添加失败，请检查网络后重试';
    }
    this.isAdding = false;
  }

  /** 分组选择对话框回调：按来源路径继续落地添加。 */
  private onPickAddGroup(group: string): void {
    const code: string = this.pendingAddCode;
    const verified: boolean = this.pendingAddVerified;
    this.pendingAddCode = '';
    if (code === '') {
      return;
    }
    if (verified) {
      this.finishAddVerified(code, group);
    } else {
      this.finishAddCode(code, group);
    }
  }

  private onInputChanged(value: string): void {
    this.inputCode = value;
    this.scheduleSearch(value);
  }

  private hasNonAscii(s: string): boolean {
    for (let i = 0; i < s.length; i++) {
      if (s.charCodeAt(i) > 127) {
        return true;
      }
    }
    return false;
  }

  /**
   * 输入防抖联想搜索：中文至少1字、数字/字母至少2位触发。
   */
  private scheduleSearch(keyword: string): void {
    this.searchToken++;
    const kw: string = keyword.trim();
    const minLen: number = this.hasNonAscii(kw) ? 1 : 2;
    if (kw.length < minLen) {
      this.suggestions = [];
      return;
    }
    const token: number = this.searchToken;
    setTimeout(() => {
      this.doSearch(kw, token);
    }, 250);
  }

  private async doSearch(keyword: string, token: number): Promise<void> {
    try {
      const list: SearchSuggest[] = await StockApi.fetchSearchSuggest(keyword);
      if (token !== this.searchToken) {
        return;
      }
      this.suggestions = list.slice(0, 8);
    } catch (error) {
      if (token === this.searchToken) {
        this.suggestions = [];
      }
    }
  }

  private suggestTypeLabel(type: string): string {
    if (type === 'GP-A') {
      return 'A股';
    }
    return type;
  }

  private async addFromSuggest(s: SearchSuggest): Promise<void> {
    this.searchToken++;
    this.suggestions = [];
    this.inputCode = '';
    this.loadErr = '';
    if (this.storedCodes.indexOf(s.code) >= 0) {
      this.loadErr = '该股票已在自选列表中';
      return;
    }
    if (this.groupNames.length > 0) {
      this.pendingAddCode = s.code;
      this.pendingAddVerified = true;
      this.pickerHint = '选择「' + s.name + '」加入的分组';
      this.pickerGroups = this.groupNames.slice();
      this.groupPickerController.open();
      return;
    }
    await this.finishAddVerified(s.code, '');
  }

  private async removeStock(code: string): Promise<void> {
    try {
      await WatchlistStore.removeCode(getContext(this), code);
      this.storedCodes = await WatchlistStore.loadCodes(getContext(this));
      await this.loadGroups();
      await this.refreshQuotes();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'removeStock failed: %{public}s', `${error}`);
    }
  }

  private openDetail(quote: StockQuote): void {
    const p: DetailNavParam = { code: quote.code, name: quote.name };
    this.pathStack.pushPathByName('StockDetail', p);
  }

  /** 使用 hero 卡片中的扫描配置发起扫描。 */
  private startScan(): void {
    const p: ScanNavParam = new ScanNavParam();
    p.category = this.scanCategory;
    this.pathStack.pushPathByName('ScanReport', p);
  }

  private isGroupScanCategory(): boolean {
    return this.scanCategory.indexOf('group:') === 0;
  }

  private scanGroupName(): string {
    return this.scanCategory.substring(6);
  }

  private isMarketScan(): boolean {
    return this.scanCategory === 'astock' || this.scanCategory === 'etf';
  }

  private isLevelSelected(level: KLineLevel): boolean {
    return this.scanLevels.indexOf(level) >= 0;
  }

  /** 级别行文案：单级别显示名称，多级别显示数量。 */
  private levelRowLabel(): string {
    if (this.scanLevels.length === 1) {
      return kLineLevelLabel(this.scanLevels[0]);
    }
    return this.scanLevels.length + '个级别';
  }

  private async toggleScanLevel(level: KLineLevel): Promise<void> {
    const idx: number = this.scanLevels.indexOf(level);
    if (idx >= 0) {
      if (this.scanLevels.length <= 1) {
        return;
      }
      this.scanLevels.splice(idx, 1);
    } else {
      this.scanLevels.push(level);
    }
    await SettingsStore.saveScanLevels(getContext(this), this.scanLevels.slice());
  }

  private scopeSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    const all: SelectOption = { value: '自选股 · 全部' };
    opts.push(all);
    for (const name of this.groupNames) {
      const opt: SelectOption = { value: '自选股 · ' + name };
      opts.push(opt);
    }
    const astock: SelectOption = { value: '全市场个股' };
    opts.push(astock);
    const etf: SelectOption = { value: '全市场ETF' };
    opts.push(etf);
    return opts;
  }

  private scopeSelectedIndex(): number {
    if (this.scanCategory === 'astock') {
      return this.groupNames.length + 1;
    }
    if (this.scanCategory === 'etf') {
      return this.groupNames.length + 2;
    }
    if (this.isGroupScanCategory()) {
      const idx: number = this.groupNames.indexOf(this.scanGroupName());
      if (idx >= 0) {
        return idx + 1;
      }
    }
    return 0;
  }

  private scopeValueText(): string {
    if (this.scanCategory === 'astock') {
      return '全市场个股';
    }
    if (this.scanCategory === 'etf') {
      return '全市场ETF';
    }
    if (this.isGroupScanCategory()) {
      return '自选股 · ' + this.scanGroupName();
    }
    return '自选股 · 全部';
  }

  private async onScopeSelect(index: number): Promise<void> {
    let target: string = 'watchlist';
    if (index === this.groupNames.length + 1) {
      target = 'astock';
    } else if (index === this.groupNames.length + 2) {
      target = 'etf';
    } else if (index >= 1 && index <= this.groupNames.length) {
      target = 'group:' + this.groupNames[index - 1];
    }
    if (target === this.scanCategory) {
      return;
    }
    this.scanCategory = target;
    if (!this.isMarketScan()) {
      this.showCustomCount = false;
    }
    await SettingsStore.saveScanCategory(getContext(this), target);
  }

  private sortLabel(fid: string): string {
    if (fid === 'f20') {
      return '总市值';
    }
    if (fid === 'f3') {
      return '涨跌幅';
    }
    if (fid === 'f8') {
      return '换手率';
    }
    return '成交额';
  }

  private scanSortSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const fid of SCAN_SORT_OPTIONS) {
      const opt: SelectOption = { value: this.sortLabel(fid) };
      opts.push(opt);
    }
    return opts;
  }

  private scanSortSelectedIndex(): number {
    return SCAN_SORT_OPTIONS.indexOf(this.scanSort);
  }

  private async changeScanSort(fid: string): Promise<void> {
    if (fid === this.scanSort) {
      return;
    }
    this.scanSort = fid;
    await SettingsStore.saveScanSort(getContext(this), fid);
  }

  private isCustomCount(): boolean {
    return SCAN_COUNT_OPTIONS.indexOf(this.scanCount) < 0;
  }

  private rangeSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const n of SCAN_COUNT_OPTIONS) {
      const opt: SelectOption = { value: '前' + n };
      opts.push(opt);
    }
    const customOpt: SelectOption = { value: '自定义' };
    opts.push(customOpt);
    return opts;
  }

  private rangeSelectedIndex(): number {
    if (this.isCustomCount()) {
      return SCAN_COUNT_OPTIONS.length;
    }
    return SCAN_COUNT_OPTIONS.indexOf(this.scanCount);
  }

  private rangeValueText(): string {
    if (this.isCustomCount()) {
      return '自定义 ' + this.scanCount;
    }
    return '前' + this.scanCount;
  }

  private onRangeSelect(index: number): void {
    if (index >= SCAN_COUNT_OPTIONS.length) {
      this.customCountInput = this.isCustomCount() ? `${this.scanCount}` : '';
      this.customCountErr = '';
      this.showCustomCount = true;
      return;
    }
    this.showCustomCount = false;
    this.changeScanCount(SCAN_COUNT_OPTIONS[index]);
  }

  private async changeScanCount(n: number): Promise<void> {
    if (n === this.scanCount) {
      return;
    }
    this.scanCount = n;
    await SettingsStore.saveScanCount(getContext(this), n);
  }

  private async applyCustomCount(): Promise<void> {
    const input: string = this.customCountInput.trim();
    const n: number = Number(input);
    if (input === '' || isNaN(n) || n < 10 || n > 2000 || Math.floor(n) !== n) {
      this.customCountErr = '请输入 10 - 2000 的整数';
      return;
    }
    this.customCountErr = '';
    this.showCustomCount = false;
    this.scanCount = n;
    await SettingsStore.saveScanCount(getContext(this), n);
  }

  private openImageScan(): void {
    this.pathStack.pushPathByName('ImageScan', new ImageScanNavParam());
  }

  private openThemeSetting(): void {
    const p: ThemeNavParam = new ThemeNavParam();
    this.pathStack.pushPathByName('ThemeSetting', p);
  }

  private confirmRemove(quote: StockQuote): void {
    AlertDialog.show({
      title: '移除自选股',
      message: `确定将「${quote.name}」（${quote.code.toUpperCase()}）从自选股中移除吗？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '移除',
        fontColor: '#FF6B6B',
        action: () => {
          this.removeStock(quote.code);
        }
      }
    });
  }

  private priceText(quote: StockQuote): string {
    if (quote.price > 0) {
      return quote.price.toFixed(2);
    }
    return '--';
  }

  private percentText(quote: StockQuote): string {
    const sign: string = quote.changePercent > 0 ? '+' : '';
    return sign + quote.changePercent.toFixed(2) + '%';
  }

  private percentColor(quote: StockQuote): string {
    if (quote.changePercent > 0) {
      return '#E62E4C';
    }
    if (quote.changePercent < 0) {
      return '#1DBF60';
    }
    return '#8A90A0';
  }

  /** 涨跌幅胶囊底色：涨红 / 跌绿 / 平灰（低透明度色块）。 */
  private percentPillBg(quote: StockQuote): string {
    if (quote.changePercent > 0) {
      return 'rgba(230,46,76,0.16)';
    }
    if (quote.changePercent < 0) {
      return 'rgba(29,191,96,0.16)';
    }
    return 'rgba(138,144,160,0.16)';
  }

  private heroGradColors(): Array<[ResourceColor, number]> {
    return [[this.t().accentFrom, 0], [this.t().accentTo, 1]];
  }

  /** 分组 chip 的平面底色（与 hero 渐变同构，便于切换）。 */
  private flatChipColors(): Array<[ResourceColor, number]> {
    return [[this.t().inputBg, 0], [this.t().inputBg, 1]];
  }

  private groupCount(name: string): number {
    for (const g of this.groupList) {
      if (g.name === name) {
        return g.codes.length;
      }
    }
    return 0;
  }

  private ungroupedCount(): number {
    let n: number = 0;
    for (const code of this.storedCodes) {
      if (this.groupOfCode(code) === '') {
        n += 1;
      }
    }
    return n;
  }

  /** 分组筛选 chip：点击切换筛选，长按自建分组可删除。对象传参以获得响应式刷新。 */
  @Builder
  private groupChip($$: GroupChipParam) {
    Row({ space: 5 }) {
      Text($$.label)
        .fontSize(12)
        .fontWeight($$.active ? FontWeight.Bold : FontWeight.Normal)
        .fontColor($$.active ? '#FFFFFF' : this.t().textSecondary)
      Text(`${$$.count}`)
        .fontSize(10)
        .fontColor($$.active ? 'rgba(255,255,255,0.85)' : this.t().textTertiary)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(12)
    .linearGradient({ angle: 90, colors: $$.active ? this.heroGradColors() : this.flatChipColors() })
    .onClick(() => {
      this.groupFilter = $$.target;
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((event: GestureEvent) => {
          if ($$.deletable) {
            this.confirmDeleteGroup($$.label);
          }
        })
    )
  }

  /** hero 卡内半透明白底按钮（叠加在渐变卡上）。 */
  private heroChipBg(): string {
    if (this.themeIndex === 3) {
      return 'rgba(42,91,215,0.10)';
    }
    return 'rgba(255,255,255,0.16)';
  }

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.activeTab === 0) {
          Column() {
        Row() {
          Column() {
            Text('自选股')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.t().textPrimary)
            Text('MACD 多级别背离分析')
              .fontSize(12)
              .fontColor(this.t().textSecondary)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          if (this.isLoading) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.t().accent)
              .margin({ right: 10 })
          }
          Text('主题')
            .fontColor(this.t().accent)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.t().card)
            .borderRadius(17)
            .border({ width: 1, color: this.t().cardBorder })
            .onClick(() => {
              this.openThemeSetting();
            })
          Text('刷新')
            .fontColor(this.t().accent)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.t().card)
            .borderRadius(17)
            .border({ width: 1, color: this.t().cardBorder })
            .margin({ left: 8 })
            .onClick(() => {
              this.refreshQuotes();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 12 })

        Row({ space: 8 }) {
          TextInput({ placeholder: '输入代码或名称添加自选，如 600519 / 贵州茅台' })
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor(this.t().textPrimary)
            .placeholderColor(this.t().textTertiary)
            .placeholderFont({ size: 13 })
            .backgroundColor(this.t().card)
            .borderRadius(12)
            .border({ width: 1, color: this.t().cardBorder })
            .onChange((value: string) => {
              this.onInputChanged(value);
            })
          Text('添加')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .height(42)
            .padding({ left: 18, right: 18 })
            .linearGradient({ angle: 135, colors: this.heroGradColors() })
            .borderRadius(12)
            .shadow({ radius: 6, color: this.t().shadowColor, offsetY: 2 })
            .onClick(() => {
              if (!this.isAdding) {
                this.addStock();
              }
            })
          Text('识图')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.t().accent)
            .textAlign(TextAlign.Center)
            .height(42)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.t().card)
            .borderRadius(12)
            .border({ width: 1, color: this.t().cardBorder })
            .onClick(() => {
              this.openImageScan();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 2, bottom: 8 })

        if (this.suggestions.length > 0) {
          List() {
            ForEach(this.suggestions, (s: SearchSuggest) => {
              ListItem() {
                Row() {
                  Text(s.name)
                    .fontSize(14)
                    .fontColor(this.t().textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(s.code.toUpperCase())
                    .fontSize(12)
                    .fontColor(this.t().textSecondary)
                    .margin({ left: 8 })
                  Text(this.suggestTypeLabel(s.type))
                    .fontSize(10)
                    .fontColor(this.t().accent)
                    .backgroundColor(this.t().inputBg)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(6)
                    .margin({ left: 8 })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .onClick(() => {
                  this.addFromSuggest(s);
                })
              }
            }, (s: SearchSuggest) => s.code + '-' + s.name)
          }
          .width('100%')
          .constraintSize({ maxHeight: 300 })
          .padding({ left: 12, right: 12 })
          .margin({ left: 16, right: 16, top: 2, bottom: 4 })
          .backgroundColor(this.t().card)
          .borderRadius(10)
          .shadow({ radius: 12, color: '#66000000', offsetX: 0, offsetY: 4 })
          .zIndex(10)
        }

        if (this.loadErr !== '') {
          Text(this.loadErr)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .padding({ left: 16, right: 16, bottom: 6 })
        }

        Column({ space: 10 }) {
          Row() {
            Column() {
              Text('背离扫描')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text('多级别共振扫描 · 一键生成扫描报告')
                .fontSize(11)
                .fontColor('rgba(255,255,255,0.75)')
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          Select(this.scopeSelectOptions())
            .selected(this.scopeSelectedIndex())
            .value('标的：' + this.scopeValueText())
            .font({ size: 12 })
            .fontColor('#FFFFFF')
            .optionFont({ size: 13 })
            .optionFontColor(this.t().textPrimary)
            .selectedOptionFontColor(this.t().accent)
            .selectedOptionBgColor(this.t().inputBg)
            .backgroundColor(this.heroChipBg())
            .borderRadius(10)
            .height(34)
            .width('100%')
            .onSelect((index: number) => {
              this.onScopeSelect(index);
            })

          Row({ space: 6 }) {
            Text('级别：' + this.levelRowLabel())
              .fontSize(12)
              .fontColor('#FFFFFF')
              .maxLines(1)
            Blank()
            Text(this.showLevelPanel ? '▴ 收起' : '▾ 多选')
              .fontSize(11)
              .fontColor('rgba(255,255,255,0.78)')
          }
          .width('100%')
          .height(34)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.heroChipBg())
          .borderRadius(10)
          .onClick(() => {
            this.showLevelPanel = !this.showLevelPanel;
          })

          if (this.showLevelPanel) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(ALL_KLINE_LEVELS, (level: KLineLevel) => {
                Text(kLineLevelLabel(level))
                  .fontSize(12)
                  .fontWeight(this.isLevelSelected(level) ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.isLevelSelected(level)
                    ? this.t().accentFrom : '#FFFFFF')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin(3)
                  .borderRadius(12)
                  .backgroundColor(this.isLevelSelected(level)
                    ? '#FFFFFF' : this.heroChipBg())
                  .onClick(() => {
                    this.toggleScanLevel(level);
                  })
              }, (level: KLineLevel) => level.toString() + '-'
                + (this.isLevelSelected(level) ? '1' : '0'))
            }
            .width('100%')
            .padding({ top: 4, bottom: 4, left: 4, right: 4 })
            .backgroundColor(this.heroChipBg())
            .borderRadius(10)
          }

          if (this.isMarketScan()) {
            Row({ space: 8 }) {
              Select(this.rangeSelectOptions())
                .selected(this.rangeSelectedIndex())
                .value('范围：' + this.rangeValueText())
                .font({ size: 12 })
                .fontColor('#FFFFFF')
                .optionFont({ size: 13 })
                .optionFontColor(this.t().textPrimary)
                .selectedOptionFontColor(this.t().accent)
                .selectedOptionBgColor(this.t().inputBg)
                .backgroundColor(this.heroChipBg())
                .borderRadius(10)
                .height(34)
                .layoutWeight(1)
                .onSelect((index: number) => {
                  this.onRangeSelect(index);
                })

              Select(this.scanSortSelectOptions())
                .selected(this.scanSortSelectedIndex())
                .value('排序：' + this.sortLabel(this.scanSort))
                .font({ size: 12 })
                .fontColor('#FFFFFF')
                .optionFont({ size: 13 })
                .optionFontColor(this.t().textPrimary)
                .selectedOptionFontColor(this.t().accent)
                .selectedOptionBgColor(this.t().inputBg)
                .backgroundColor(this.heroChipBg())
                .borderRadius(10)
                .height(34)
                .layoutWeight(1)
                .onSelect((index: number) => {
                  this.changeScanSort(SCAN_SORT_OPTIONS[index]);
                })
            }
            .width('100%')

            if (this.showCustomCount) {
              Row({ space: 8 }) {
                TextInput({ text: this.customCountInput, placeholder: '输入 10 - 2000 的整数' })
                  .type(InputType.Number)
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .placeholderColor('rgba(255,255,255,0.6)')
                  .height(36)
                  .layoutWeight(1)
                  .backgroundColor(this.heroChipBg())
                  .borderRadius(8)
                  .padding({ left: 10, right: 10 })
                  .onChange((value: string) => {
                    this.customCountInput = value;
                  })
                Text('确定')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.t().accentFrom)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .backgroundColor('#FFFFFF')
                  .borderRadius(14)
                  .onClick(() => {
                    this.applyCustomCount();
                  })
              }
              .width('100%')

              if (this.customCountErr !== '') {
                Text(this.customCountErr)
                  .fontSize(11)
                  .fontColor('#FFD1D1')
                  .width('100%')
              }
            }
          }

          Text('开始扫描')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.t().accentFrom)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 10, bottom: 10 })
            .backgroundColor('#FFFFFF')
            .borderRadius(18)
            .shadow({ radius: 6, color: this.t().shadowColor, offsetY: 2 })
            .onClick(() => {
              this.startScan();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .margin({ left: 16, right: 16, bottom: 10 })
        .linearGradient({ angle: 120, colors: this.heroGradColors() })
        .borderRadius(16)
        .shadow({ radius: 10, color: this.t().shadowColor, offsetY: 4 })

        Column({ space: 10 }) {
          Row() {
            Text('自选分组')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
            if (this.groupNames.length > 0) {
              Text(`${this.groupNames.length} 个分组`)
                .fontSize(11)
                .fontColor(this.t().textTertiary)
                .margin({ left: 8 })
            }
            Blank()
            Text('＋ 新建')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().accent)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.t().inputBg)
              .borderRadius(11)
              .border({ width: 1, color: this.t().accent })
              .onClick(() => {
                this.createGroupController.open();
              })
          }
          .width('100%')

          if (this.groupNames.length === 0) {
            Text('新建分组后可分类管理自选股，加股时可选择分组，长按分组可删除')
              .fontSize(11)
              .fontColor(this.t().textTertiary)
              .width('100%')
          } else {
            Scroll() {
              Row({ space: 8 }) {
                this.groupChip({
                  label: '全部',
                  target: FILTER_ALL,
                  active: this.groupFilter === FILTER_ALL,
                  deletable: false,
                  count: this.storedCodes.length
                })
                this.groupChip({
                  label: '未分组',
                  target: FILTER_NONE,
                  active: this.groupFilter === FILTER_NONE,
                  deletable: false,
                  count: this.ungroupedCount()
                })
                ForEach(this.groupNames, (name: string) => {
                  this.groupChip({
                    label: name,
                    target: name,
                    active: this.groupFilter === name,
                    deletable: true,
                    count: this.groupCount(name)
                  })
                }, (name: string) => `${name}-${this.groupCount(name)}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .margin({ left: 16, right: 16, bottom: 10 })
        .backgroundColor(this.t().card)
        .borderRadius(16)
        .border({ width: 1, color: this.t().cardBorder })
        .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })

        if (this.quoteList.length === 0) {
          Column({ space: 10 }) {
            Stack() {
              Column()
                .width(72)
                .height(72)
                .backgroundColor(this.t().inputBg)
                .borderRadius(36)
              Text('📈')
                .fontSize(30)
            }
            Text('暂无自选股')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.t().textPrimary)
            Text('在上方输入股票代码（如 600519、sz000001）添加自选股，或点击「识图」从持仓截图识别批量添加')
              .fontSize(12)
              .fontColor(this.t().textTertiary)
              .margin({ top: 4 })
              .textAlign(TextAlign.Center)
              .lineHeight(18)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 32, right: 32 })
        } else {
          if (this.filteredQuotes().length === 0) {
            Column() {
              Text('该分组暂无股票')
                .fontSize(13)
                .fontColor(this.t().textTertiary)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding({ bottom: 104 })
          } else {
          List({ space: 10 }) {
            ForEach(this.filteredQuotes(), (quote: StockQuote) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(quote.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.t().textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(quote.code.toUpperCase())
                      .fontSize(11)
                      .fontColor(this.t().textTertiary)
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column({ space: 5 }) {
                    Text(this.priceText(quote))
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.percentColor(quote))
                    Text(this.percentText(quote))
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.percentColor(quote))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(9)
                      .backgroundColor(this.percentPillBg(quote))
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 13, bottom: 13 })
                .backgroundColor(this.t().card)
                .borderRadius(16)
                .border({ width: 1, color: this.t().cardBorder })
                .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })
                .onClick(() => {
                  this.openDetail(quote);
                })
                .gesture(
                  LongPressGesture({ repeat: false, duration: 500 })
                    .onAction((event: GestureEvent) => {
                      this.confirmRemove(quote);
                    })
                )
              }
            }, (quote: StockQuote) => quote.code)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 2, bottom: 104 })
          }
        }
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.t().bg)
        } else {
          PersonalPage({
            navPathStack: this.pathStack,
            onWatchlistSynced: () => {
              this.reloadAfterSync();
            }
          })
        }

        Row({ space: 4 }) {
          Stack() {
            if (this.activeTab === 0) {
              Column()
                .width('100%')
                .height('100%')
                .borderRadius(19)
                .linearGradient({ angle: 90, colors: this.dockGradColors() })
                .shadow({ radius: 8, color: this.t().shadowColor })
            }
            Text('主页')
              .fontSize(14)
              .fontWeight(this.dockFontWeight(0))
              .fontColor(this.dockLabelColor(0))
          }
          .width(78)
          .height(38)
          .onClick(() => {
            this.activeTab = 0;
          })

          Stack() {
            if (this.activeTab === 1) {
              Column()
                .width('100%')
                .height('100%')
                .borderRadius(19)
                .linearGradient({ angle: 90, colors: this.dockGradColors() })
                .shadow({ radius: 8, color: this.t().shadowColor })
            }
            Text('个人')
              .fontSize(14)
              .fontWeight(this.dockFontWeight(1))
              .fontColor(this.dockLabelColor(1))
          }
          .width(78)
          .height(38)
          .onClick(() => {
            this.activeTab = 1;
          })
        }
        .padding({ left: 6, right: 6, top: 5, bottom: 5 })
        .margin({ left: 64, right: 64, bottom: 18 })
        .borderRadius(24)
        .backgroundColor('#B3' + this.t().card.substring(1))
        .backgroundBlurStyle(BlurStyle.Thick)
        .shadow({ radius: 20, color: '#33000000', offsetY: 4 })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
