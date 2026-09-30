# Kindle Voyage 越狱 + 安装 KOReader + 觅阅 (MiuRead 微信读书) 全套准备资料与实操指南

> 💡 **状态说明**：已完成全部离线工具包与插件的下载、校验与解压预装。当您的 Kindle Voyage 到手后，配合本指南与配套的一键脚本，即可在 15~20 分钟内完成全套越狱与微信读书部署。

---

## 目录结构说明

本机准备目录位于：`/Users/mac/Documents/antigravity/wonderful-rutherford/Kindle_Voyage_Toolkit/`

```text
Kindle_Voyage_Toolkit/
├── macOS一键辅助工具.sh                     <-- 针对 macOS 终端的交互式自动拷贝脚本
├── 00_备用官方固件_5.13.6/                   <-- 官方 5.13.6 最终版固件 (235MB，供古董固件离线升级保底)
│   └── update_kindle_voyage_5.13.6.bin
├── 01_第一步_WatchThis越狱文件/
│   ├── 按固件版本选取写入Kindle根目录的.demo文件夹/
│   │   ├── 固件_5.13.6_适用(最常见)/        <-- 含 demo.json, KV-5.13.6.zip, goodreads 空目录
│   │   │   └── .demo/
│   │   ├── 固件_5.13.5_适用/
│   │   │   └── .demo/
│   │   └── 固件_5.13.4_适用/
│   │       └── .demo/
│   └── 越狱触发后放入Kindle根目录/
│       └── Update_hotfix_watchthis_custom.bin
├── 02_第二步_环境与安装器_MRPI与KUAL/
│   └── 直接复制到Kindle根目录/
│       ├── extensions/                    <-- MRInstaller 安装器核心
│       └── mrpackages/                    <-- 包含待安装的 KUAL Booklet 与最新持久化 Hotfix
│           ├── Update_jailbreak_hotfix_1.16.N_install.bin
│           └── Update_KUALBooklet_v2.7.37_install.bin
├── 03_第三步_阅读器与微信读书插件_KOReader与觅阅/
│   └── 直接复制到Kindle根目录/
│       ├── extensions/                    <-- koreader 快捷启动项
│       └── koreader/                      <-- KOReader 完整运行环境 (kindlepw2 硬件优化版)
│           └── plugins/
│               └── miuread.koplugin/      <-- 觅阅 v5.7.5 微信读书插件 (已预先解压集成)
└── downloads/                             <-- 原始下载归档包 (保留供备份)
```

---

## 核心原理与机型确认

1. **机型特征**：Kindle Voyage (第 7 代，代号 KV，序列号前缀多为 `9013`、`9054`、`9053` 等)。
2. **固件上限**：亚马逊官方针对 Voyage 的最终系统版本停留于 **5.13.6**（不会再推送更新）。
3. **越狱支持**：因固件版本 <= 5.13.6，所有正常工作的 Kindle Voyage **100% 支持纯软件无损越狱**（通过基于演示模式漏洞的 **WatchThis** 方案）。无需拆机拆焊，安全性极高。

---

## 实操步骤详解（机器到手后按此顺序进行）

### 【步骤 0】检查固件版本
1. 打开 Kindle：点击右上角菜单（三个点） -> 【设置 (Settings)】 -> 再次点击菜单 -> 【设备信息 (Device Info)】。
2. 查看【固件版本 (Firmware Version)】：
   - **若版本为 5.13.4、5.13.5 或 5.13.6**：直接进入【步骤 1】。
   - **若版本低于 5.12.2.2**（例如 5.8.x、5.10.x）：
     - 用数据线将 Kindle 连到 Mac。
     - 将 `00_备用官方固件_5.13.6/update_kindle_voyage_5.13.6.bin` 复制到 Kindle 根目录。
     - 弹出 Kindle，进入【设置】 -> 点击菜单 -> 点击【更新您的 Kindle】，等待系统升级到 5.13.6 后再开始。

---

### 【步骤 1】执行 WatchThis 纯软件越狱

> ⚠️ **提示**：越狱会清空本机数据（书籍与个人设置），如有重要本地书籍请先备份到电脑。

1. **恢复出厂设置**：
   - Kindle【设置】 -> 菜单 -> 【重置设备 (Reset)】。
2. **初始化语言设置**：
   - 重启后在语言选择界面，选择 **`English (United Kingdom)`**（必须选英国英语）。
   - 在 Wi-Fi 设置界面，**不要连 Wi-Fi**（点任一网络弹窗后直接点击取消/后退跳过）。
3. **进入演示模式**：
   - 在 Kindle 顶部搜索框中输入：`;enter_demo` 并按回车。
   - 长按电源键弹出菜单，点击 **Restart** 重启设备。
4. **演示模式引导配置**：
   - 重启后屏幕会提示演示模式，Wi-Fi 提示点跳过，个人/店铺信息随意填字母。
   - 寻找 payload 提示点跳过。
   - 演示类型选择 **Standard**。
   - 到“sideload content”页面时，直接点击 **Done**。
5. **破解配置错误弹窗（秘密手势）**：
   - 此时屏幕会弹出一个错误提示窗口（Misconfiguration error）。
   - **关键手势**：使用两根手指同时轻触屏幕右下角，然后单指轻扫向左侧滑动（两指触底后向左划）。
   - 弹窗消失，成功回到搜索栏界面。
