# 放课后茶会（K-ON!）车载伴侣 iOS App (巨魔专属)

基于日本 RWC 官方《轻音少女》放学后 Tea Time 导航仪（RM-500HTT）1,122 段原版语音制作的专属 iOS 车载伴侣 App。

---

## 核心功能与安全特性

1. **高强度防盗加密（AES-256-GCM）**
   - 原始 1,122 个散装 WAV 音频全部抹去文件头，并使用 AES-256-GCM 封装在单个二进制资产包 `voice_assets.dat` 中。
   - 即使他人解压 IPA，也只能看到无规则加密二进制，任何播放器或音频提取器均无法直接读取。
   - **零落盘内存解码**：App 运行时通过 iOS 原生 `CryptoKit` 硬件加速在 RAM 运行内存中即时解密，直接送入 `AVAudioPlayer` 播放，**绝不在手机闪存生成任何临时 WAV 缓存**，用 Filza 翻遍沙盒也搜不到明文音频。
   - **密钥混淆**：解密密钥在代码层采用双数组字节异或还原，防止反编译字符串直接提取明文。

2. **后台伴侣与导航混音（MixWithOthers）**
   - 支持后台音频播放（`UIBackgroundModes: audio`）。
   - 启用混音机制，播放台词时**不打断高德地图导航、Apple Music、网易云音乐或播客**。

3. **车载巡航模式（Cruise Mode）**
   - 支持设置 5分钟 / 10分钟 / 15分钟 / 30分钟 间隔。
   - 支持指定单个角色（唯、澪、律、紬、梓）或“全员随机”，在行车过程中提供定时的关怀与提醒语音。

4. **全量台词试听板（Soundboard）**
   - 平泽唯 (1 ~ 196)
   - 秋山澪 (197 ~ 392)
   - 田井中律 (393 ~ 588)
   - 琴吹紬 (589 ~ 784)
   - 中野梓 (785 ~ 980)
   - 角色互动与彩蛋 (981 ~ 1122)

---

## 3 分钟一键生成 TrollStore IPA 教程

无需 Mac 电脑，利用 GitHub 提供的免费 macOS 虚拟机自动编译：

### 第一步：新建 GitHub 私有仓库
1. 登录 [GitHub](https://github.com/)，点击右上角 `+` -> **New repository**。
2. 仓库名称随意填（例如 `HTT-NaviCompanion`）。
3. **重要：请务必选择「Private」（私有仓库）**，确保你的代码与加密音频数据只有你自己能看到。
4. 点击底部 **Create repository**。

### 第二步：上传本项目全部文件
将本工程解压后的所有文件（包含 `.github` 隐藏文件夹、`KOnNaviCompanion` 文件夹、`KOnNaviCompanion.xcodeproj`）完整上传或推送到该仓库。

*如果使用网页端上传：可以直接将解压后的文件夹整体拖入 GitHub 网页端上传提交。*

### 第三步：点击运行构建工作流
1. 打开该仓库上方的 **Actions** 标签页。
2. 左侧点击 **Build TrollStore IPA**。
3. 点击右侧的 **Run workflow** -> 绿色按钮 **Run workflow**。
4. GitHub 会启动搭载最新 Xcode 的 macOS 虚拟机自动拉取、编译与打包，耗时约 2~3 分钟。

### 第四步：下载并安装到 iPhone
1. 编译完成后，点击刚刚运行成功的构建记录（带绿色勾）。
2. 在页面最下方的 **Artifacts** 区域，点击 **KOnNaviCompanion-TrollStore** 即可下载生成的 `KOnNaviCompanion.ipa`。
3. 将下载好的 IPA 发送到 iPhone（可通过 AirDrop、微云、夸克网盘或手机 Safari 直接下载）。
4. 在 iPhone 上点击该文件 -> 选择“用 TrollStore 打开并安装”，完成！
