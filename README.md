# Mocca

Mocca 的移动客户端：**Flutter + Material 3**，同时支持 Android 与 iOS 的手机与平板。

播放 MP4 视频、MP3 音频、JPG/PNG 图片；服务器地址可改；本地记录观看时长与上次停顿位置，并支持收藏与稍后再看。

---

## 快速开始

本仓库就是 Flutter 工程本身（没有子目录嵌套），所有命令都在**仓库根目录**执行。

```bash
flutter pub get        # 或 make get

# 运行（连接真机或模拟器）
flutter run            # 或 make run

# 生成安装包
flutter build apk --release          # Android
flutter build ios --release          # iOS（需 Xcode 与签名配置）
```

常用操作也可以走 `Makefile`，执行 `make help` 查看全部目标：

| 目标 | 作用 |
| --- | --- |
| `make get` / `make upgrade` | 拉取 / 升级依赖 |
| `make analyze` / `make format` | 静态分析 / 格式化 |
| `make test` / `make test-cover` | 跑测试 / 带覆盖率 |
| `make run` / `make devices` / `make doctor` | 运行、列设备、检查工具链 |
| `make build-apk` / `make build-aab` | Android APK / AAB |
| `make build-ios` / `make build-ipa` | iOS 不签名 app / 导出 IPA |
| `make pod` / `make clean` | 装 iOS Pods / 清理产物 |

构建产物统一复制到 `dist/`，文件名带 `pubspec.yaml` 里的版本号。

首次启动会让你填写**服务器地址**，点击「测试连接」确认可达后登录。

支持两种凭证：

| 方式 | 适用场景 |
| --- | --- |
| 用户名 + 密码 | 普通用户。密码在本地做静态哈希后传输，不发明文 |
| 管理员令牌 | 服务器设置里的 `token`，适合只播放不管理 |

---

## 功能

### 浏览
- 目录导航（进入子目录、返回上级、Android 返回键联动）
- 类型筛选：全部 / 视频 / 音频 / 图片
- 网格与列表两种视图，可手动切换（图片目录默认网格）
- 下拉刷新；错误态可重试或返回上级

### 播放
| 类型 | 实现 | 能力 |
| --- | --- | --- |
| MP4 视频 | `video_player` | 续播、拖动进度、±10 秒、0.5×~2× 变速、累计观看时长 |
| MP3 音频 | `just_audio` | 续播、同目录上一首/下一首、随机、循环模式（关/列表/单曲） |
| JPG/PNG 图片 | `cached_network_image` + `InteractiveViewer` | 捏合缩放、双击缩放（锚定画面中心）、左右切换同目录图片 |

### 弹幕与评论

视频画面上叠一层滚动弹幕，底部控制栏可一键显示 / 隐藏；旁边的气泡按钮打开
「弹幕 / 评论」面板，两个 Tab 各带输入框。

| | 弹幕 | 评论 |
| --- | --- | --- |
| 展示 | 按时间轴投放到画面上滚动 | 顶层倒序 + 回复（只支持一层） |
| 发送 | 带当前播放时刻，发出后立刻出现在画面上 | 发评论或回复某条 |
| 上限 | 50 字 | 500 字 |
| 删除 | 只能删自己的（管理员除外） | 同左 |

- **实时性**：进入播放页先全量拉一次，随后订阅 SSE 只接收新增条目，别人发的弹幕会即时飘出来
- **只有登录用户能发**；未登录时输入框禁用并提示「登录后可发送…」，读取不受影响
- 拖动进度条后弹幕会按新位置重算，不会一次性涌出上百条；暂停时弹幕冻结在原地
- 弹幕按**媒体内容指纹**锚定（不是路径），所以文件改名、移动都不会丢；
  反过来，媒体若还没被服务器索引，接口会返回「该媒体还没有索引」，面板里直接显示这句提示

> 头像由后端 `/static/avatars/<key>.png` 提供，但那个路径实际返回的是 SVG，
> 而 Flutter 内置解码器不支持 SVG。因此客户端按 key 在本地生成纯色头像
> （昵称首字 + 稳定配色），不额外引入 SVG 依赖。

### 媒体库（本地，不依赖服务器）
- **观看记录**：记录「上次停在哪」与「累计观看多久」，带进度条；显示「看到 12:34 / 45:00」或「已看完」
- **收藏** / **稍后再看**：两个独立分组
- 管理操作：清除播放进度（下次从头播）、从记录移除、清空记录、清空分组

记录存在本机（`SharedPreferences`），**换服务器后仍然保留**。

### 响应式
- 手机（< 600dp）：底部导航栏
- 平板 / 大屏：侧边 `NavigationRail`
- 列表栅格列数随宽度自适应（2 ~ 8 列）

---

## 与后端对接的要点

客户端只依赖这些端点：

