import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ALL_KLINE_LEVELS,
  DivergenceInfo,
  DivergenceType,
  KLineItem,
  KLineLevel,
  LevelAnalysisResult,
  MacdPoint,
  kLineLevelLabel
} from '../model/StockModels';
import { StockApi } from '../data/StockApi';
import { AiClient } from '../data/AiClient';
import { MacdAnalyzer } from '../analysis/MacdAnalyzer';
import { ChartRenderer } from '../chart/ChartRenderer';
import { SettingsStore } from '../store/SettingsStore';
import { ThemeColors, themeColors } from '../model/Theme';

const DOMAIN: number = 0x0002;
const TAG: string = 'StockDetail';

@Builder
export function StockDetailBuilder(): void {
  StockDetail()
}

@Component
export struct StockDetail {
  @State stockCode: string = '';
  @State stockName: string = '';
  @State currentLevel: KLineLevel = KLineLevel.DAY;
  @State klines: KLineItem[] = [];
  @State macdPoints: MacdPoint[] = [];
  @State divergences: DivergenceInfo[] = [];
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State dataTime: string = '';
  @State axisFontScale: number = 1.0;
  @State crosshairIndex: number = -1;
  @State aiLoading: boolean = false;
  @State aiResult: string = '';
  @State aiErr: string = '';
  @StorageLink('theme_index') themeIndex: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  private aiBaseUrl: string = '';
  private aiApiKey: string = '';
  private aiModel: string = '';
  private levelCache: Map<number, LevelAnalysisResult> = new Map<number, LevelAnalysisResult>();
  private klineCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private macdCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private klineReady: boolean = false;
  private macdReady: boolean = false;
  private klineWidth: number = 0;
  private visibleCount: number = 100;
  private scrollOffset: number = 0;
  private panStartOffset: number = 0;
  private pinchStartCount: number = 100;

  private titleText(): string {
    if (this.stockName !== '') {
      return this.stockName;
    }
    return this.stockCode;
  }

  private lastCloseText(): string {
    if (this.klines.length === 0) {
      return '';
    }
    const last: KLineItem = this.klines[this.klines.length - 1];
    return '最新收盘 ' + last.close.toFixed(2);
  }

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private levelTabColor(level: KLineLevel): string {
    if (this.currentLevel === level) {
      return '#FFFFFF';
    }
    return '#8A90A0';
  }

  private levelTabBg(level: KLineLevel): string {
    if (this.currentLevel === level) {
      return '#2A5BD7';
    }
    return '#1E2130';
  }

  private topCount(): number {
    let n: number = 0;
    for (const d of this.divergences) {
      if (d.divType === DivergenceType.TOP) {
        n++;
      }
    }
    return n;
  }

  private bottomCount(): number {
    let n: number = 0;
    for (const d of this.divergences) {
      if (d.divType === DivergenceType.BOTTOM) {
        n++;
      }
    }
    return n;
  }

  private summaryText(): string {
    if (this.divergences.length === 0) {
      return '';
    }
    return '顶背离 ' + this.topCount() + ' 处 · 底背离 ' + this.bottomCount() + ' 处';
  }

  private divColor(div: DivergenceInfo): string {
    if (div.divType === DivergenceType.TOP) {
      return '#B388FF';
    }
    return '#4DD0E1';
  }

  private fontScaleText(): string {
    return this.axisFontScale.toFixed(2) + 'x';
  }

  private onChartTap(x: number): void {
    if (this.klines.length === 0) {
      return;
    }
    const perBar: number = this.pxPerBar();
    if (perBar <= 0) {
      return;
    }
    const endIndex: number = this.klines.length - this.scrollOffset;
    const startIndex: number = Math.max(0, endIndex - this.visibleCount);
    let idx: number = startIndex + Math.floor((x - 6) / perBar);
    if (idx < startIndex) {
      idx = startIndex;
    }
    const lastIdx: number = endIndex - 1;
    if (idx > lastIdx) {
      idx = lastIdx;
    }
    if (idx < 0) {
      return;
    }
    if (idx === this.crosshairIndex) {
      this.crosshairIndex = -1;
    } else {
      this.crosshairIndex = idx;
    }
    this.drawAll();
  }

  private infoIndex(): number {
    if (this.crosshairIndex >= 0 && this.crosshairIndex < this.klines.length) {
      return this.crosshairIndex;
    }
    return this.klines.length - 1;
  }

