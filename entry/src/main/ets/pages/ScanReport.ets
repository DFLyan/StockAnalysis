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
import { WatchlistStore } from '../store/WatchlistStore';
import { SettingsStore } from '../store/SettingsStore';
import { ThemeColors, themeColors } from '../model/Theme';

const DOMAIN: number = 0x0003;
const TAG: string = 'ScanReport';
const SCAN_BATCH: number = 6;
const SCAN_COUNT_OPTIONS: number[] = [50, 100, 200, 500];
const SCAN_SORT_OPTIONS: string[] = ['f6', 'f20', 'f3', 'f8'];
const DATE_RANGE_IDS: number[] = [0, 1, 2, 3, 4];
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
  @State customStart: string = '';
  @State customEnd: string = '';
  @State showCustomCount: boolean = false;
  @State customCountInput: string = '';
  @State customCountErr: string = '';
  @StorageLink('theme_index') themeIndex: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();
  private cancelled: boolean = false;
  private scanToken: number = 0;

  aboutToDisappear(): void {
    this.cancelled = true;
  }

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private categoryTitle(): string {
    if (this.category === 'astock') {
      return '全市场个股';
    }
    if (this.category === 'etf') {
      return '全市场ETF';
    }
    return '自选股';
  }

  private scanTitleText(): string {
    if (this.scanLevels.length === 1) {
      return kLineLevelLabel(this.scanLevels[0]) + ' MACD 背离扫描';
    }
    return '多级别 MACD 背离扫描（' + this.scanLevels.length + '个级别）';
  }

  private scopeDescText(): string {
    if (this.category === 'astock') {
      return '按' + this.sortLabel(this.scanSort) + '排名前 ' + this.scanCount + ' 只个股';
    }
    if (this.category === 'etf') {
      return '按' + this.sortLabel(this.scanSort) + '排名前 ' + this.scanCount + ' 只ETF（剔除货币/债券）';
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

  private sortChipColor(fid: string): string {
    if (this.scanSort === fid) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private sortChipBg(fid: string): string {
    if (this.scanSort === fid) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
  }

  private async changeScanSort(fid: string): Promise<void> {
    if (this.scanSort === fid) {
      return;
    }
    this.scanSort = fid;
    this.filterType = 0;
    this.dateRange = 0;
    this.filterLevel = -1;
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    await SettingsStore.saveScanSort(context, fid);
    await this.startScan();
  }

  private isMarketScan(): boolean {
    return this.category === 'astock' || this.category === 'etf';
  }

  private scanCountLabel(n: number): string {
    return '前' + n;
  }

  private scanCountColor(n: number): string {
    if (this.scanCount === n) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private scanCountBg(n: number): string {
    if (this.scanCount === n) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
  }

  private async changeScanCount(n: number): Promise<void> {
    if (this.scanCount === n) {
      return;
    }
    this.scanCount = n;
    this.filterType = 0;
    this.dateRange = 0;
    this.filterLevel = -1;
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    await SettingsStore.saveScanCount(context, n);
    await this.startScan();
  }

  private isCustomCount(): boolean {
    return SCAN_COUNT_OPTIONS.indexOf(this.scanCount) < 0;
  }

  private customChipLabel(): string {
    if (this.isCustomCount()) {
      return '自定义 ' + this.scanCount;
    }
    return '自定义';
  }

  private customChipColor(): string {
    if (this.isCustomCount()) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private customChipBg(): string {
    if (this.isCustomCount()) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
  }

  private openCustomCount(): void {
    this.customCountInput = this.scanCount.toString();
    this.customCountErr = '';
    this.showCustomCount = !this.showCustomCount;
  }

  private async applyCustomCount(): Promise<void> {
    const input: string = this.customCountInput.trim();
    const n: number = Number(input);
    if (input === '' || isNaN(n) || n < 10 || n > 2000 || Math.floor(n) !== n) {
      this.customCountErr = '请输入 10 - 2000 的整数';
      return;
    }
    this.showCustomCount = false;
    this.customCountErr = '';
    if (n === this.scanCount) {
      return;
    }
    this.scanCount = n;
    this.filterType = 0;
    this.dateRange = 0;
    this.filterLevel = -1;
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    await SettingsStore.saveScanCount(context, n);
    await this.startScan();
  }

  private progressText(): string {
    if (this.totalCount <= 0) {
      return '正在获取标的列表...';
    }
    return '已扫描 ' + this.scannedCount + ' / ' + this.totalCount;
  }

  private resultSummaryText(): string {
    let text: string = '发现背离 ' + this.results.length + ' 条';
    if (this.failCount > 0) {
      text = text + ' · 失败 ' + this.failCount + ' 项';
    }
    return text;
  }

  private isLevelSelected(level: KLineLevel): boolean {
    return this.scanLevels.indexOf(level) >= 0;
  }

  private scanLevelColor(level: KLineLevel): string {
    if (this.isLevelSelected(level)) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private scanLevelBg(level: KLineLevel): string {
    if (this.isLevelSelected(level)) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
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
    this.filterType = 0;
    this.dateRange = 0;
    this.filterLevel = -1;
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    await SettingsStore.saveScanLevels(context, this.scanLevels);
    await this.startScan();
  }

  private levelFilterColor(level: number): string {
    if (this.filterLevel === level) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private levelFilterBg(level: number): string {
    if (this.filterLevel === level) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
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
   * 解析 "YYYY-MM-DD" 或 "YYYY-MM-DD HH:mm" 前10位，返回当天0点时间戳；
   * 无法解析返回 NaN。
   */
  private parseYmd(dateStr: string): number {
    if (dateStr.length < 10) {
      return NaN;
    }
    const y: number = Number(dateStr.substring(0, 4));
    const m: number = Number(dateStr.substring(5, 7));
    const d: number = Number(dateStr.substring(8, 10));
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
      return NaN;
    }
    const time: number = new Date(y, m - 1, d).getTime();
    if (isNaN(time)) {
      return NaN;
    }
    return time;
  }

  /**
   * 日期筛选：按"最近一次背离"的日期判断。
   * 自定义区间含首尾两天；无法解析时保守保留该结果。
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

  private dateFiltered(): ScanResultItem[] {
    if (this.dateRangeDays() <= 0 && this.dateRange !== 4) {
      return this.results;
    }
    return this.results.filter((r: ScanResultItem) => this.inDateRange(r.latestDate));
  }

  private topResultCount(): number {
    let n: number = 0;
    for (const r of this.dateFiltered()) {
      if (r.topCount > 0) {
        n++;
      }
    }
    return n;
  }

  private bottomResultCount(): number {
    let n: number = 0;
    for (const r of this.dateFiltered()) {
      if (r.bottomCount > 0) {
        n++;
      }
    }
    return n;
  }

  private filteredResults(): ScanResultItem[] {
    const base: ScanResultItem[] = this.dateFiltered();
    let filtered: ScanResultItem[] = base;
    if (this.filterType === 1) {
      filtered = filtered.filter((r: ScanResultItem) => r.topCount > 0);
    }
    if (this.filterType === 2) {
      filtered = filtered.filter((r: ScanResultItem) => r.bottomCount > 0);
    }
    if (this.filterLevel >= 0) {
      filtered = filtered.filter((r: ScanResultItem) => r.level === this.filterLevel);
    }
    return filtered;
  }

  private filterChipColor(type: number): string {
    if (this.filterType === type) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private filterChipBg(type: number): string {
    if (this.filterType === type) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
  }

  private dateChipColor(id: number): string {
    if (this.dateRange === id) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private dateChipBg(id: number): string {
    if (this.dateRange === id) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
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
    if (item.isTop) {
      return '#B388FF';
    }
    return '#4DD0E1';
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
    const codes: string[] = await WatchlistStore.loadCodes(context);
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

  private async scanOne(target: MarketRef): Promise<void> {
    for (const level of this.scanLevels) {
      try {
        const klines: KLineItem[] = await StockApi.fetchKLines(target.code, level);
        const macd: MacdPoint[] = MacdAnalyzer.calcMacd(klines);
        const divs: DivergenceInfo[] =
          MacdAnalyzer.detectDivergence(klines, macd, level);
        if (divs.length === 0) {
          continue;
        }
        let top: number = 0;
        let bottom: number = 0;
        for (const d of divs) {
          if (d.divType === DivergenceType.TOP) {
            top++;
          } else {
            bottom++;
          }
        }
        // detectDivergence 按时间降序返回，divs[0] 为最近一次背离
        const latest: DivergenceInfo = divs[0];
        this.results.push(new ScanResultItem(target.code, target.name,
          klines[klines.length - 1].close, top, bottom, latest.desc,
          latest.dateB, latest.divType === DivergenceType.TOP, level));
      } catch (error) {
        this.failCount++;
      }
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column({ space: 8 }) {
          Row() {
            Text(this.scanTitleText())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
            Blank()
            Text(this.categoryTitle())
              .fontSize(13)
              .fontColor('#4E9CF8')
          }
          .width('100%')

          Text(this.scopeDescText())
            .fontSize(11)
            .fontColor(this.t().textTertiary)
            .width('100%')

          Progress({ value: this.scannedCount, total: Math.max(1, this.totalCount),
            type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color('#2A5BD7')
            .backgroundColor(this.t().inputBg)
            .borderRadius(3)

          Row() {
            Text(this.progressText())
              .fontSize(12)
              .fontColor(this.t().textSecondary)
            Blank()
            if (!this.isScanning && this.totalCount > 0) {
              Text(this.resultSummaryText())
                .fontSize(12)
                .fontColor(this.t().textPrimary)
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor(this.t().card)

        Flex({ wrap: FlexWrap.Wrap }) {
          Text('级别')
            .fontSize(12)
            .fontColor(this.t().textTertiary)
            .margin(4)
          ForEach(ALL_KLINE_LEVELS, (level: KLineLevel) => {
            Text(kLineLevelLabel(level))
              .fontSize(12)
              .fontColor(this.scanLevelColor(level))
              .backgroundColor(this.scanLevelBg(level))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .margin(4)
              .onClick(() => {
                this.toggleScanLevel(level);
              })
          }, (level: KLineLevel) => level.toString() + '-'
            + (this.isLevelSelected(level) ? '1' : '0'))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 4 })

        if (this.isMarketScan()) {
          Flex({ wrap: FlexWrap.Wrap }) {
            Text('范围')
              .fontSize(12)
              .fontColor(this.t().textTertiary)
              .margin(4)
            ForEach(SCAN_COUNT_OPTIONS, (n: number) => {
              Text(this.scanCountLabel(n))
                .fontSize(12)
                .fontColor(this.scanCountColor(n))
                .backgroundColor(this.scanCountBg(n))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(14)
                .margin(4)
                .onClick(() => {
                  this.showCustomCount = false;
                  this.changeScanCount(n);
                })
            }, (n: number) => n.toString() + '-' + this.scanCount.toString())
            Text(this.customChipLabel())
              .fontSize(12)
              .fontColor(this.customChipColor())
              .backgroundColor(this.customChipBg())
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .margin(4)
              .onClick(() => {
                this.openCustomCount();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })

          if (this.showCustomCount) {
            Row({ space: 8 }) {
              TextInput({ text: this.customCountInput, placeholder: '输入 10 - 2000 的整数' })
                .type(InputType.Number)
                .fontSize(12)
                .height(36)
                .layoutWeight(1)
                .backgroundColor(this.t().inputBg)
                .borderRadius(8)
                .padding({ left: 10, right: 10 })
                .onChange((value: string) => {
                  this.customCountInput = value;
                })
              Text('确定')
                .fontSize(12)
                .fontColor('#FFFFFF')
                .backgroundColor('#2A5BD7')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .borderRadius(14)
                .onClick(() => {
                  this.applyCustomCount();
                })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 2, bottom: 2 })

            if (this.customCountErr !== '') {
              Text(this.customCountErr)
                .fontSize(11)
                .fontColor('#FF6B6B')
                .width('100%')
                .padding({ left: 24, bottom: 2 })
            }
          }

          Flex({ wrap: FlexWrap.Wrap }) {
            Text('排序')
              .fontSize(12)
              .fontColor(this.t().textTertiary)
              .margin(4)
            ForEach(SCAN_SORT_OPTIONS, (fid: string) => {
              Text(this.sortLabel(fid))
                .fontSize(12)
                .fontColor(this.sortChipColor(fid))
                .backgroundColor(this.sortChipBg(fid))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(14)
                .margin(4)
                .onClick(() => {
                  this.changeScanSort(fid);
                })
            }, (fid: string) => fid + '-' + this.scanSort)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        }

        if (this.loadErr !== '') {
          Text(this.loadErr)
            .fontSize(13)
            .fontColor('#FF6B6B')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 8 })
        }

        if (this.results.length > 0) {
          Row({ space: 8 }) {
            Text('全部 ' + this.dateFiltered().length)
              .fontSize(12)
              .fontColor(this.filterChipColor(0))
              .backgroundColor(this.filterChipBg(0))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .onClick(() => {
                this.filterType = 0;
              })
            Text('顶背离 ' + this.topResultCount())
              .fontSize(12)
              .fontColor(this.filterChipColor(1))
              .backgroundColor(this.filterChipBg(1))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .onClick(() => {
                this.filterType = 1;
              })
            Text('底背离 ' + this.bottomResultCount())
              .fontSize(12)
              .fontColor(this.filterChipColor(2))
              .backgroundColor(this.filterChipBg(2))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .onClick(() => {
                this.filterType = 2;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 4 })

          Row({ space: 8 }) {
            ForEach(DATE_RANGE_IDS, (id: number) => {
              Text(this.dateRangeLabel(id))
                .fontSize(12)
                .fontColor(this.dateChipColor(id))
                .backgroundColor(this.dateChipBg(id))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(14)
                .onClick(() => {
                  this.selectDateRange(id);
                })
            }, (id: number) => id.toString() + '-' + this.dateRange.toString())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 2 })

          if (this.scanLevels.length > 1) {
            Flex({ wrap: FlexWrap.Wrap }) {
              Text('全部级别')
                .fontSize(12)
                .fontColor(this.levelFilterColor(-1))
                .backgroundColor(this.levelFilterBg(-1))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(14)
                .margin({ left: 0, right: 4 })
                .onClick(() => {
                  this.filterLevel = -1;
                })
              ForEach(this.scanLevels, (level: KLineLevel) => {
                Text(kLineLevelLabel(level))
                  .fontSize(12)
                  .fontColor(this.levelFilterColor(level))
                  .backgroundColor(this.levelFilterBg(level))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .margin(4)
                  .onClick(() => {
                    this.filterLevel = level;
                  })
              }, (level: KLineLevel) => level.toString() + '-' + this.filterLevel.toString())
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 2, bottom: 2 })
          }

          if (this.dateRange === 4 && this.customStart !== '') {
            Text('自定义区间：' + this.customStart + ' 至 ' + this.customEnd
              + '（含首尾）· 点击"自定义"可重新选择')
              .fontSize(11)
              .fontColor(this.t().textTertiary)
              .width('100%')
              .padding({ left: 20, bottom: 4 })
          }
        }

        if (!this.isScanning && this.totalCount > 0 && this.loadErr === ''
          && this.filteredResults().length === 0) {
          Text(this.emptyPromptText())
            .fontSize(13)
            .fontColor(this.t().textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else {
          List({ space: 8 }) {
            ForEach(this.filteredResults(), (item: ScanResultItem) => {
              ListItem() {
                Column({ space: 6 }) {
                  Row() {
                    Column() {
                      Text(item.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.t().textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(item.code.toUpperCase() + ' · ' + kLineLevelLabel(item.level)
                        + ' · 收 ' + item.lastClose.toFixed(2))
                        .fontSize(11)
                        .fontColor(this.t().textSecondary)
                        .margin({ top: 3 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Column() {
                      Text('顶背离 ' + item.topCount + ' 处')
                        .fontSize(11)
                        .fontColor('#B388FF')
                      Text('底背离 ' + item.bottomCount + ' 处')
                        .fontSize(11)
                        .fontColor('#4DD0E1')
                        .margin({ top: 3 })
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                  .width('100%')

                  Text(item.latestDivDesc)
                    .fontSize(11)
                    .fontColor(this.resultBorderColor(item))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .width('100%')
                .padding(12)
                .borderRadius(10)
                .backgroundColor(this.t().card)
                .border({ width: 1, color: this.resultBorderColor(item) })
                .onClick(() => {
                  this.openDetail(item);
                })
              }
            }, (item: ScanResultItem) => item.code + '-' + item.level.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 4, bottom: 12 })
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
    await this.startScan();
  }
}
