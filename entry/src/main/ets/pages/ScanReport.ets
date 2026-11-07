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
import { ThemeColors, themeColors } from '../model/Theme';

const DOMAIN: number = 0x0003;
const TAG: string = 'ScanReport';
const SCAN_BATCH: number = 6;
const SCAN_MARKET_COUNT: number = 200;
const DATE_RANGE_IDS: number[] = [0, 1, 2, 3, 4];
const DAY_MS: number = 86400000;

@Builder
export function ScanReportBuilder(): void {
  ScanReport()
}

/**
 * 一键背离扫描报告页：支持 30分/60分/日/周 级别切换（切换后重新扫描），
 * 范围支持自选股 / 全市场个股 / 全市场ETF（按成交额前200，ETF 剔除货币债券）。
 * 结果支持按背离类型（顶/底）与日期（近1周/1月/3月/自定义区间）筛选。
 */
@Component
export struct ScanReport {
  @State category: string = 'watchlist';
  @State scanLevel: KLineLevel = KLineLevel.DAY;
  @State isScanning: boolean = false;
  @State scannedCount: number = 0;
  @State totalCount: number = 0;
  @State failCount: number = 0;
  @State results: ScanResultItem[] = [];
  @State loadErr: string = '';
  @State filterType: number = 0;
  @State dateRange: number = 0;
  @State customStart: string = '';
  @State customEnd: string = '';
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

  private scopeDescText(): string {
    if (this.category === 'astock') {
      return '按成交额排名前 ' + SCAN_MARKET_COUNT + ' 只个股';
    }
    if (this.category === 'etf') {
      return '按成交额排名前 ' + SCAN_MARKET_COUNT + ' 只ETF（剔除货币/债券）';
    }
    return '自选股全部标的';
  }

  private progressText(): string {
    if (this.totalCount <= 0) {
      return '正在获取标的列表...';
    }
    return '已扫描 ' + this.scannedCount + ' / ' + this.totalCount;
  }

  private resultSummaryText(): string {
    let text: string = '发现背离 ' + this.results.length + ' 只';
    if (this.failCount > 0) {
      text = text + ' · 失败 ' + this.failCount + ' 只';
    }
    return text;
  }

  private scanLevelColor(level: KLineLevel): string {
    if (this.scanLevel === level) {
      return '#FFFFFF';
    }
    return this.t().textSecondary;
  }

  private scanLevelBg(level: KLineLevel): string {
    if (this.scanLevel === level) {
      return '#2A5BD7';
    }
    return this.t().inputBg;
  }

  private changeScanLevel(level: KLineLevel): void {
    if (this.scanLevel === level) {
      return;
    }
    this.scanLevel = level;
    this.filterType = 0;
    this.dateRange = 0;
    this.startScan();
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
    if (this.filterType === 1) {
      return base.filter((r: ScanResultItem) => r.topCount > 0);
    }
    if (this.filterType === 2) {
      return base.filter((r: ScanResultItem) => r.bottomCount > 0);
    }
    return base;
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
      return MarketApi.fetchTopStocks(SCAN_MARKET_COUNT);
    }
    if (this.category === 'etf') {
      return MarketApi.fetchTopEtfs(SCAN_MARKET_COUNT);
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
    try {
      const klines: KLineItem[] = await StockApi.fetchKLines(target.code, this.scanLevel);
      const macd: MacdPoint[] = MacdAnalyzer.calcMacd(klines);
      const divs: DivergenceInfo[] =
        MacdAnalyzer.detectDivergence(klines, macd, this.scanLevel);
      if (divs.length === 0) {
        return;
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
        latest.dateB, latest.divType === DivergenceType.TOP));
    } catch (error) {
      this.failCount++;
    }
  }

  build() {
    NavDestination() {
      Column() {
        Column({ space: 8 }) {
          Row() {
            Text(kLineLevelLabel(this.scanLevel) + ' MACD 背离扫描')
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

        Row({ space: 8 }) {
          Text('级别')
            .fontSize(12)
            .fontColor(this.t().textTertiary)
          ForEach(ALL_KLINE_LEVELS, (level: KLineLevel) => {
            Text(kLineLevelLabel(level))
              .fontSize(12)
              .fontColor(this.scanLevelColor(level))
              .backgroundColor(this.scanLevelBg(level))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .onClick(() => {
                this.changeScanLevel(level);
              })
          }, (level: KLineLevel) => level.toString() + '-' + this.scanLevel.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 4 })

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
                      Text(item.code.toUpperCase() + ' · 收 ' + item.lastClose.toFixed(2))
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
            }, (item: ScanResultItem) => item.code)
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
      this.startScan();
    })
  }
}