  private infoDateText(): string {
    const i: number = this.infoIndex();
    if (i < 0) {
      return '';
    }
    const d: string = this.klines[i].date;
    if (d.indexOf('-') >= 0) {
      return d;
    }
    if (d.length >= 12) {
      return d.substring(0, 4) + '-' + d.substring(4, 6) + '-' + d.substring(6, 8) +
        ' ' + d.substring(8, 10) + ':' + d.substring(10, 12);
    }
    return d;
  }

  private infoOpenText(): string {
    const i: number = this.infoIndex();
    if (i < 0) {
      return '--';
    }
    return this.klines[i].open.toFixed(2);
  }

  private infoHighText(): string {
    const i: number = this.infoIndex();
    if (i < 0) {
      return '--';
    }
    return this.klines[i].high.toFixed(2);
  }

  private infoLowText(): string {
    const i: number = this.infoIndex();
    if (i < 0) {
      return '--';
    }
    return this.klines[i].low.toFixed(2);
  }

  private infoCloseText(): string {
    const i: number = this.infoIndex();
    if (i < 0) {
      return '--';
    }
    return this.klines[i].close.toFixed(2);
  }

  private infoUpColor(): string {
    const i: number = this.infoIndex();
    if (i < 0 || this.klines[i].close < this.klines[i].open) {
      return '#1DBF60';
    }
    return '#E62E4C';
  }

  private infoChangeText(): string {
    const i: number = this.infoIndex();
    if (i <= 0) {
      return '--';
    }
    const prev: number = this.klines[i - 1].close;
    if (prev <= 0) {
      return '--';
    }
    const pct: number = (this.klines[i].close - prev) / prev * 100;
    return (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%';
  }

  private infoChangeColor(): string {
    const i: number = this.infoIndex();
    if (i <= 0) {
      return '#8A90A0';
    }
    const prev: number = this.klines[i - 1].close;
    if (prev <= 0) {
      return '#8A90A0';
    }
    const pct: number = (this.klines[i].close - prev) / prev * 100;
    if (pct > 0) {
      return '#E62E4C';
    }
    if (pct < 0) {
      return '#1DBF60';
    }
    return '#8A90A0';
  }

  private infoDifText(): string {
    const i: number = this.infoIndex();
    if (i < 0 || i >= this.macdPoints.length) {
      return '--';
    }
    return this.macdPoints[i].dif.toFixed(2);
  }

  private infoDeaText(): string {
    const i: number = this.infoIndex();
    if (i < 0 || i >= this.macdPoints.length) {
      return '--';
    }
    return this.macdPoints[i].dea.toFixed(2);
  }

  private infoMacdText(): string {
    const i: number = this.infoIndex();
    if (i < 0 || i >= this.macdPoints.length) {
      return '--';
    }
    return this.macdPoints[i].bar.toFixed(2);
  }

  private infoMacdColor(): string {
    const i: number = this.infoIndex();
    if (i < 0 || i >= this.macdPoints.length) {
      return '#8A90A0';
    }
    if (this.macdPoints[i].bar >= 0) {
      return '#E62E4C';
    }
    return '#1DBF60';
  }

  private async initSettings(): Promise<void> {
    try {
      const context: common.Context =
        this.getUIContext().getHostContext() as common.Context;
      if (context === null || context === undefined) {
        return;
      }
      this.axisFontScale = await SettingsStore.loadAxisFontScale(context);
      this.aiBaseUrl = await SettingsStore.loadAiBaseUrl(context);
      this.aiApiKey = await SettingsStore.loadAiApiKey(context);
      this.aiModel = await SettingsStore.loadAiModel(context);
      this.drawAll();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'initSettings failed: %{public}s', `${error}`);
    }
  }

