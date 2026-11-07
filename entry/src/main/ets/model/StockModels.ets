export enum KLineLevel {
  M30 = 0,
  M60 = 1,
  DAY = 2,
  WEEK = 3
}

export function kLineLevelLabel(level: KLineLevel): string {
  if (level === KLineLevel.M30) {
    return '30分钟';
  }
  if (level === KLineLevel.M60) {
    return '60分钟';
  }
  if (level === KLineLevel.DAY) {
    return '日线';
  }
  return '周线';
}

export const ALL_KLINE_LEVELS: KLineLevel[] =
  [KLineLevel.M30, KLineLevel.M60, KLineLevel.DAY, KLineLevel.WEEK];

export class KLineItem {
  date: string;
  open: number;
  close: number;
  high: number;
  low: number;
  volume: number;

  constructor(date: string, open: number, close: number,
    high: number, low: number, volume: number) {
    this.date = date;
    this.open = open;
    this.close = close;
    this.high = high;
    this.low = low;
    this.volume = volume;
  }
}

export class MacdPoint {
  dif: number;
  dea: number;
  bar: number;

  constructor(dif: number, dea: number, bar: number) {
    this.dif = dif;
    this.dea = dea;
    this.bar = bar;
  }
}

export enum DivergenceType {
  TOP = 0,
  BOTTOM = 1
}

export class DivergenceInfo {
  divType: DivergenceType;
  level: KLineLevel;
  indexA: number;
  indexB: number;
  dateA: string;
  dateB: string;
  priceA: number;
  priceB: number;
  difA: number;
  difB: number;
  desc: string;

  constructor(divType: DivergenceType, level: KLineLevel,
    indexA: number, indexB: number, dateA: string, dateB: string,
    priceA: number, priceB: number, difA: number, difB: number, desc: string) {
    this.divType = divType;
    this.level = level;
    this.indexA = indexA;
    this.indexB = indexB;
    this.dateA = dateA;
    this.dateB = dateB;
    this.priceA = priceA;
    this.priceB = priceB;
    this.difA = difA;
    this.difB = difB;
    this.desc = desc;
  }
}

export class StockQuote {
  code: string;
  name: string;
  price: number;
  prevClose: number;
  changePercent: number;

  constructor(code: string, name: string, price: number,
    prevClose: number, changePercent: number) {
    this.code = code;
    this.name = name;
    this.price = price;
    this.prevClose = prevClose;
    this.changePercent = changePercent;
  }
}

export class LevelAnalysisResult {
  level: KLineLevel;
  klines: KLineItem[];
  macdPoints: MacdPoint[];
  divergences: DivergenceInfo[];

  constructor(level: KLineLevel, klines: KLineItem[],
    macdPoints: MacdPoint[], divergences: DivergenceInfo[]) {
    this.level = level;
    this.klines = klines;
    this.macdPoints = macdPoints;
    this.divergences = divergences;
  }
}

export class DetailNavParam {
  code: string = '';
  name: string = '';
}

export class ScanNavParam {
  category: string = 'watchlist';
}

export class MarketRef {
  code: string;
  name: string;
  price: number;

  constructor(code: string, name: string, price: number) {
    this.code = code;
    this.name = name;
    this.price = price;
  }
}

export class ScanResultItem {
  code: string;
  name: string;
  lastClose: number;
  topCount: number;
  bottomCount: number;
  latestDivDesc: string;
  latestDate: string;
  isTop: boolean;

  constructor(code: string, name: string, lastClose: number,
    topCount: number, bottomCount: number, latestDivDesc: string,
    latestDate: string, isTop: boolean) {
    this.code = code;
    this.name = name;
    this.lastClose = lastClose;
    this.topCount = topCount;
    this.bottomCount = bottomCount;
    this.latestDivDesc = latestDivDesc;
    this.latestDate = latestDate;
    this.isTop = isTop;
  }
}
