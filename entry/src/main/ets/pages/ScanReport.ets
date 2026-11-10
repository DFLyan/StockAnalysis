import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import {
  ALL_KLINE_LEVELS,
  DetailNavParam,
  DivergenceInfo,
  DivergenceType,
  KLineItem,
  KLineLevel,
  MacdPoint,
  MarketRef,
  ScanResultItem,
  StockQuote,
  kLineLevelLabel
} from '../model/StockModels';
import { StockApi } from '../data/StockApi';
import { MarketApi } from '../data/MarketApi';
import { MacdAnalyzer } from '../analysis/MacdAnalyzer';
import { WatchlistGroup, WatchlistStore } from '../store/WatchlistStore';
import { SettingsStore } from '../store/SettingsStore';
import { ThemeColors, themeColors } from '../model/Theme';
import { GroupPickerDialog } from '../components/GroupDialogs';

const DOMAIN: number = 0x0003;
const TAG: string = 'ScanReport';
const SCAN_BATCH: number = 6;
const DATE_RANGE_IDS: number[] = [0, 1, 2, 3, 4];
const RESULT_SORT_OPTIONS: number[] = [0, 1, 2];
const CARD_DIV_LIMIT: number = 3;
const DAY_MS: number = 86400000;

@Builder
export function ScanReportBuilder(): void {
  ScanReport()
}

/**
 * 一键背离扫描报告页：级别支持 5分/15分/30分/60分/日/周/月 多选（多级别同时扫描），
 * 范围支持自选股 / 全市场个股 / 全市场ETF（前N可预设或自定义，ETF 剔除货币债券）。
 * 结果支持按级别、背离类型（顶/底）与日期（近1周/1月/3月/自定义区间）筛选。
 */
@Component
export struct ScanReport {
  @State category: string = 'watchlist';
  @State scanLevels: KLineLevel[] = [KLineLevel.DAY];
  @State scanCount: number = SettingsStore.DEFAULT_SCAN_COUNT;
  @State scanSort: string = SettingsStore.DEFAULT_SCAN_SORT;
  @State isScanning: boolean = false;
  @State scannedCount: number = 0;
  @State totalCount: number = 0;
  @State failCount: number = 0;
  @State results: ScanResultItem[] = [];
  @State loadErr: string = '';
  @State filterType: number = 0;
  @State filterLevel: number = -1;
  @State dateRange: number = 0;
  @State resultSort: number = 0;
  @State customStart: string = '';
  @State customEnd: string = '';
  @State watchlistCodes: string[] = [];
  @State pickerGroups: string[] = [];
  @State pickerHint: string = '';
  @StorageLink('theme_index') themeIndex: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();
  private cancelled: boolean = false;
  private scanToken: number = 0;
  private pendingAddItem: ScanResultItem | null = null;
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

  aboutToDisappear(): void {
    this.cancelled = true;
  }

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  /** 分组范围 category 编码：group:分组名。 */
  private isGroupCategory(): boolean {
    return this.category.indexOf('group:') === 0;
  }

  private groupNameOfCategory(): string {
    if (this.isGroupCategory()) {
      return this.category.substring(6);
    }
    return '';
  }

  private categoryTitle(): string {
    if (this.category === 'astock') {
      return '全市场个股';
    }
    if (this.category === 'etf') {
      return '全市场ETF';
    }
    if (this.isGroupCategory()) {
      return this.groupNameOfCategory();
    }
    return '自选股';
  }

  private scanTitleText(): string {
    if (this.scanLevels.length === 1) {
      return kLineLevelLabel(this.scanLevels[0]) + ' MACD 背离扫描';
    }
    return '多级别共振扫描（' + this.scanLevels.length + '个级别）';
  }