  private changeFontScale(delta: number): void {
    let target: number = Math.round((this.axisFontScale + delta) * 100) / 100;
    if (target < 0.75) {
      target = 0.75;
    }
    if (target > 2) {
      target = 2;
    }
    if (target === this.axisFontScale) {
      return;
    }
    this.axisFontScale = target;
    this.drawAll();
    const context: common.Context =
      this.getUIContext().getHostContext() as common.Context;
    if (context !== null && context !== undefined) {
      SettingsStore.saveAxisFontScale(context, target).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'saveAxisFontScale failed: %{public}s', `${error.message}`);
      });
    }
  }

  private buildPrompt(): string {
    const parts: string[] = [];
    parts.push('你是专业的证券技术分析师。请基于以下数据，用简体中文分点分析该标的：'
      + '1) 当前趋势与动能状态；2) MACD 背离信号解读；3) 后续需重点关注的价位与风险。'
      + '全文 200 字以内，结尾附一句风险提示，不给出具体买卖建议。');
    parts.push('标的：' + (this.stockName !== '' ? this.stockName : this.stockCode)
      + '(' + this.stockCode.toUpperCase() + ')');
    parts.push('分析周期：' + kLineLevelLabel(this.currentLevel));
    if (this.klines.length > 0) {
      const last: KLineItem = this.klines[this.klines.length - 1];
      parts.push('最新收盘价：' + last.close.toFixed(2));
      const n: number = Math.min(10, this.klines.length);
      const closes: string[] = [];
      for (let i = this.klines.length - n; i < this.klines.length; i++) {
        closes.push(this.klines[i].close.toFixed(2));
      }
      parts.push('最近 ' + n + ' 根收盘价：' + closes.join(','));
    }
    if (this.macdPoints.length > 0) {
      const m: MacdPoint = this.macdPoints[this.macdPoints.length - 1];
      parts.push('最新 MACD：DIF=' + m.dif.toFixed(3) + '，DEA=' + m.dea.toFixed(3)
        + '，柱=' + m.bar.toFixed(3));
    }
    if (this.divergences.length > 0) {
      parts.push('检测到的背离（按时间倒序）：');
      const n: number = Math.min(5, this.divergences.length);
      for (let i = 0; i < n; i++) {
        parts.push((i + 1) + '. ' + this.divergences[i].desc);
      }
      if (this.divergences.length > n) {
        parts.push('（其余 ' + (this.divergences.length - n) + ' 处从略）');
      }
    } else {
      parts.push('未检测到明显背离。');
    }
    return parts.join('\n');
  }

  private async runAiAnalysis(): Promise<void> {
    if (this.aiLoading || this.klines.length === 0) {
      return;
    }
    if (this.aiApiKey === '') {
      this.aiResult = '';
      this.aiErr = '未配置 API Key，请到 个人中心 → AI 智能分析 填写';
      return;
    }
    this.aiLoading = true;
    this.aiErr = '';
    this.aiResult = '';
    try {
      const reply: string = await AiClient.chat(this.aiBaseUrl, this.aiApiKey,
        this.aiModel, this.buildPrompt());
      this.aiResult = reply;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      this.aiErr = 'AI 解读失败：' + (err.message ?? '网络或配置错误');
    }
    this.aiLoading = false;
  }

  private async loadLevel(level: KLineLevel): Promise<void> {
    this.currentLevel = level;
    const cached: LevelAnalysisResult | undefined = this.levelCache.get(level);
    if (cached !== undefined) {
      this.applyResult(cached);
      return;
    }
    this.isLoading = true;
    this.errorMsg = '';
    try {
      const klines: KLineItem[] = await StockApi.fetchKLines(this.stockCode, level);
      const macd: MacdPoint[] = MacdAnalyzer.calcMacd(klines);
      const divs: DivergenceInfo[] = MacdAnalyzer.detectDivergence(klines, macd, level);
      const result: LevelAnalysisResult = new LevelAnalysisResult(level, klines, macd, divs);
      this.levelCache.set(level, result);
      if (this.currentLevel === level) {
        this.applyResult(result);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadLevel failed: %{public}s', `${error}`);
      if (this.currentLevel === level) {
        this.klines = [];
        this.macdPoints = [];
        this.divergences = [];
        this.errorMsg = '行情数据加载失败，请检查网络后返回重试';
        this.drawAll();
      }
    }
    if (this.currentLevel === level) {
      this.isLoading = false;
    }
  }

  private applyResult(result: LevelAnalysisResult): void {
    this.klines = result.klines;
    this.macdPoints = result.macdPoints;
    this.divergences = result.divergences;
    this.scrollOffset = 0;
    this.crosshairIndex = -1;
    const now: Date = new Date();
    const minutes: number = now.getMinutes();
    const minuteStr: string = minutes < 10 ? '0' + minutes : '' + minutes;
    this.dataTime = now.getHours() + ':' + minuteStr;
    this.drawAll();
  }

  private pxPerBar(): number {
    if (this.klineWidth <= 0 || this.visibleCount <= 0 || this.klines.length < 2) {
      return 0;
    }
    const endIndex: number = Math.min(this.klines.length,
      this.klines.length - this.scrollOffset);
    const startIndex: number = Math.max(0, endIndex - this.visibleCount);
    const padRight: number = ChartRenderer.axisPadRight(this.klines,
      startIndex, endIndex, this.axisFontScale);
    const plotWidth: number = this.klineWidth - 6 - padRight;
    if (plotWidth <= 0) {
      return 0;
    }
    return plotWidth / this.visibleCount;
  }

  private drawAll(): void {
    if (this.klines.length === 0) {
      if (this.klineReady) {
        this.klineCtx.clearRect(0, 0, this.klineCtx.width, this.klineCtx.height);
      }
      if (this.macdReady) {
        this.macdCtx.clearRect(0, 0, this.macdCtx.width, this.macdCtx.height);
      }
      return;
    }
    const maxOffset: number = Math.max(0, this.klines.length - this.visibleCount);
    if (this.scrollOffset > maxOffset) {
      this.scrollOffset = maxOffset;
    }
    if (this.scrollOffset < 0) {
      this.scrollOffset = 0;
    }
    const endIndex: number = this.klines.length - this.scrollOffset;
    const startIndex: number = Math.max(0, endIndex - this.visibleCount);
    if (this.klineReady) {
      ChartRenderer.drawKLineChart(this.klineCtx, this.klines, this.divergences,
        startIndex, endIndex, this.axisFontScale, this.crosshairIndex);
    }
    if (this.macdReady && this.macdPoints.length > 0) {
      ChartRenderer.drawMacdChart(this.macdCtx, this.klines, this.macdPoints,
        this.divergences, startIndex, endIndex, this.axisFontScale, this.crosshairIndex);
    }
  }
  /**
   * 点击背离结论卡片：图表窗口跳转到该背离（以 A/B 两点中点居中），
   * 同时页面平滑滚回图表区域。
   */
  private jumpToDivergence(div: DivergenceInfo): void {
    if (this.klines.length === 0) {
      return;
    }
    const mid: number = Math.floor((div.indexA + div.indexB) / 2);
    let end: number = mid + Math.ceil(this.visibleCount / 2);
    if (end > this.klines.length) {
      end = this.klines.length;
    }
    let start: number = end - this.visibleCount;
    if (start < 0) {
      start = 0;
      end = Math.min(this.klines.length, this.visibleCount);
    }
    this.scrollOffset = Math.max(0, this.klines.length - end);
    this.crosshairIndex = -1;
    this.drawAll();
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  build() {

    NavDestination() {
      Scroll(this.scroller) {
        Column() {
          Row() {
            Column() {
              Text(this.titleText())
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.t().textPrimary)
              Text(this.stockCode.toUpperCase())
                .fontSize(12)
                .fontColor(this.t().textSecondary)
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            if (this.klines.length > 0) {
              Column() {
                Text(this.lastCloseText())
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.t().textPrimary)
                if (this.dataTime !== '') {
                  Text('更新 ' + this.dataTime)
                    .fontSize(11)
                    .fontColor(this.t().textTertiary)
                    .margin({ top: 3 })
                }
              }
              .alignItems(HorizontalAlign.End)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(ALL_KLINE_LEVELS, (level: KLineLevel) => {
              Text(kLineLevelLabel(level))
                .fontSize(12)
                .fontColor(this.levelTabColor(level))
                .backgroundColor(this.levelTabBg(level))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(14)
                .margin(4)
                .onClick(() => {
                  this.loadLevel(level);
                })
            }, (level: KLineLevel) => level.toString() + '-' + this.currentLevel.toString())
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 6 })

          Row() {
            Text('拖动查看历史 · 双指缩放 · 点击查看单根数据')
              .fontSize(11)
              .fontColor(this.t().textTertiary)
            Blank()
            Text('轴字体')
              .fontSize(11)
              .fontColor(this.t().textTertiary)
            Text('A-')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
              .backgroundColor(this.t().inputBg)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(12)
              .margin({ left: 8 })
              .onClick(() => {
                this.changeFontScale(-0.25);
              })
            Text(this.fontScaleText())
              .fontSize(11)
              .fontColor(this.t().textSecondary)
              .width(44)
              .textAlign(TextAlign.Center)
            Text('A+')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.t().textPrimary)
              .backgroundColor(this.t().inputBg)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(12)
              .onClick(() => {
                this.changeFontScale(0.25);
              })
          }
          .width('92%')
          .padding({ bottom: 4 })

          if (this.isLoading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color('#4E9CF8')
              Text('正在加载 ' + kLineLevelLabel(this.currentLevel) + ' 行情数据...')
                .fontSize(13)
                .fontColor(this.t().textSecondary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 8, bottom: 8 })
          }

          if (this.errorMsg !== '') {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor('#FF6B6B')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
          }

          Text('K线走势（' + kLineLevelLabel(this.currentLevel) + '）')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.t().textSecondary)
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 6 })

          if (this.klines.length > 0) {
            Column({ space: 4 }) {
              Row({ space: 10 }) {
                Text(this.infoDateText())
                  .fontSize(11)
                  .fontColor(this.t().textPrimary)
                Text('开 ' + this.infoOpenText())
                  .fontSize(11)
                  .fontColor(this.infoUpColor())
                Text('高 ' + this.infoHighText())
                  .fontSize(11)
                  .fontColor(this.t().textPrimary)
                Text('低 ' + this.infoLowText())
                  .fontSize(11)
                  .fontColor(this.t().textPrimary)
              }
              Row({ space: 10 }) {
                Text('收 ' + this.infoCloseText())
                  .fontSize(11)
                  .fontColor(this.infoUpColor())
                Text(this.infoChangeText())
                  .fontSize(11)
                  .fontColor(this.infoChangeColor())
                Text('DIF ' + this.infoDifText())
                  .fontSize(11)
                  .fontColor('#F0F0F0')
                Text('DEA ' + this.infoDeaText())
                  .fontSize(11)
                  .fontColor('#FFB74D')
                Text('MACD ' + this.infoMacdText())
                  .fontSize(11)
                  .fontColor(this.infoMacdColor())
              }
            }
            .width('92%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(this.t().card)
            .borderRadius(8)
            .margin({ bottom: 6 })
          }

          Canvas(this.klineCtx)
            .width('92%')
            .height(260)
            .backgroundColor('#14161F')
            .borderRadius(10)
            .onClick((event: ClickEvent) => {
              this.onChartTap(event.x);
            })
            .onReady(() => {
              this.klineWidth = this.klineCtx.width;
              this.klineReady = true;
              this.drawAll();
            })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
                  .onActionStart((event: GestureEvent) => {
                    this.panStartOffset = this.scrollOffset;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const perBar: number = this.pxPerBar();
                    if (perBar <= 0) {
                      return;
                    }
                    this.scrollOffset = this.panStartOffset + Math.round(event.offsetX / perBar);
                    this.drawAll();
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart((event: GestureEvent) => {
                    this.pinchStartCount = this.visibleCount;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    if (event.scale <= 0.01) {
                      return;
                    }
                    let target: number = Math.round(this.pinchStartCount / event.scale);
                    if (target < 30) {
                      target = 30;
                    }
                    if (target > 250) {
                      target = 250;
                    }
                    this.visibleCount = target;
                    this.drawAll();
                  })
              )
            )

          Row({ space: 12 }) {
            Text('DIF')
              .fontSize(11)
              .fontColor('#F0F0F0')
            Text('DEA')
              .fontSize(11)
              .fontColor('#FFB74D')
            Text('顶背离标记')
              .fontSize(11)
              .fontColor('#B388FF')
            Text('底背离标记')
              .fontSize(11)
              .fontColor('#4DD0E1')
          }
          .width('92%')
          .padding({ top: 6, bottom: 6 })

          Text('MACD（12,26,9）')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.t().textSecondary)
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 6 })

          Canvas(this.macdCtx)
            .width('92%')
            .height(170)
            .backgroundColor('#14161F')
            .borderRadius(10)
            .onClick((event: ClickEvent) => {
              this.onChartTap(event.x);
            })
            .onReady(() => {
              this.macdReady = true;
              this.drawAll();
            })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
                  .onActionStart((event: GestureEvent) => {
                    this.panStartOffset = this.scrollOffset;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const perBar: number = this.pxPerBar();
                    if (perBar <= 0) {
                      return;
                    }
                    this.scrollOffset = this.panStartOffset + Math.round(event.offsetX / perBar);
                    this.drawAll();
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart((event: GestureEvent) => {
                    this.pinchStartCount = this.visibleCount;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    if (event.scale <= 0.01) {
                      return;
                    }
                    let target: number = Math.round(this.pinchStartCount / event.scale);
                    if (target < 30) {
                      target = 30;
                    }
                    if (target > 250) {
                      target = 250;
                    }
                    this.visibleCount = target;
                    this.drawAll();
                  })
              )
            )

          Row() {
            Text('背离分析结论')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
            Blank()
            if (this.divergences.length > 0) {
              Text(this.summaryText())
                .fontSize(12)
                .fontColor(this.t().textSecondary)
            }
          }
          .width('92%')
          .padding({ top: 18, bottom: 8 })

          if (this.klines.length > 0 && !this.isLoading) {
            Row({ space: 10 }) {
              Text('AI 解读')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor('#2A5BD7')
                .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                .borderRadius(15)
                .onClick(() => {
                  this.runAiAnalysis();
                })
              if (this.aiLoading) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color('#4E9CF8')
                Text('正在分析 ' + this.aiModel + ' ...')
                  .fontSize(11)
                  .fontColor(this.t().textSecondary)
              } else {
                Text('大模型解读当前背离数据')
                  .fontSize(11)
                  .fontColor(this.t().textTertiary)
              }
            }
            .width('92%')
            .padding({ bottom: 8 })

            if (this.aiErr !== '') {
              Text(this.aiErr)
                .fontSize(12)
                .fontColor('#FF6B6B')
                .width('92%')
                .padding({ bottom: 8 })
            }

            if (this.aiResult !== '') {
              Column({ space: 6 }) {
                Text('AI 智能解读（' + this.aiModel + '）')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#4E9CF8')
                  .width('100%')
                Text(this.aiResult)
                  .fontSize(13)
                  .fontColor(this.t().textSecondary)
                  .lineHeight(20)
                  .width('100%')
                Text('AI 生成内容仅供参考，不构成投资建议。')
                  .fontSize(11)
                  .fontColor(this.t().textTertiary)
                  .width('100%')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .width('92%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(this.t().card)
              .border({ width: 1, color: '#4E9CF8' })
              .margin({ bottom: 8 })
            }
          }

          if (this.divergences.length === 0) {
            if (!this.isLoading && this.errorMsg === '') {
              Text('当前' + kLineLevelLabel(this.currentLevel)
                + '级别未检测到明显 MACD 背离，价格与动能方向保持一致。')
                .fontSize(13)
                .fontColor(this.t().textSecondary)
                .lineHeight(19)
                .width('92%')
                .padding(12)
                .backgroundColor(this.t().card)
                .borderRadius(10)
            }
          } else {
            Column({ space: 8 }) {
              ForEach(this.divergences, (div: DivergenceInfo) => {
                Column({ space: 4 }) {
                  Text(div.desc)
                    .fontSize(12)
                    .fontColor(this.t().textSecondary)
                    .lineHeight(18)
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(10)
                .borderRadius(10)
                .backgroundColor(this.t().card)
                .border({ width: 1, color: this.divColor(div) })
                .onClick(() => {
                  this.jumpToDivergence(div);
                })
              }, (div: DivergenceInfo) => div.level.toString() + '-' + div.indexB.toString())
            }
            .width('92%')
          }

          Text('以上结果为基于公开行情的算法计算，仅供学习参考，不构成投资建议。')
            .fontSize(11)
            .fontColor(this.t().textTertiary)
            .width('92%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 24 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.t().bg)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .title(this.titleText())
    .backgroundColor(this.t().bg)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const rawParam: Record<string, Object> =
        ctx.pathInfo.param as Record<string, Object>;
      if (rawParam !== null && rawParam !== undefined) {
        const codeVal: Object | undefined = rawParam['code'];
        const nameVal: Object | undefined = rawParam['name'];
        if (typeof codeVal === 'string') {
          this.stockCode = codeVal;
        }
        if (typeof nameVal === 'string') {
          this.stockName = nameVal;
        }
      }
      this.initSettings();
      this.loadLevel(this.currentLevel);
    })
  }
}
