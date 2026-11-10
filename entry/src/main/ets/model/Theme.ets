/**
 * 背景主题定义。themeIndex 通过 AppStorage('theme_index') 全局共享，
 * 由主页启动时从持久化读取，主题设置页修改后所有页面即时生效。
 *
 * 设计令牌（现代金融风）：
 * - accent/accentFrom/accentTo：强调色与渐变对（主按钮、激活态 chip、hero 卡）；
 * - cardBorder：卡片 1px 细描边，替代纯色块堆叠，增加层次；
 * - shadowColor：卡片柔和投影色。
 */
export class ThemeColors {
  bg: string;
  card: string;
  inputBg: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  accent: string;
  accentFrom: string;
  accentTo: string;
  cardBorder: string;
  shadowColor: string;

  constructor(bg: string, card: string, inputBg: string,
    textPrimary: string, textSecondary: string, textTertiary: string,
    accent: string, accentFrom: string, accentTo: string,
    cardBorder: string, shadowColor: string) {
    this.bg = bg;
    this.card = card;
    this.inputBg = inputBg;
    this.textPrimary = textPrimary;
    this.textSecondary = textSecondary;
    this.textTertiary = textTertiary;
    this.accent = accent;
    this.accentFrom = accentFrom;
    this.accentTo = accentTo;
    this.cardBorder = cardBorder;
    this.shadowColor = shadowColor;
  }
}

export const THEME_IDS: number[] = [0, 1, 2, 3];

export class ThemeNavParam {
  from: string = 'index';
}

export function themeName(id: number): string {
  if (id === 1) {
    return '午夜蓝';
  }
  if (id === 2) {
    return '翡翠暗绿';
  }
  if (id === 3) {
    return '简约浅色';
  }
  return '深邃黑';
}

export function themeColors(id: number): ThemeColors {
  if (id === 1) {
    return new ThemeColors('#0E1626', '#16223A', '#1B2A47',
      '#E8EDF7', '#7E8BA6', '#55617C',
      '#4E9CF8', '#1D4ED8', '#4E9CF8',
      'rgba(126,139,166,0.16)', '#40000000');
  }
  if (id === 2) {
    return new ThemeColors('#0E1512', '#15221C', '#1A2B23',
      '#E9F0EA', '#84988A', '#59695E',
      '#2FC08E', '#0F7A5A', '#2FBF80',
      'rgba(132,152,138,0.16)', '#40000000');
  }
  if (id === 3) {
    return new ThemeColors('#F4F5F8', '#FFFFFF', '#E9EBF0',
      '#1C2230', '#5A6474', '#9AA2B0',
      '#2A5BD7', '#2A5BD7', '#5E8BFF',
      'rgba(28,34,48,0.07)', '#141C2230');
  }
  return new ThemeColors('#12141C', '#1A1D29', '#1E2130',
    '#ECEDEE', '#8A90A0', '#5A6072',
    '#4E9CF8', '#2A5BD7', '#5E8BFF',
    'rgba(255,255,255,0.06)', '#40000000');
}
