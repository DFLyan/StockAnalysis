export enum KLineLevel {
  M5 = 0,
  M15 = 1,
  M30 = 2,
  M60 = 3,
  DAY = 4,
  WEEK = 5,
  MONTH = 6,
  M120 = 7,
  QUARTER = 8,
  YEAR = 9
}

export function kLineLevelLabel(level: KLineLevel): string {
  if (level === KLineLevel.M5) {
    return '5分钟';
  }
  if (level === KLineLevel.M15) {
    return '15分钟';
  }
  if (level === KLineLevel.M30) {
    return '30分钟';
  }
  if (level === KLineLevel.M60) {
    return '60分钟';
  }
  if (level === KLineLevel.M120) {
    return '120分钟';
  }
  if (level === KLineLevel.DAY) {
    return '日线';
  }
  if (level === KLineLevel.WEEK) {
    return '周线';
  }
  if (level === KLineLevel.MONTH) {
    return '月线';
  }
  if (level === KLineLevel.QUARTER) {
    return '季线';
  }
  return '年线';
}

export const ALL_KLINE_LEVELS: KLineLevel[] =
  [KLineLevel.M5, KLineLevel.M15, KLineLevel.M30, KLineLevel.M60,
    KLineLevel.M120, KLineLevel.DAY, KLineLevel.WEEK, KLineLevel.MONTH,
    KLineLevel.QUARTER, KLineLevel.YEAR];

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

export class ImageScanNavParam {
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

/**
 * 扫描结果：一只标的一条，levels 为命中的级别清单（多个即多级别共振），
 * divergences 汇总该标的所有级别背离。
 */
export class ScanResultItem {
  code: string;
  name: string;
  lastClose: number;
  levels: KLineLevel[];
  divergences: DivergenceInfo[];

  constructor(code: string, name: string, lastClose: number,
    levels: KLineLevel[], divergences: DivergenceInfo[]) {
    this.code = code;
    this.name = name;
    this.lastClose = lastClose;
    this.levels = levels;
    this.divergences = divergences;
  }
}

export class TrendPoint {
  time: string;
  price: number;
  avg: number;

  constructor(time: string, price: number, avg: number) {
    this.time = time;
    this.price = price;
    this.avg = avg;
  }
}

export class TrendData {
  points: TrendPoint[];
  preClose: number;

  constructor(points: TrendPoint[], preClose: number) {
    this.points = points;
    this.preClose = preClose;
  }
}

export class SearchSuggest {
  code: string;
  name: string;
  type: string;

  constructor(code: string, name: string, type: string) {
    this.code = code;
    this.name = name;
    this.type = type;
  }
}
