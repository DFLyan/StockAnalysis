# StockAnalysis · 股票 MACD 背离分析（HarmonyOS）

基于 HarmonyOS ArkTS/ArkUI 开发的股票技术分析应用：自选股管理、多级别 K 线图、MACD 背离自动检测、全市场一键背离扫描、AI 智能解读，以及华为账号云同步。

> 仅供参考与学习，不构成投资建议。

## 功能特性

### 自选股管理
- 代码 / 名称 / 拼音输入联想添加（腾讯 smartbox）
- 主页行情列表实时展示现价与涨跌幅，长按移除
- **识图添加**：从图库选择持仓截图，端侧 OCR（Core Vision Kit）识别图中股票代码，识别结果自由勾选、批量导入
- **云同步**：华为账号登录（Account Kit）+ 云数据库（Cloud Foundation Kit），自选股上传 / 跨设备恢复

### K 线与 MACD 分析
- 7 个周期：5 分钟 / 15 分钟 / 30 分钟 / 60 分钟 / 日线 / 周线 / 月线
- K 线拖动平移、双指缩放、点击查看单根 OHLC 与 DIF/DEA/MACD
- MACD(12,26,9) 顶背离 / 底背离自动检测，图表上标注背离点对，点击结论卡片图表自动跳转定位
- 坐标轴字号可调（0.75x ~ 2x），持久化保存

### 一键背离扫描
- 范围：自选股 / 全市场个股 / 全市场 ETF（剔除货币债券）
- 排序：成交额 / 总市值 / 涨跌幅 / 换手率（东财 clist 排行）
- 数量：前 50 / 100 / 200 / 500 / **自定义 10~2000**
- 级别：**多选**，一次扫描同时分析多个周期，结果按“标的 + 级别”分条展示并可按级别筛选
- 结果筛选：顶背离 / 底背离、日期区间（近 1 周 / 1 月 / 3 月 / 自定义区间）
- 扫描范围、排序、级别选择均持久化

### AI 智能解读
- 接入 OpenAI 协议兼容的大模型平台（DeepSeek / 智谱 / Kimi 等），个人中心配置接口地址、API Key、模型名
- 个股详情页一键“AI 解读”：自动组装当前周期、近 10 根收盘价、最新 MACD 与背离清单发送给模型，分点输出趋势与背离解读
- API Key 仅保存在本机 Preferences

### 其他
- 4 套主题外观，实时切换
- 毛玻璃悬浮 Dock 主页/个人页切换，全面适配安全区

## 技术栈

| 项 | 说明 |
| --- | --- |
| 语言 / UI | ArkTS + ArkUI（Stage 模型） |
| SDK | HarmonyOS 6.1.0 (API 23)，兼容模拟器 / 真机 |
| 状态管理 | @State / @StorageLink / @Observed+@ObjectLink（V1） |
| 导航 | Navigation + 系统路由表（router_map.json） |
| 数据持久化 | @ohos.data.preferences |
| 网络 | @ohos.net.http（东财主用 + 腾讯兜底） |
| AI | Core Vision Kit textRecognition（端侧 OCR）+ 自定义 LLM API |

## 数据来源（公开接口）

| 数据 | 来源 |
| --- | --- |
| 实时报价 / 名称搜索 | 腾讯 `qt.gtimg.cn` / `smartbox.gtimg.cn` |
| 日 / 周 / 月 K 线 | 东财 `push2his.eastmoney.com`（主）+ 腾讯 `ifzq.gtimg.cn`（兜底） |
| 分钟 K 线（5/15/30/60） | 腾讯 `mkline` |
| 市场排行（扫描范围） | 东财 `push2.eastmoney.com` clist |

## 目录结构

```
entry/src/main/ets/
├── pages/
│   ├── Index.ets          # 主页：自选股列表 / 搜索添加 / 识图入口 / Dock
│   ├── StockDetail.ets    # 个股详情：K线图 + MACD + 背离结论 + AI 解读
│   ├── ScanReport.ets     # 一键背离扫描报告
│   ├── ImageScan.ets      # 识图添加（图库选图 + OCR + 勾选导入）
│   ├── Personal.ets       # 个人中心：账号 / 云同步 / AI 配置 / 主题入口
│   └── ThemeSetting.ets   # 主题设置
├── chart/ChartRenderer.ets        # K线/MACD Canvas 渲染
├── analysis/MacdAnalyzer.ets      # MACD 计算与背离检测
├── data/
│   ├── StockApi.ets       # 报价 / K线 / 搜索
│   ├── MarketApi.ets      # 市场排行分页拉取
│   └── AiClient.ets       # OpenAI 协议兼容 LLM 客户端
├── store/
│   ├── WatchlistStore.ets # 自选股持久化
│   ├── SettingsStore.ets  # 各项设置持久化
│   └── CloudSync.ets      # AGC 账号登录与云数据库同步
└── model/                 # 数据模型与主题
```

## 构建运行

1. DevEco Studio 打开工程，SDK 使用 HarmonyOS 6.1.0(23)
2. 连接模拟器或真机，直接 Run；或命令行：
   ```bash
   devecocli build
   devecocli run --skip-build --device <deviceId>
   ```
3. 应用需要网络权限（已声明 `ohos.permission.INTERNET`）拉取行情

## 配置说明

### AI 解读（可选）
个人中心 → AI 智能分析 → 填写接口地址（默认 `https://api.deepseek.com`）、API Key、模型名（默认 `deepseek-chat`）→ 保存后到个股详情页点击“AI 解读”。

### 华为账号云同步（可选，需 AGC）
1. AppGallery Connect 创建项目并开通云数据库（对象类型 `WatchlistRecord`，存储区 `StockAnalysisZone`）
2. 下载 `agconnect-services.json` 放入 `entry/`
3. `entry/src/main/module.json5` 中将 `client_id` 元数据替换为 AGC 分配值
4. 配置签名（真机），未配置时应用内优雅降级为提示，不影响其他功能

## 注意事项

- **识图 OCR、华为账号登录等系统能力仅真机可用**，模拟器上会给出友好提示
- 腾讯 `fqkline` 接口对部分网络返回 501，日/周/月 K 线已以东财为主、腾讯兜底
- 扫描大量标的（如前 500 × 多级别）会产生较多网络请求，建议在 Wi-Fi 下使用
