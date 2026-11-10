import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { StockQuote } from '../model/StockModels';
import { StockApi, normalizeStockCode } from '../data/StockApi';
import { WatchlistGroup, WatchlistStore } from '../store/WatchlistStore';
import { ThemeColors, themeColors } from '../model/Theme';
import { GroupPickerDialog } from '../components/GroupDialogs';

const DOMAIN: number = 0x0004;
const TAG: string = 'ImageScan';
const MAX_CODES_TO_VERIFY: number = 40;

@Observed
class DetectedStock {
  code: string;
  name: string;
  price: number;
  changePercent: number;
  selectable: boolean;
  selected: boolean;

  constructor(code: string, name: string, price: number,
    changePercent: number, selectable: boolean, selected: boolean) {
    this.code = code;
    this.name = name;
    this.price = price;
    this.changePercent = changePercent;
    this.selectable = selectable;
    this.selected = selected;
  }
}

@Component
struct DetectedRow {
  @ObjectLink item: DetectedStock;
  @StorageLink('theme_index') themeIndex: number = 0;
  onToggle: (item: DetectedStock) => void = () => {
  };

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private priceText(): string {
    if (this.item.price > 0) {
      return this.item.price.toFixed(2);
    }
    return '--';
  }

  private percentText(): string {
    const sign: string = this.item.changePercent > 0 ? '+' : '';
    return sign + this.item.changePercent.toFixed(2) + '%';
  }

  private percentColor(): string {
    if (this.item.changePercent > 0) {
      return '#E62E4C';
    }
    if (this.item.changePercent < 0) {
      return '#1DBF60';
    }
    return '#8A90A0';
  }

  private checkBoxBg(): string {
    if (this.item.selected) {
      return this.t().accentFrom;
    }
    return 'transparent';
  }

  private checkBoxBorder(): string {
    if (this.item.selected) {
      return this.t().accentFrom;
    }
    if (!this.item.selectable) {
      return '#4A4F5E';
    }
    return '#8A90A0';
  }