| 端点 | 用途 | 登录 |
| --- | --- | --- |
| `POST /api/auth/login/hash` | 登录换 JWT | — |
| `GET /api/me` | 取当前用户、`base_path`，以及**用户 ID**（弹幕评论靠它判断作者） | 是 |
| `POST /api/fs/list` | 列目录（`type`：2=视频 3=音频 5=图片，0=目录） | 否 |
| `POST /api/fs/get` | 取详情，`raw_url` 即可播放地址 | 否 |
| `GET /api/danmaku` | 弹幕列表（可带 `from` / `to` 毫秒窗口，无分页） | 否 |
| `POST /api/danmaku` | 发弹幕（`path` + `offset` 毫秒 + `content`） | **是** |
| `GET /api/comments` | 评论，返回顶层 + `replies`（后端已组装好，别在客户端重新拼父子关系） | 否 |
| `POST /api/comments` | 发评论 / 回复（带 `parent_id` 即回复，只支持一层） | **是** |
| `DELETE /api/comments` | 删自己的评论**或弹幕**（弹幕没有单独的删除接口） | **是** |
| `GET /api/danmaku/stream` | SSE 实时推送新增条目（只推增量；令牌走 `?token=`） | 可选 |

弹幕与评论在后端是同一份 `Entry`（`type`：0=评论 1=弹幕），评论就是「时间点为 0 的弹幕」。

几个容易踩的点，代码里都做了处理：

1. **登录密码需要静态哈希**
   `sha256(明文 + "-" + "https://github.com/alist-org/alist")`（小写十六进制）。
   见 `ApiClient.staticHash`，测试里有黄金值断言。

2. **`raw_url` 是相对路径**
   需要补全为绝对地址。子路径部署（如 `http://host:5244/nas`）时后端返回的路径已含前缀，
   `ApiClient.resolveUrl` 会正确处理这两种情况。

3. **后端返回的业务错误也是 HTTP 200**
   错误码在响应体的 `code` 字段，不能只看 HTTP 状态码。见 `ApiClient._unwrap`。

4. **签名地址不需要 `Authorization` 头**
   `/d`、`/p` 走 URL 签名，因此可以直接交给播放器。但部分存储要求额外请求头，
   后端会在 `header` 字段给出，客户端解析后一并传给播放器。

5. **专属目录由服务端拼接**
   请求里的 `path` 用**相对自己根**的路径（如 `/movies`），不要自行拼 `base_path`。

6. **SSE 要先把字节流攒成帧再解析**
   `/api/danmaku/stream` 用 `\n\n` 分帧，一次 `onData` 可能收到半帧或多帧。
   直接按行处理会在中文等多字节内容被 chunk 切断时拿到半截 JSON；
   `ApiClient.danmakuStream` 用缓冲区分帧，`parseDanmakuFrame` 负责解析。
   另外 dio 的 per-request `receiveTimeout` 为 `null` 时会回退到 `BaseOptions`
   的 30 秒，长连接会被掐断，所以那里显式给了一个足够大的值。

---

## 平台配置（已就绪，勿删）

自建服务器通常是局域网明文 HTTP，两个平台默认都会拦截，因此已预先放开：

- **Android** `android/app/src/main/AndroidManifest.xml`
  - `android:usesCleartextTraffic="true"`
  - 显式声明 `INTERNET` 权限（Flutter 默认只在 debug manifest 里加，release 会漏）
- **iOS** `ios/Runner/Info.plist`
  - `NSAppTransportSecurity` → `NSAllowsArbitraryLoads` / `NSAllowsLocalNetworking`

若上架 App Store 被问到 ATS，说明这是「用户可自定义任意服务器地址」的通用客户端即可。

### 发布签名

- **Android**：`android/app/build.gradle.kts` 会读 `android/key.properties` 里的
  `storeFile / storePassword / keyAlias / keyPassword`。该文件与 `*.jks` 都已在
  `.gitignore` 中忽略，**不会进版本库**；文件缺失时自动回退到 debug 签名，
  所以新克隆的仓库照样能构建（但那份产物不能用于发布）。
  注意 `keyAlias` 必须与 keystore 里的条目名**完全一致**，否则打包时
  `packageRelease` 直接失败，报 `No key with alias 'xxx' found in keystore`。
  用 `keytool -list -keystore android/app/mocca-release.jks` 可以查到实际别名。
- **iOS**：`flutter build ipa` 时用 `export.plist` 指定导出方式（`signingStyle`
  为 `automatic`）。上架前把 `method` 改成 `app-store`，其余分发方式见
  `xcrun xcodebuild -help` 里的 `exportOptionsPlist` 说明。
- **架构**：Android 只打 `arm64-v8a`，限制写在 `buildTypes.release`（不能写进
  `defaultConfig`，Flutter 插件会覆盖它）；iOS 为 arm64 真机。