  private scopeDescText(): string {
    if (this.category === 'astock') {
      return '按' + this.sortLabel(this.scanSort) + '排名前 ' + this.scanCount + ' 只个股';
    }
    if (this.category === 'etf') {
      return '按' + this.sortLabel(this.scanSort) + '排名前 ' + this.scanCount + ' 只ETF（剔除货币/债券）';
    }
    if (this.isGroupCategory()) {
      return '自选分组「' + this.groupNameOfCategory() + '」全部标的';
    }
    return '自选股全部标的';
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

  /** chip 激活态渐变（主题强调色），非激活态返回扁平 inputBg 双 stop。 */
  private chipGrad(active: boolean): Array<[ResourceColor, number]> {
    if (active) {
      return [[this.t().accentFrom, 0], [this.t().accentTo, 1]];
    }
    return [[this.t().inputBg, 0], [this.t().inputBg, 1]];
  }

  private progressText(): string {
    if (this.totalCount <= 0) {
      return '正在获取标的列表...';
    }
    return '已扫描 ' + this.scannedCount + ' / ' + this.totalCount;
  }

  private resultSummaryText(): string {
    let resonance: number = 0;
    for (const r of this.results) {
      if (r.levels.length > 1) {
        resonance++;
      }
    }
    let text: string = '背离 ' + this.results.length + ' 只 · 共振 ' + resonance + ' 只';
    if (this.failCount > 0) {
      text = text + ' · 失败 ' + this.failCount + ' 项';
    }
    return text;
  }

  private levelFilterColor(level: number): string {
    if (this.filterLevel === level) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private isLevelFilterActive(level: number): boolean {
    return this.filterLevel === level;
  }

  private dateRangeDays(): number {
    if (this.dateRange === 1) {
      return 7;
    }
    if (this.dateRange === 2) {
      return 30;
    }
    if (this.dateRange === 3) {
      return 90;
    }
    return 0;
  }

  private dateRangeLabel(id: number): string {
    if (id === 1) {
      return '近1周';
    }
    if (id === 2) {
      return '近1月';
    }
    if (id === 3) {
      return '近3月';
    }
    if (id === 4) {
      return '自定义';
    }
    return '全部日期';
  }

  /**
   * 解析 "YYYY-MM-DD"、"YYYY-MM-DD HH:mm"、"YYYY-MM"（月/季/年级别）
   * 或 "YYYYMMDDHHmm" 数字串，返回当天0点时间戳；无法解析返回 NaN。
   */
  private parseYmd(dateStr: string): number {
    if (dateStr.length === 8 && dateStr.indexOf('-') < 0) {
      const y8: number = Number(dateStr.substring(0, 4));
      const m8: number = Number(dateStr.substring(4, 6));
      const d8: number = Number(dateStr.substring(6, 8));
      if (isNaN(y8) || isNaN(m8) || isNaN(d8)) {
        return NaN;
      }
      return new Date(y8, m8 - 1, d8).getTime();
    }
    if (dateStr.length < 7 || dateStr.charAt(4) !== '-') {
      return NaN;
    }
    const y: number = Number(dateStr.substring(0, 4));
    const m: number = Number(dateStr.substring(5, 7));
    if (isNaN(y) || isNaN(m)) {
      return NaN;
    }
    let d: number = 1;
    if (dateStr.length >= 10) {
      const parsedD: number = Number(dateStr.substring(8, 10));
      if (!isNaN(parsedD)) {
        d = parsedD;
      }
    }
    const time: number = new Date(y, m - 1, d).getTime();
    if (isNaN(time)) {
      return NaN;
    }
    return time;
  }

  /**
   * 日期筛选作用于单条背离：按背离 B 点日期判断；
   * 自定义区间含首尾两天；无法解析时保守保留。
   */
  private inDateRange(dateStr: string): boolean {
    const t: number = this.parseYmd(dateStr);
    if (this.dateRange === 4) {
      if (this.customStart === '' || this.customEnd === '') {
        return true;
      }
      if (isNaN(t)) {
        return true;
      }
      const s: number = this.parseYmd(this.customStart);
      const e: number = this.parseYmd(this.customEnd) + DAY_MS;
      return t >= s && t < e;
    }
    const days: number = this.dateRangeDays();
    if (days <= 0) {
      return true;
    }
    if (isNaN(t)) {
      return true;
    }
    return t >= Date.now() - days * DAY_MS;
  }

  /** 单条结果中通过日期筛选的背离。 */
  private divsAfterDate(item: ScanResultItem): DivergenceInfo[] {
    return item.divergences.filter((d: DivergenceInfo) => this.inDateRange(d.dateB));
  }

  /** 单条结果中同时通过日期 + 背离类型筛选的背离（组合联动核心）。 */
  private divsAfterType(item: ScanResultItem): DivergenceInfo[] {
    const dated: DivergenceInfo[] = this.divsAfterDate(item);
    if (this.filterType === 1) {
      return dated.filter((d: DivergenceInfo) => d.divType === DivergenceType.TOP);
    }
    if (this.filterType === 2) {
      return dated.filter((d: DivergenceInfo) => d.divType === DivergenceType.BOTTOM);
    }
    return dated;
  }

  private hasDivType(item: ScanResultItem, divType: DivergenceType): boolean {
    for (const d of this.divsAfterDate(item)) {
      if (d.divType === divType) {
        return true;
      }
    }
    return false;
  }

  private allResultCount(): number {
    let n: number = 0;
    for (const r of this.results) {
      if (this.divsAfterDate(r).length > 0) {
        n++;
      }
    }
    return n;
  }

  private topResultCount(): number {
    let n: number = 0;
    for (const r of this.results) {
      if (this.hasDivType(r, DivergenceType.TOP)) {
        n++;
      }
    }
    return n;
  }

  private bottomResultCount(): number {
    let n: number = 0;
    for (const r of this.results) {
      if (this.hasDivType(r, DivergenceType.BOTTOM)) {
        n++;
      }
    }
    return n;
  }

  /**
   * 结果日期排序键：兼容 "2026-11-10"、"2026-11-10 09:30"、"2026-11"
   * 与 "202611100930" 格式，统一取数字串比较（6 位按月补齐成 8 位量级）。
   */
  private dateSortKey(dateStr: string): number {
    let digits: string = '';
    for (let i = 0; i < dateStr.length; i++) {
      const c: string = dateStr.charAt(i);
      if (c >= '0' && c <= '9') {
        digits += c;
      }
    }
    if (digits.length >= 8) {
      const n: number = Number(digits.substring(0, 8));
      return isNaN(n) ? 0 : n;
    }
    if (digits.length >= 6) {
      const n: number = Number(digits.substring(0, 6) + '00');
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  private filteredResults(): ScanResultItem[] {
    let list: ScanResultItem[] = [];
    for (const r of this.results) {
      if (this.divsAfterType(r).length > 0) {
        list.push(r);
      }
    }
    if (this.filterLevel >= 0) {
      const wanted: number = this.filterLevel;
      list = list.filter((r: ScanResultItem) => {
        for (const lv of r.levels) {
          if (lv === wanted) {
            return true;
          }
        }
        return false;
      });
    }
    if (this.resultSort === 0) {
      // 共振优先：命中级别数多的在前，同数按最新背离日期降序
      list.sort((a: ScanResultItem, b: ScanResultItem): number => {
        const byLevels: number = b.levels.length - a.levels.length;
        if (byLevels !== 0) {
          return byLevels;
        }
        const ka: number = this.dateSortKey(this.latestDivOf(a).dateB);
        const kb: number = this.dateSortKey(this.latestDivOf(b).dateB);
        return kb - ka;
      });
    } else if (this.resultSort === 1 || this.resultSort === 2) {
      list.sort((a: ScanResultItem, b: ScanResultItem): number => {
        const ka: number = this.dateSortKey(this.latestDivOf(a).dateB);
        const kb: number = this.dateSortKey(this.latestDivOf(b).dateB);
        if (this.resultSort === 1) {
          return kb - ka;
        }
        return ka - kb;
      });
    }
    return list;
  }

  /** 组合筛选后该结果中最新的背离（divergences 按时间降序，取过滤后首个）。 */
  private latestDivOf(item: ScanResultItem): DivergenceInfo {
    return this.divsAfterType(item)[0];
  }

  private itemTopCount(item: ScanResultItem): number {
    let n: number = 0;
    for (const d of this.divsAfterType(item)) {
      if (d.divType === DivergenceType.TOP) {
        n++;
      }
    }
    return n;
  }

  private itemBottomCount(item: ScanResultItem): number {
    let n: number = 0;
    for (const d of this.divsAfterType(item)) {
      if (d.divType === DivergenceType.BOTTOM) {
        n++;
      }
    }
    return n;
  }

  /** 卡片展示的背离清单：组合筛选后最多 CARD_DIV_LIMIT 条。 */
  private itemDivList(item: ScanResultItem): DivergenceInfo[] {
    return this.divsAfterType(item).slice(0, CARD_DIV_LIMIT);
  }

  private itemMoreCount(item: ScanResultItem): number {
    const total: number = this.divsAfterType(item).length;
    return total > CARD_DIV_LIMIT ? total - CARD_DIV_LIMIT : 0;
  }

  /** 是否多级别共振（命中级别数 > 1）。 */
  private isResonance(item: ScanResultItem): boolean {
    return item.levels.length > 1;
  }

  /** 级别短名：徽标组合文案用（5分/15分/…/日/周/月/季/年）。 */
  private levelShortLabel(level: KLineLevel): string {
    if (level === KLineLevel.M5) {
      return '5分';
    }
    if (level === KLineLevel.M15) {
      return '15分';
    }
    if (level === KLineLevel.M30) {
      return '30分';
    }
    if (level === KLineLevel.M60) {
      return '60分';
    }
    if (level === KLineLevel.M120) {
      return '120分';
    }
    if (level === KLineLevel.DAY) {
      return '日';
    }
    if (level === KLineLevel.WEEK) {
      return '周';
    }
    if (level === KLineLevel.MONTH) {
      return '月';
    }
    if (level === KLineLevel.QUARTER) {
      return '季';
    }
    return '年';
  }

  /**
   * 结果卡级别徽标：≤3 个级别直接写明组合（如「日+60分共振」），
   * 更多时显示「N级别共振」，下方级别 chips 列出全部命中级别。
   */
  private levelBadgeText(item: ScanResultItem): string {
    const n: number = item.levels.length;
    if (n <= 1) {
      return kLineLevelLabel(item.levels[0]);
    }
    if (n <= 3) {
      const parts: string[] = [];
      for (const lv of item.levels) {
        parts.push(this.levelShortLabel(lv));
      }
      return parts.join('+') + '共振';
    }
    return n + '级别共振';
  }

  /** 级别 chip 文案：级别名 + 顶/底命中数（跟随当前类型/日期筛选联动）。 */
  private levelChipText(item: ScanResultItem, level: KLineLevel): string {
    let top: number = 0;
    let bottom: number = 0;
    for (const d of this.divsAfterType(item)) {
      if (d.level === level) {
        if (d.divType === DivergenceType.TOP) {
          top++;
        } else {
          bottom++;
        }
      }
    }
    let s: string = kLineLevelLabel(level);
    if (top > 0) {
      s += ' 顶' + top;
    }
    if (bottom > 0) {
      s += ' 底' + bottom;
    }
    return s;
  }

  private divTextColor(d: DivergenceInfo): string {
    if (d.divType === DivergenceType.TOP) {
      return '#B388FF';
    }
    return '#4DD0E1';
  }

  private resultSortLabel(id: number): string {
    if (id === 1) {
      return '时间最新';
    }
    if (id === 2) {
      return '时间最早';
    }
    return '共振优先';
  }

  private resultSortColor(id: number): string {
    if (this.resultSort === id) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private isResultSortActive(id: number): boolean {
    return this.resultSort === id;
  }

  private filterTypeSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    const all: SelectOption = { value: '全部 ' + this.allResultCount() };
    opts.push(all);
    const top: SelectOption = { value: '顶背离 ' + this.topResultCount() };
    opts.push(top);
    const bottom: SelectOption = { value: '底背离 ' + this.bottomResultCount() };
    opts.push(bottom);
    return opts;
  }

  private filterTypeValueText(): string {
    if (this.filterType === 1) {
      return '顶背离 ' + this.topResultCount();
    }
    if (this.filterType === 2) {
      return '底背离 ' + this.bottomResultCount();
    }
    return '全部 ' + this.allResultCount();
  }

  private dateRangeSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const id of DATE_RANGE_IDS) {
      const opt: SelectOption = { value: this.dateRangeLabel(id) };
      opts.push(opt);
    }
    return opts;
  }

  private filterLevelSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    const all: SelectOption = { value: '全部级别' };
    opts.push(all);
    for (const level of this.scanLevels) {
      const opt: SelectOption = { value: kLineLevelLabel(level) };
      opts.push(opt);
    }
    return opts;
  }

  private filterLevelSelectedIndex(): number {
    if (this.filterLevel < 0) {
      return 0;
    }
    for (let i = 0; i < this.scanLevels.length; i++) {
      if (this.scanLevels[i] === this.filterLevel) {
        return i + 1;
      }
    }
    return 0;
  }

  private filterLevelValueText(): string {
    if (this.filterLevel < 0) {
      return '全部级别';
    }
    for (const level of this.scanLevels) {
      if (level === this.filterLevel) {
        return kLineLevelLabel(level);
      }
    }
    return '全部级别';
  }

  private onFilterLevelSelect(index: number): void {
    if (index <= 0) {
      this.filterLevel = -1;
      return;
    }
    this.filterLevel = this.scanLevels[index - 1];
  }

  private resultSortSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const id of RESULT_SORT_OPTIONS) {
      const opt: SelectOption = { value: this.resultSortLabel(id) };
      opts.push(opt);
    }
    return opts;
  }

  private filterChipColor(type: number): string {
    if (this.filterType === type) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private isFilterActive(type: number): boolean {
    return this.filterType === type;
  }

  private dateChipColor(id: number): string {
    if (this.dateRange === id) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private isDateActive(id: number): boolean {
    return this.dateRange === id;
  }

  private formatYmd(d: Date): string {
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mStr: string = m < 10 ? '0' + m : '' + m;
    const dStr: string = day < 10 ? '0' + day : '' + day;
    return d.getFullYear() + '-' + mStr + '-' + dStr;
  }

  private selectDateRange(id: number): void {
    if (id === 4) {
      this.showCustomStartPicker();
      return;
    }
    this.dateRange = id;
  }

  private showCustomStartPicker(): void {
    const now: Date = new Date();
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: now,
      selected: now,
      onDateAccept: (value: Date) => {
        this.customStart = this.formatYmd(value);
        this.showCustomEndPicker();
      }
    });
  }

  private showCustomEndPicker(): void {
    const now: Date = new Date();
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: now,
      selected: now,
      onDateAccept: (value: Date) => {
        let endStr: string = this.formatYmd(value);
        if (endStr < this.customStart) {
          const tmp: string = this.customStart;
          this.customStart = endStr;
          endStr = tmp;
        }
        this.customEnd = endStr;
        this.dateRange = 4;
      }
    });
  }

  private emptyPromptText(): string {
    if (this.results.length === 0) {
      return '扫描完成，未发现明显 MACD 背离。';
    }
    return '当前筛选条件下暂无背离结果。';
  }

  private resultBorderColor(item: ScanResultItem): string {
    return this.divTextColor(this.latestDivOf(item));
  }

  /** 摘要 hero 卡渐变（跟随主题强调色）。 */
  private heroGradColors(): Array<[ResourceColor, number]> {
    return [[this.t().accentFrom, 0], [this.t().accentTo, 1]];
  }

  /** 多级别共振结果数量。 */
  private resonanceCount(): number {
    let n: number = 0;
    for (const r of this.results) {
      if (r.levels.length > 1) {
        n++;
      }
    }
    return n;
  }

  private isInWatchlist(item: ScanResultItem): boolean {
    return this.watchlistCodes.indexOf(item.code) >= 0;
  }

  /** 轻提示 Toast（加自选成功/已在自选等反馈）。 */
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  /**
   * 扫描结果一键加自选：已在自选时弹提示不重复添加；
   * 已有分组时先弹分组选择；添加成功后递增 watchlist_version 通知主页刷新。
   */
  private async addToWatchlist(item: ScanResultItem): Promise<void> {
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    try {
      const existing: string[] = await WatchlistStore.loadCodes(context);
      if (existing.indexOf(item.code) >= 0) {
        this.watchlistCodes = existing;
        this.showToast('「' + item.name + '」已在自选股中');
        return;
      }
      const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
      if (groups.length > 0) {
        const names: string[] = [];
        for (const g of groups) {
          names.push(g.name);
        }
        this.pendingAddItem = item;
        this.pickerHint = '选择「' + item.name + '」加入的分组';
        this.pickerGroups = names;
        this.groupPickerController.open();
        return;
      }
      await this.finishAddToWatchlist(item, '');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'addToWatchlist failed: %{public}s', `${error}`);
      this.showToast('添加失败，请重试');
    }
  }

  /** 分组选择对话框回调：按所选分组落地添加。 */
  private onPickAddGroup(group: string): void {
    const item: ScanResultItem | null = this.pendingAddItem;
    this.pendingAddItem = null;
    if (item === null) {
      return;
    }
    this.finishAddToWatchlist(item, group);
  }

  private async finishAddToWatchlist(item: ScanResultItem, group: string): Promise<void> {
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    try {
      await WatchlistStore.addToGroup(context, item.code, group);
      const prev: number = AppStorage.get<number>('watchlist_version') ?? 0;
      AppStorage.setOrCreate<number>('watchlist_version', prev + 1);
      this.watchlistCodes = await WatchlistStore.loadCodes(context);
      this.showToast('已添加「' + item.name + '」'
        + (group !== '' ? '到分组「' + group + '」' : '到自选股'));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'finishAddToWatchlist failed: %{public}s', `${error}`);
      this.showToast('添加失败，请重试');
    }
  }

  private openDetail(item: ScanResultItem): void {
    const p: DetailNavParam = new DetailNavParam();
    p.code = item.code;
    p.name = item.name;
    this.navPathStack.pushPathByName('StockDetail', p);
  }

  /**
   * scanToken 保证切换级别时旧扫描循环立即失效，不干扰新一轮扫描状态。
   */
  private async startScan(): Promise<void> {
    const token: number = this.scanToken + 1;
    this.scanToken = token;
    this.isScanning = true;
    this.loadErr = '';
    this.results = [];
    this.scannedCount = 0;
    this.failCount = 0;
    this.totalCount = 0;
    try {
      const targets: MarketRef[] = await this.loadTargets();
      if (this.scanToken !== token) {
        return;
      }
      this.totalCount = targets.length;
      if (targets.length === 0) {
        this.loadErr = '未获取到待扫描标的，请检查网络或先添加自选股';
        this.isScanning = false;
        return;
      }
      for (let i = 0; i < targets.length; i += SCAN_BATCH) {
        if (this.cancelled || this.scanToken !== token) {
          return;
        }
        const end: number = Math.min(targets.length, i + SCAN_BATCH);
        const batch: MarketRef[] = targets.slice(i, end);
        const tasks: Promise<void>[] = [];
        for (const target of batch) {
          tasks.push(this.scanOne(target));
        }
        await Promise.all(tasks);
        if (this.scanToken !== token) {
          return;
        }
        this.scannedCount = end;
      }
    } catch (error) {
      if (this.scanToken === token) {
        hilog.error(DOMAIN, TAG, 'startScan failed: %{public}s', `${error}`);
        this.loadErr = '扫描初始化失败，请检查网络后重试';
        this.isScanning = false;
      }
      return;
    }
    if (this.scanToken === token) {
      this.isScanning = false;
    }
  }

  private async loadTargets(): Promise<MarketRef[]> {
    if (this.category === 'astock') {
      return MarketApi.fetchTopStocks(this.scanCount, this.scanSort);
    }
    if (this.category === 'etf') {
      return MarketApi.fetchTopEtfs(this.scanCount, this.scanSort);
    }
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    let codes: string[] = [];
    if (this.isGroupCategory()) {
      const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
      for (const g of groups) {
        if (g.name === this.groupNameOfCategory()) {
          codes = g.codes.slice();
        }
      }
    } else {
      codes = await WatchlistStore.loadCodes(context);
    }
    if (codes.length === 0) {
      return [];
    }
    const quotes: StockQuote[] = await StockApi.fetchQuotes(codes);
    const refs: MarketRef[] = [];
    for (const q of quotes) {
      refs.push(new MarketRef(q.code, q.name, q.price));
    }
    return refs;
  }

  /**
   * 多级别共振扫描核心：对单个标的依次拉取所选级别的 K 线并检测背离，
   * 命中级别汇总为 levels（多级别即共振），全部背离合并进一条结果。
   */
  private async scanOne(target: MarketRef): Promise<void> {
    const hitLevels: KLineLevel[] = [];
    const allDivs: DivergenceInfo[] = [];
    let lastClose: number = 0;
    for (const level of this.scanLevels) {
      try {
        const klines: KLineItem[] = await StockApi.fetchKLines(target.code, level);
        lastClose = klines[klines.length - 1].close;
        const macd: MacdPoint[] = MacdAnalyzer.calcMacd(klines);
        const divs: DivergenceInfo[] =
          MacdAnalyzer.detectDivergence(klines, macd, level);
        if (divs.length > 0) {
          hitLevels.push(level);
          for (const d of divs) {
            allDivs.push(d);
          }
        }
      } catch (error) {
        this.failCount++;
      }
    }
    if (hitLevels.length > 0) {
      hitLevels.sort((a: KLineLevel, b: KLineLevel): number =>
        ALL_KLINE_LEVELS.indexOf(a) - ALL_KLINE_LEVELS.indexOf(b));
      this.results.push(new ScanResultItem(target.code, target.name,
        lastClose, hitLevels, allDivs));
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column({ space: 10 }) {
          Row() {
            Text(this.scanTitleText())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
            Blank()
            Text(this.categoryTitle())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(10)
          }
          .width('100%')

          Text(this.scopeDescText())
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.78)')
            .width('100%')

          if (this.isScanning) {
            Progress({ value: this.scannedCount, total: Math.max(1, this.totalCount),
              type: ProgressType.Linear })
              .width('100%')
              .height(6)
              .color('#FFFFFF')
              .backgroundColor('#33FFFFFF')
              .borderRadius(3)

            Row() {
              Text(this.progressText())
                .fontSize(12)
                .fontColor('rgba(255,255,255,0.85)')
              Blank()
            }
            .width('100%')
          } else if (this.totalCount > 0) {
            Row() {
              Column({ space: 2 }) {
                Text(`${this.results.length}`)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                Text('背离标的')
                  .fontSize(10)
                  .fontColor('rgba(255,255,255,0.75)')
              }
              .layoutWeight(1)

              Column({ space: 2 }) {
                Text(`${this.resonanceCount()}`)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                Text('多级别共振')
                  .fontSize(10)
                  .fontColor('rgba(255,255,255,0.75)')
              }
              .layoutWeight(1)

              Column({ space: 2 }) {
                Text(`${this.failCount}`)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                Text('拉取失败')
                  .fontSize(10)
                  .fontColor('rgba(255,255,255,0.75)')
              }
              .layoutWeight(1)
            }
            .width('100%')
          }
        }
        .width('100%')
        .margin({ left: 16, right: 16, top: 12 })
        .padding(16)
        .linearGradient({ angle: 120, colors: this.heroGradColors() })
        .borderRadius(16)
        .shadow({ radius: 10, color: this.t().shadowColor, offsetY: 4 })

        if (this.loadErr !== '') {
          Text(this.loadErr)
            .fontSize(13)
            .fontColor('#FF6B6B')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 8 })
        }

        if (this.results.length > 0) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Select(this.filterTypeSelectOptions())
                .selected(this.filterType)
                .value('类型：' + this.filterTypeValueText())
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
                  this.filterType = index;
                })

              Select(this.dateRangeSelectOptions())
                .selected(DATE_RANGE_IDS.indexOf(this.dateRange))
                .value('日期：' + this.dateRangeLabel(this.dateRange))
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
                  this.selectDateRange(DATE_RANGE_IDS[index]);
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              if (this.scanLevels.length > 1) {
                Select(this.filterLevelSelectOptions())
                  .selected(this.filterLevelSelectedIndex())
                  .value('级别：' + this.filterLevelValueText())
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
                    this.onFilterLevelSelect(index);
                  })
              }

              Select(this.resultSortSelectOptions())
                .selected(RESULT_SORT_OPTIONS.indexOf(this.resultSort))
                .value('结果：' + this.resultSortLabel(this.resultSort))
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
                  this.resultSort = RESULT_SORT_OPTIONS[index];
                })
            }
            .width('100%')

            if (this.dateRange === 4 && this.customStart !== '') {
              Text('自定义区间：' + this.customStart + ' 至 ' + this.customEnd
                + '（含首尾）· 点击"自定义"可重新选择')
                .fontSize(11)
                .fontColor(this.t().textTertiary)
                .width('100%')
            }
          }
          .width('100%')
          .margin({ left: 16, right: 16, top: 10 })
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(this.t().card)
          .borderRadius(16)
          .border({ width: 1, color: this.t().cardBorder })
          .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })
        }

        if (!this.isScanning && this.totalCount > 0 && this.loadErr === ''
          && this.filteredResults().length === 0) {
          Column({ space: 10 }) {
            Stack() {
              Column()
                .width(72)
                .height(72)
                .backgroundColor(this.t().inputBg)
                .borderRadius(36)
              Text('🔍')
                .fontSize(30)
            }
            Text(this.emptyPromptText())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textSecondary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 28, bottom: 28 })
        } else {
          List({ space: 10 }) {
            ForEach(this.filteredResults(), (item: ScanResultItem) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row() {
                    Column() {
                      Text(item.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.t().textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(item.code.toUpperCase() + ' · 收 ' + item.lastClose.toFixed(2))
                        .fontSize(11)
                        .fontColor(this.t().textSecondary)
                        .margin({ top: 3 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(this.levelBadgeText(item))
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isResonance(item) ? '#FFFFFF' : this.t().textSecondary)
                      .linearGradient({ angle: 135, colors: this.chipGrad(this.isResonance(item)) })
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .borderRadius(12)
                      .maxLines(1)
                  }
                  .width('100%')

                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(item.levels, (lv: KLineLevel) => {
                      Text(this.levelChipText(item, lv))
                        .fontSize(11)
                        .fontColor(this.t().textPrimary)
                        .backgroundColor(this.t().inputBg)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(10)
                        .margin({ right: 6, bottom: 4 })
                    }, (lv: KLineLevel) => lv.toString() + '-' + item.code)
                  }
                  .width('100%')

                  Row({ space: 12 }) {
                    Text('顶背离 ' + this.itemTopCount(item) + ' 处')
                      .fontSize(11)
                      .fontColor('#B388FF')
                    Text('底背离 ' + this.itemBottomCount(item) + ' 处')
                      .fontSize(11)
                      .fontColor('#4DD0E1')
                  }
                  .width('100%')

                  ForEach(this.itemDivList(item), (d: DivergenceInfo) => {
                    Text(d.desc)
                      .fontSize(11)
                      .fontColor(this.divTextColor(d))
                      .lineHeight(16)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }, (d: DivergenceInfo) => item.code + '-' + d.level.toString()
                    + '-' + d.indexB.toString())

                  if (this.itemMoreCount(item) > 0) {
                    Text('其余 ' + this.itemMoreCount(item) + ' 处背离，点击卡片查看全部')
                      .fontSize(11)
                      .fontColor(this.t().textTertiary)
                      .width('100%')
                  }

                  Row() {
                    Blank()
                    Text(this.isInWatchlist(item) ? '✓ 已自选' : '+ 加自选')
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isInWatchlist(item)
                        ? this.t().textTertiary : this.t().accent)
                      .backgroundColor(this.t().inputBg)
                      .border({
                        width: 1,
                        color: this.isInWatchlist(item)
                          ? this.t().cardBorder : this.t().accent
                      })
                      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                      .borderRadius(12)
                      .onClick(() => {
                        this.addToWatchlist(item);
                      })
                  }
                  .width('100%')
                  .margin({ top: 2 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(16)
                .backgroundColor(this.t().card)
                .border({
                  width: { left: 3, top: 1, right: 1, bottom: 1 },
                  color: {
                    left: this.resultBorderColor(item),
                    top: this.t().cardBorder,
                    right: this.t().cardBorder,
                    bottom: this.t().cardBorder
                  }
                })
                .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })
                .onClick(() => {
                  this.openDetail(item);
                })
              }
            }, (item: ScanResultItem) => item.code + '-' + this.resultSort.toString()
              + '-' + this.filterType.toString() + '-' + this.dateRange.toString()
              + '-' + this.filterLevel.toString()
              + '-' + (this.isInWatchlist(item) ? '1' : '0'))
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.t().bg)
    }
    .title('背离扫描报告')
    .backgroundColor(this.t().bg)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const rawParam: Record<string, Object> =
        ctx.pathInfo.param as Record<string, Object>;
      if (rawParam !== null && rawParam !== undefined) {
        const catVal: Object | undefined = rawParam['category'];
        if (typeof catVal === 'string') {
          this.category = catVal;
        }
      }
      this.initScan();
    })
  }

  private async initScan(): Promise<void> {
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    this.scanCount = await SettingsStore.loadScanCount(context);
    this.scanSort = await SettingsStore.loadScanSort(context);
    this.scanLevels = await SettingsStore.loadScanLevels(context);
    this.watchlistCodes = await WatchlistStore.loadCodes(context);
    // 扫描标的指向已删分组时回落到全部自选
    if (this.isGroupCategory()) {
      const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(context);
      const names: string[] = [];
      for (const g of groups) {
        names.push(g.name);
      }
      if (names.indexOf(this.groupNameOfCategory()) < 0) {
        this.category = 'watchlist';
      }
    }
    await this.startScan();
  }
}