6. **写入第一步越狱文件**：
   - 顶部搜索框输入：`;demo` 并按回车。
   - 点击屏幕上的 **Sideload Content**。
   - 用数据线将 Kindle 连到 Mac。
   - 打开终端运行配套助手：
     ```bash
     /Users/mac/Documents/antigravity/wonderful-rutherford/Kindle_Voyage_Toolkit/macOS一键辅助工具.sh
     ```
     选择 `[2]`（或手动将 `01_第一步_WatchThis越狱文件` 下对应固件版本的 `.demo` 文件夹整体复制到 Kindle 根目录）。
   - 在 Mac 上**安全弹出 Kindle**。
   - 在 Kindle 屏幕上点击 **Done**。
7. **触发提权并重启**：
   - 点击屏幕上的 **Exit Demo** 退出演示模式。
   - 在顶部搜索框中输入：`;dsts` 并按回车。
   - 依次点击 **Help & User Guides** -> **Get Started**。
   - Kindle 将自动黑屏并重启，正式进入越狱环境！
8. **安装 WatchThis 收尾补丁**：
   - 开机后，在顶部搜索框输入：`;uzb` 并按回车（开启 USB 存储模式）。
   - 将 Kindle 连到 Mac。
   - 运行助手选择 `[3]`（或手动将 `01_第一步_WatchThis越狱文件/越狱触发后放入Kindle根目录/Update_hotfix_watchthis_custom.bin` 复制到 Kindle 根目录）。
   - 安全弹出 Kindle。
   - 在 Kindle 顶部搜索框输入：`;dsts` 并回车，进入设置菜单，点击 **Update Your Kindle**。
   - 设备自动更新并重启。至此底层越狱大功告成！

---

### 【步骤 2】安装 KUAL 启动器与持久化 Hotfix 环境

1. 用数据线将 Kindle 连接到 Mac。
2. 运行助手选择 `[4]`（或手动将 `02_第二步_环境与安装器_MRPI与KUAL/直接复制到Kindle根目录/` 下的 `extensions` 与 `mrpackages` 两个文件夹直接复制到 Kindle 根目录）。
3. 在 Mac 上安全弹出 Kindle。
4. 在 Kindle 顶部搜索框中输入：
   ```text
   ;log mrpi
   ```
   并按回车。
5. Kindle 屏幕下方会出现黑底控制台安装提示，自动处理 `Update_KUALBooklet_v2.7.37_install.bin` 与 `Update_jailbreak_hotfix_1.16.N_install.bin`。
6. 等待安装结束自动刷新屏幕。在 Kindle 书架或主页上会出现一个名为 **KUAL** 的应用图标！

---

### 【步骤 3】安装 KOReader 及“觅阅”微信读书插件

1. 用数据线将 Kindle 连接到 Mac。
2. 运行助手选择 `[5]`（或手动将 `03_第三步_阅读器与微信读书插件_KOReader与觅阅/直接复制到Kindle根目录/` 下的所有文件复制到 Kindle 根目录）。
   - *注：我们已在本地将觅阅最新版插件 (`miuread.koplugin`) 完整放置于 `koreader/plugins/` 中，拷贝即生效！*
3. 在 Mac 上安全弹出 Kindle。
4. 打开 Kindle 书架上的 **KUAL** 图标，在列表中点击 **KOReader**。
5. 屏幕进入 KOReader 极速墨水屏阅读器界面！

---

### 【步骤 4】配置与登录“觅阅 (MiuRead)”微信读书

1. **连接网络**：在 Kindle 原生系统或 KOReader 的 Wi-Fi 菜单中连接您的家用 Wi-Fi 或手机热点。
2. **开启微信读书**：
   - 点击 KOReader 顶部菜单栏 -> 右上角设置图标（齿轮）或工具箱图标。
   - 点击 **觅阅**（或 **微信读书**）菜单。
3. **扫码登录**：
   - 点击【扫码登录】，屏幕上会呈现高清二维码。
   - 使用手机微信扫一扫授权登录。
4. **开始畅读**：
   - 登录后即可同步您的微信读书书架。
   - 支持【整本离线下载】（排版比自带浏览器好数倍，全屏纯净、翻页极速、支持物理压感按键翻页）。
   - 自动在后台将您的阅读时长、划线笔记、书签与手机端微信读书双向同步。

---

## 常见问题与技巧 (FAQ)

- **Q: 在 Mac 上怎么查看 `.demo` 这种以点开头的隐藏文件夹？**
  - 在 Finder（访达）中打开任意目录，按下快捷键：`Cmd + Shift + .`（Command + Shift + 句号）即可一键切换隐藏文件的显示/隐藏。
- **Q: 之后如果不小心连接 Wi-Fi，会不会自动升级导致越狱失效？**
  - 不会。一方面 Kindle Voyage 官方固件已终生停留在 5.13.6，亚马逊不再推送新版本；另一方面我们在第 2 步中预装了最新的 `1.16.N Hotfix`，具备全方位的越狱自愈与防刷保护。
- **Q: Voyage 屏幕左右两侧的 PagePress 压感按键在 KOReader 里能用吗？**
  - 完全支持！KOReader 原生识别 Voyage 的两侧微震动压感翻页键，可在 KOReader 的【设备】->【按键设置】中按喜好调整压感力度或翻页方向。
