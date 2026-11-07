/**
 * 背景主题定义。themeIndex 通过 AppStorage('theme_index') 全局共享，
 * 由主页启动时从持久化读取，主题设置页修改后所有页面即时生效。
 */
export class ThemeColors {
  bg: string;
  card: string;
  inputBg: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;

  constructor(bg: string, card: string, inputBg: string,
    textPrimary: string, textSecondary: string, textTertiary: string) {
    this.bg = bg;
    this.card = card;
    this.inputBg = inputBg;
    this.textPrimary = textPrimary;
    this.textSecondary = textSecondary;
    this.textTertiary = textTertiary;
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
      '#E8EDF7', '#7E8BA6', '#55617C');
  }
  if (id === 2) {
    return new ThemeColors('#0E1512', '#15221C', '#1A2B23',
      '#E9F0EA', '#84988A', '#59695E');
  }
  if (id === 3) {
    return new ThemeColors('#F4F5F8', '#FFFFFF', '#E9EBF0',
      '#1C2230', '#5A6474', '#9AA2B0');
  }
  return new ThemeColors('#12141C', '#1A1D29', '#1E2130',
    '#ECEDEE', '#8A90A0', '#5A6072');
}
