import { hilog } from '@kit.PerformanceAnalysisKit';
import { DetailNavParam, ScanNavParam, SearchSuggest, StockQuote } from '../model/StockModels';
import { StockApi, normalizeStockCode } from '../data/StockApi';
import { WatchlistStore } from '../store/WatchlistStore';
import { SettingsStore } from '../store/SettingsStore';
import { ThemeColors, ThemeNavParam, themeColors } from '../model/Theme';
import { PersonalPage } from './Personal';

const DOMAIN: number = 0x0001;
const TAG: string = 'WatchlistIndex';

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
  @StorageLink('theme_index') themeIndex: number = 0;
  private pathStack: NavPathStack = new NavPathStack();
  private storedCodes: string[] = [];
  private searchToken: number = 0;
  private dockGradColors: Array<[ResourceColor, number]> =
    [['#4E9CF8', 0], ['#2A5BD7', 1]];

  private async reloadAfterSync(): Promise<void> {
    this.storedCodes = await WatchlistStore.loadCodes(getContext(this));
    await this.refreshQuotes();
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
    await this.refreshQuotes();
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
    this.isAdding = true;
    this.loadErr = '';
    try {
      const quotes: StockQuote[] = await StockApi.fetchQuotes([normalized]);
      if (quotes.length === 0 || quotes[0].name === '') {
        this.loadErr = `未找到股票 ${normalized}，请确认代码是否正确`;
      } else {
        this.storedCodes.push(normalized);
        await WatchlistStore.saveCodes(getContext(this), this.storedCodes.slice());
        this.inputCode = '';
        await this.refreshQuotes();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'addStock failed: %{public}s', `${error}`);
      this.loadErr = '添加失败，请检查网络后重试';
    }
    this.isAdding = false;
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
    this.isAdding = true;
    try {
      this.storedCodes.push(s.code);
      await WatchlistStore.saveCodes(getContext(this), this.storedCodes.slice());
      await this.refreshQuotes();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'addFromSuggest failed: %{public}s', `${error}`);
      this.loadErr = '添加失败，请检查网络后重试';
    }
    this.isAdding = false;
  }

  private async removeStock(code: string): Promise<void> {
    const idx: number = this.storedCodes.indexOf(code);
    if (idx >= 0) {
      this.storedCodes.splice(idx, 1);
      await WatchlistStore.saveCodes(getContext(this), this.storedCodes.slice());
      await this.refreshQuotes();
    }
  }

  private openDetail(quote: StockQuote): void {
    const p: DetailNavParam = { code: quote.code, name: quote.name };
    this.pathStack.pushPathByName('StockDetail', p);
  }

  private startScan(category: string): void {
    const p: ScanNavParam = new ScanNavParam();
    p.category = category;
    this.pathStack.pushPathByName('ScanReport', p);
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
              .color('#4E9CF8')
              .margin({ right: 10 })
          }
          Text('主题')
            .fontColor('#4E9CF8')
            .fontSize(15)
            .padding({ left: 8, top: 6, right: 4, bottom: 6 })
            .onClick(() => {
              this.openThemeSetting();
            })
          Text('刷新')
            .fontColor('#4E9CF8')
            .fontSize(15)
            .padding({ left: 4, top: 6, right: 8, bottom: 6 })
            .onClick(() => {
              this.refreshQuotes();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Row({ space: 8 }) {
          TextInput({ placeholder: '输入代码或名称添加自选，如 600519 / 贵州茅台' })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(this.t().textPrimary)
            .placeholderColor(this.t().textTertiary)
            .placeholderFont({ size: 14 })
            .backgroundColor(this.t().inputBg)
            .borderRadius(8)
            .onChange((value: string) => {
              this.onInputChanged(value);
            })
          Button('添加', { type: ButtonType.Capsule })
            .height(36)
            .fontSize(14)
            .backgroundColor('#2A5BD7')
            .enabled(!this.isAdding)
            .onClick(() => {
              this.addStock();
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
                    .fontColor('#4E9CF8')
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

        Column({ space: 8 }) {
          Row() {
            Text('背离扫描')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.t().textPrimary)
            Text('一键生成日线 MACD 背离报告')
              .fontSize(11)
              .fontColor(this.t().textTertiary)
              .margin({ left: 8 })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('自选股')
              .fontSize(12)
              .fontColor(this.t().textPrimary)
              .backgroundColor(this.t().inputBg)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(14)
              .onClick(() => {
                this.startScan('watchlist');
              })
            Text('全市场个股')
              .fontSize(12)
              .fontColor(this.t().textPrimary)
              .backgroundColor(this.t().inputBg)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(14)
              .onClick(() => {
                this.startScan('astock');
              })
            Text('全市场ETF')
              .fontSize(12)
              .fontColor(this.t().textPrimary)
              .backgroundColor(this.t().inputBg)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(14)
              .onClick(() => {
                this.startScan('etf');
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .margin({ left: 16, right: 16, bottom: 8 })
        .backgroundColor(this.t().card)
        .borderRadius(12)

        if (this.quoteList.length === 0) {
          Column() {
            Text('暂无自选股')
              .fontSize(16)
              .fontColor(this.t().textSecondary)
            Text('在上方输入股票代码（如 600519、sz000001），添加你的自选股')
              .fontSize(13)
              .fontColor(this.t().textTertiary)
              .margin({ top: 8 })
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 32, right: 32 })
        } else {
          List({ space: 8 }) {
            ForEach(this.quoteList, (quote: StockQuote) => {
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
                      .fontSize(12)
                      .fontColor(this.t().textSecondary)
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column() {
                    Text(this.priceText(quote))
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.percentColor(quote))
                    Text(this.percentText(quote))
                      .fontSize(12)
                      .fontColor(this.percentColor(quote))
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .backgroundColor(this.t().card)
                .borderRadius(12)
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
          .padding({ left: 12, right: 12, top: 4, bottom: 104 })
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
                .linearGradient({ angle: 90, colors: this.dockGradColors })
                .shadow({ radius: 8, color: '#804E9CF8' })
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
                .linearGradient({ angle: 90, colors: this.dockGradColors })
                .shadow({ radius: 8, color: '#804E9CF8' })
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
  }
}