  build() {
    Row({ space: 12 }) {
      Text(this.item.selected ? '✓' : '')
        .width(22)
        .height(22)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .backgroundColor(this.checkBoxBg())
        .borderRadius(11)
        .border({ width: 1.5, color: this.checkBoxBorder() })

      Column() {
        Text(this.item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.item.selectable ? this.t().textPrimary : this.t().textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.item.code.toUpperCase() + (this.item.selectable ? '' : ' · 已在自选'))
          .fontSize(11)
          .fontColor(this.t().textSecondary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text(this.priceText())
          .fontSize(14)
          .fontColor(this.percentColor())
        Text(this.percentText())
          .fontSize(11)
          .fontColor(this.percentColor())
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.t().inputBg)
    .opacity(this.item.selectable ? 1 : 0.55)
    .onClick(() => {
      this.onToggle(this.item);
    })
  }
}

@Builder
export function ImageScanBuilder(): void {
  ImageScan()
}

/**
 * 图片识别添加自选股：图库选图 → 端侧 OCR（Core Vision Kit）→ 提取并校验
 * 股票代码 → 展示识别结果供自由勾选 → 批量加入自选股。
 * 文字识别为系统 AI 能力，仅真机可用（模拟器调用失败时给出提示）。
 */
@Component
export struct ImageScan {
  @State pixelMap: PixelMap | undefined = undefined;
  @State isRecognizing: boolean = false;
  @State detected: DetectedStock[] = [];
  @State selectedCount: number = 0;
  @State scanErr: string = '';
  @State statusMsg: string = '';
  @State statusOk: boolean = true;
  @State isAdding: boolean = false;
  @State recognizedText: string = '';
  @State pickerGroups: string[] = [];
  @State pickerHint: string = '';
  @StorageLink('theme_index') themeIndex: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();
  private imageSource: image.ImageSource | undefined = undefined;
  private pendingBatch: string[] = [];
  private groupPickerController: CustomDialogController = new CustomDialogController({
    builder: GroupPickerDialog({
      hint: this.pickerHint,
      groups: this.pickerGroups,
      onPick: (group: string) => {
        this.onPickBatchGroup(group);
      }
    }),
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    try {
      textRecognition.init().catch(() => {
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'ocr init unavailable on this device');
    }
  }

  aboutToDisappear(): void {
    try {
      textRecognition.release().catch(() => {
      });
    } catch (error) {
    }
    if (this.imageSource !== undefined) {
      this.imageSource.release().catch(() => {
      });
      this.imageSource = undefined;
    }
  }

  private t(): ThemeColors {
    return themeColors(this.themeIndex);
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async pickImage(): Promise<void> {
    if (this.isRecognizing) {
      return;
    }
    this.scanErr = '';
    this.statusMsg = '';
    try {
      const photoPicker: photoAccessHelper.PhotoViewPicker =
        new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris.length === 0) {
        return;
      }
      await this.loadPixelMapFromUri(result.photoUris[0]);
      await this.runOcr();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'pickImage failed: %{public}s', `${err.message}`);
      this.scanErr = '选择图片失败：' + (err.message ?? '已取消');
    }
  }

  private async loadPixelMapFromUri(uri: string): Promise<void> {
    const fileSource: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    if (this.imageSource !== undefined) {
      this.imageSource.release().catch(() => {
      });
    }
    this.imageSource = image.createImageSource(fileSource.fd);
    this.pixelMap = await this.imageSource.createPixelMap();
    fileIo.closeSync(fileSource);
  }

  private async runOcr(): Promise<void> {
    if (this.pixelMap === undefined || this.isRecognizing) {
      return;
    }
    this.isRecognizing = true;
    this.scanErr = '';
    this.statusMsg = '';
    this.detected = [];
    this.selectedCount = 0;
    this.recognizedText = '';
    try {
      const visionInfo: textRecognition.VisionInfo = { pixelMap: this.pixelMap };
      const config: textRecognition.TextRecognitionConfiguration = {
        isDirectionDetectionSupported: false
      };
      const textResult: textRecognition.TextRecognitionResult =
        await textRecognition.recognizeText(visionInfo, config);
      this.recognizedText = textResult.value;
      await this.processText(textResult.value);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'runOcr failed: %{public}s', `${err.message}`);
      this.scanErr = '文字识别失败：' + (err.message ?? '未知错误') + '，AI 识别需真机支持';
    }
    this.isRecognizing = false;
  }

  private isDigitChar(c: string): boolean {
    return c >= '0' && c <= '9';
  }

  /**
   * 从 OCR 文本提取股票代码：按最大数字串扫描，
   * 长度恰为 6 的整段、或更长数字串的首/尾 6 位窗口，经 normalizeStockCode 归一化去重。
   * 日期、手机号等长数字串因窗口归一化非法或后续行情校验失败而被过滤。
   */
  private extractCodes(text: string): string[] {
    const found: string[] = [];
    const cleaned: string = text.replace(/\s/g, '');
    let i: number = 0;
    while (i < cleaned.length) {
      if (!this.isDigitChar(cleaned.charAt(i))) {
        i++;
        continue;
      }
      let j: number = i;
      while (j < cleaned.length && this.isDigitChar(cleaned.charAt(j))) {
        j++;
      }
      const run: string = cleaned.substring(i, j);
      const candidates: string[] = [];
      if (run.length === 6) {
        candidates.push(run);
      } else if (run.length > 6) {
        candidates.push(run.substring(0, 6));
        candidates.push(run.substring(run.length - 6));
      }
      for (const cand of candidates) {
        const normalized: string = normalizeStockCode(cand);
        if (normalized !== '' && found.indexOf(normalized) < 0) {
          found.push(normalized);
        }
      }
      i = j;
    }
    return found;
  }

  /**
   * 提取的候选代码经行情接口校验：无效代码不会返回报价，直接过滤；
   * 已在自选股中的标的置灰不可勾选。
   */
  private async processText(text: string): Promise<void> {
    const codes: string[] = this.extractCodes(text);
    if (codes.length === 0) {
      this.scanErr = '图片中未识别到有效的股票代码，请换更清晰的图片';
      return;
    }
    let quotes: StockQuote[] = [];
    try {
      quotes = await StockApi.fetchQuotes(codes.slice(0, MAX_CODES_TO_VERIFY));
    } catch (error) {
      this.scanErr = '代码校验失败，请检查网络后重试';
      return;
    }
    const existing: string[] = await WatchlistStore.loadCodes(this.ctx());
    const list: DetectedStock[] = [];
    for (const q of quotes) {
      if (q.name === '') {
        continue;
      }
      const selectable: boolean = existing.indexOf(q.code) < 0;
      list.push(new DetectedStock(q.code, q.name, q.price, q.changePercent,
        selectable, selectable));
    }
    if (list.length === 0) {
      this.scanErr = '识别到 ' + codes.length + ' 个疑似代码，但均不是有效股票代码';
      return;
    }
    this.detected = list;
    this.selectedCount = this.countSelected();
  }

  /**
   * 勾选状态更新采用"实例替换"而非原地改属性：替换后 ForEach key 变化，
   * 行组件整体重建，彻底规避 @Observed 属性通知偶发不生效导致的勾选视觉不同步。
   */
  private toggleItem(item: DetectedStock): void {
    if (!item.selectable) {
      return;
    }
    const idx: number = this.detected.indexOf(item);
    if (idx < 0) {
      return;
    }
    const old: DetectedStock = this.detected[idx];
    this.detected.splice(idx, 1, new DetectedStock(old.code, old.name, old.price,
      old.changePercent, old.selectable, !old.selected));
    this.selectedCount = this.countSelected();
  }

  private countSelected(): number {
    let n: number = 0;
    for (const d of this.detected) {
      if (d.selectable && d.selected) {
        n++;
      }
    }
    return n;
  }

  private selectAllItems(select: boolean): void {
    const list: DetectedStock[] = [];
    for (const d of this.detected) {
      if (d.selectable) {
        list.push(new DetectedStock(d.code, d.name, d.price,
          d.changePercent, d.selectable, select));
      } else {
        list.push(d);
      }
    }
    this.detected = list;
    this.selectedCount = this.countSelected();
  }

  private async addSelected(): Promise<void> {
    if (this.isAdding || this.isRecognizing) {
      return;
    }
    const codes: string[] = [];
    for (const d of this.detected) {
      if (d.selectable && d.selected) {
        codes.push(d.code);
      }
    }
    if (codes.length === 0) {
      this.statusMsg = '请先勾选要添加的股票';
      this.statusOk = false;
      return;
    }
    // 已有分组时先选分组，再落地批量添加
    try {
      const groups: WatchlistGroup[] = await WatchlistStore.loadGroups(this.ctx());
      if (groups.length > 0) {
        const names: string[] = [];
        for (const g of groups) {
          names.push(g.name);
        }
        this.pendingBatch = codes;
        this.pickerHint = '将 ' + codes.length + ' 只股票加入分组';
        this.pickerGroups = names;
        this.groupPickerController.open();
        return;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'loadGroups failed, fallback ungrouped');
    }
    await this.finishAddBatch(codes, '');
  }

  /** 分组选择对话框回调：按所选分组落地批量添加。 */
  private onPickBatchGroup(group: string): void {
    const codes: string[] = this.pendingBatch;
    this.pendingBatch = [];
    if (codes.length === 0) {
      return;
    }
    this.finishAddBatch(codes, group);
  }

  private async finishAddBatch(codes: string[], group: string): Promise<void> {
    this.isAdding = true;
    try {
      const existing: string[] = await WatchlistStore.loadCodes(this.ctx());
      let added: number = 0;
      for (const c of codes) {
        if (existing.indexOf(c) < 0) {
          added++;
        }
      }
      await WatchlistStore.addToGroupBatch(this.ctx(), codes, group);
      const prev: number = AppStorage.get<number>('watchlist_version') ?? 0;
      AppStorage.setOrCreate<number>('watchlist_version', prev + 1);
      const list: DetectedStock[] = [];
      for (const d of this.detected) {
        if (d.selectable && d.selected) {
          list.push(new DetectedStock(d.code, d.name, d.price,
            d.changePercent, false, false));
        } else {
          list.push(d);
        }
      }
      this.detected = list;
      this.selectedCount = 0;
      this.statusMsg = '已添加 ' + added + ' 只自选股'
        + (group !== '' ? '到分组「' + group + '」' : '') + '，返回主页即可查看';
      this.statusOk = true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'addSelected failed: %{public}s', `${error}`);
      this.statusMsg = '添加失败，请重试';
      this.statusOk = false;
    }
    this.isAdding = false;
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Text('从图库选择持仓截图或股票列表照片，自动识别图中的股票代码；识别完成后可自由勾选，批量加入自选股。')
            .fontSize(12)
            .fontColor(this.t().textTertiary)
            .width('100%')
            .lineHeight(18)

          if (this.pixelMap !== undefined) {
            Image(this.pixelMap)
              .width('100%')
              .constraintSize({ maxHeight: 220 })
              .borderRadius(10)
              .objectFit(ImageFit.Contain)
              .backgroundColor('#14161F')
          } else {
            Column({ space: 6 }) {
              Text('尚未选择图片')
                .fontSize(14)
                .fontColor(this.t().textSecondary)
              Text('点击下方按钮从图库选择')
                .fontSize(11)
                .fontColor(this.t().textTertiary)
            }
            .width('100%')
            .height(150)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.t().inputBg)
            .borderRadius(10)
          }

          Row({ space: 10 }) {
            Button('选择图片识别', { type: ButtonType.Capsule })
              .height(38)
              .fontSize(14)
              .backgroundColor(this.t().accentFrom)
              .enabled(!this.isRecognizing)
              .layoutWeight(1)
              .onClick(() => {
                this.pickImage();
              })
            if (this.pixelMap !== undefined) {
              Button('重新识别', { type: ButtonType.Capsule })
                .height(38)
                .fontSize(14)
                .fontColor(this.t().accent)
                .backgroundColor(this.t().inputBg)
                .border({ width: 1, color: this.t().cardBorder })
                .enabled(!this.isRecognizing)
                .onClick(() => {
                  this.runOcr();
                })
            }
          }
          .width('100%')

          if (this.isRecognizing) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(this.t().accent)
              Text('正在识别图片中的股票代码...')
                .fontSize(13)
                .fontColor(this.t().textSecondary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }

          if (this.scanErr !== '') {
            Text(this.scanErr)
              .fontSize(12)
              .fontColor('#FF6B6B')
              .width('100%')
              .lineHeight(18)
          }

          if (this.statusMsg !== '') {
            Text(this.statusMsg)
              .fontSize(12)
              .fontColor(this.statusOk ? '#1DBF60' : '#FF6B6B')
              .width('100%')
          }

          if (this.detected.length > 0) {
            Column({ space: 10 }) {
              Row() {
                Text('识别到 ' + this.detected.length + ' 只股票')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.t().textPrimary)
                Blank()
                Text('已选 ' + this.selectedCount)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.t().accent)
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('全选')
                  .fontSize(12)
                  .fontColor(this.t().textPrimary)
                  .backgroundColor(this.t().inputBg)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .onClick(() => {
                    this.selectAllItems(true);
                  })
                Text('清空')
                  .fontSize(12)
                  .fontColor(this.t().textPrimary)
                  .backgroundColor(this.t().inputBg)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .onClick(() => {
                    this.selectAllItems(false);
                  })
              }
              .width('100%')

              ForEach(this.detected, (d: DetectedStock) => {
                DetectedRow({
                  item: d,
                  onToggle: (item: DetectedStock): void => {
                    this.toggleItem(item);
                  }
                })
              }, (d: DetectedStock) => d.code + '-' + (d.selectable ? '1' : '0')
                + '-' + (d.selected ? '1' : '0'))

              Button('添加所选（' + this.selectedCount + ' 只）', { type: ButtonType.Capsule })
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor(this.t().accentFrom)
                .enabled(!this.isAdding && this.selectedCount > 0)
                .onClick(() => {
                  this.addSelected();
                })
            }
            .width('100%')
            .padding(14)
            .backgroundColor(this.t().card)
            .borderRadius(16)
            .border({ width: 1, color: this.t().cardBorder })
            .shadow({ radius: 8, color: this.t().shadowColor, offsetY: 3 })
          }

          if (this.recognizedText !== '' && this.detected.length === 0
            && this.scanErr === '') {
            Text('识别原文：' + this.recognizedText)
              .fontSize(11)
              .fontColor(this.t().textTertiary)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 32 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.t().bg)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .title('图片识别添加')
    .backgroundColor(this.t().bg)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
    })
  }
}