### 原生编译必须先清环境变量（重要）

`make` 里所有会触发原生编译的目标（`build-apk` / `build-aab` / `build-ios` /
`build-ipa` / `run` / `pod`）都通过 `ENV_CLEAN` 先 `env -u` 掉
`SDKROOT / CC / CXX / LD / C_INCLUDE_PATH / CPLUS_INCLUDE_PATH / LIBRARY_PATH / CPATH / LDFLAGS`
再调 `flutter`。这几个变量常由 `~/.zprofile` 为了命令行编 C/C++ 而导出，
指向 Homebrew LLVM 与 **macOS SDK**，一旦被继承就会踩两个坑：

- **Android**：NDK 的 clang 会把 macOS SDK 的头文件也算进搜索路径，
  `jni` 之类带 C/C++ 代码的插件编译时报
  `#error Unsupported architecture`（macOS 的 `machine/_types.h` 不认
  `aarch64-linux-android`），失败点是 `:jni:buildCMake...`；
- **iOS**：xcodebuild 抓错 libobjc，链接时报
  `Building for iOS, but linking in dylib built for macOS`。

所以**不要绕过 Makefile 直接裸跑 `flutter build apk`**；确需裸跑时记得自己清变量。
另外 Gradle daemon 会带着启动时的环境存活，改完变量后建议先
`cd android && ./gradlew --stop` 再重来。

### 版本库约定

- 忽略规则只在**根目录 `.gitignore`** 一份，`android/` 与 `ios/` 原来的两份已合并进去，
  路径统一写成仓库根相对路径。
- Gradle wrapper（`android/gradlew`、`gradlew.bat`、`gradle/wrapper/gradle-wrapper.jar`）
  是**入库**的——少了它们新克隆的仓库无法构建 Android，不要加进忽略列表。
- 反过来，签名材料（`*.jks`、`*.keystore`、`key.properties`）与本机状态
  （`local.properties`、`ios/Pods`、`xcuserdata`）一律不入库。

---

## 代码结构

```
lib/
├── main.dart                    入口 + 响应式导航壳
├── core/
│   ├── api_client.dart          后端契约、登录哈希、地址规范化、SSE 分帧
│   ├── models.dart              MediaObj / MediaDetail / Session / PlayRecord / SavedItem
│   ├── social.dart              弹幕 / 评论模型、长度校验、SSE 帧解析、头像配色
│   ├── theme.dart               M3 主题 + 断点
│   └── format.dart              时长 / 体积 / 相对时间
├── data/
│   ├── store.dart               全局状态 + 本地媒体库持久化
│   └── social_store.dart        单个媒体的弹幕 / 评论：加载、发送、删除、实时追加
└── ui/
    ├── login_page.dart          服务器配置 + 登录
    ├── browse_page.dart         目录浏览
    ├── library_page.dart        观看记录 / 收藏 / 稍后再看
    ├── settings_page.dart       服务器、账号、本地数据
    ├── media_launcher.dart      取播放地址 → 分流到对应播放器
    ├── player/
    │   ├── video_page.dart
    │   ├── audio_page.dart
    │   └── image_page.dart
    └── widgets/
        ├── media_actions.dart
        ├── danmaku_layer.dart   弹幕画布：时间轴调度 + 轨道滚动
        └── social_sheet.dart    弹幕 / 评论面板
```

状态管理用 Flutter 内置的 `ChangeNotifier` + `ListenableBuilder`，未引入额外状态库。

---

## 测试

```bash
flutter analyze   # 应为 No issues found
flutter test      # 51 个用例（44 个纯逻辑 + 7 个 widget）
```

`make test` 等价；`make test-cover` 额外生成 `coverage/lcov.info`。

弹幕这块覆盖的是纯逻辑与调度行为：长度校验（emoji 按码点）、SSE 帧解析
（含半帧与心跳帧）、评论线程组装，以及弹幕图层在**拖动进度条**、**暂停**、
**切换显示**下的表现。

测试覆盖的是纯逻辑，其中两条是有实际防回归价值的：

- **静态哈希黄金值** —— 与真实后端联调确认过的哈希，公式被改动会立刻失败
- **地址解析** —— 覆盖根路径 / 子路径部署下的相对与绝对地址

> 这两条测试在开发时就抓到过真实缺陷：`Uri.replace(query:'', fragment:'')` 会留下 `?#`，
> 进而让子路径部署下的相对地址丢掉 `/nas` 前缀。

---

## 已知限制

- 视频播放器未做横屏全屏与画中画（`enterImmersive()` 已备好，尚未接入按钮）
- 音频未做后台播放与锁屏控制（需要额外的原生配置与权限）
- 图片不提供「保存到相册」
- 观看记录上限 500 条，超出淘汰最旧
