# Mocca —— Flutter 移动端（Android / iOS）构建脚本
#
# 日常开发：make get / make run / make test
# 打包发布：make build-apk / make build-aab / make build-ipa
# 全部目标：make help

.DEFAULT_GOAL := help

# ── 项目配置 ──────────────────────────────────────────

APP = mocca
# 产物输出目录
DIST = dist
# 版本号取自 pubspec.yaml（形如 1.0.0+1），仅用于给产物文件命名
VERSION ?= $(shell awk '/^version:/{print $$2; exit}' pubspec.yaml)

# flutter 在 PATH 里即可；用 fvm / asdf 时可用 `make FLUTTER=fvm\ flutter test` 覆盖
FLUTTER ?= flutter

# Xcode 构建会继承 shell 里的 CC/CXX/LD/SDKROOT 等变量。若这些变量被指向
# Homebrew LLVM 或 macOS SDK，xcodebuild（以及 flutter build ios 内部调用的
# pod）在链接 iOS 目标时会抓错 libobjc，报
#   "Building for iOS, but linking in dylib built for macOS"
# 因此 iOS 相关目标统一清掉这几个变量后再执行。
ENV_CLEAN = env -u SDKROOT -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u CPATH \
            -u LIBRARY_PATH -u CC -u CXX -u LD -u LDFLAGS

# 只打 arm64：限制写在 android/app/build.gradle.kts 的 buildTypes.release 里，
# 单包体积从 ~56MB 降到 ~21MB。不要再加 --target-platform，会与 Gradle 配置打架。
# IPA 的文件名由 Xcode 的 PRODUCT_NAME 决定（默认 Runner），所以用通配而不是写死
APK = build/app/outputs/flutter-apk/app-release.apk
AAB = build/app/outputs/bundle/release/app-release.aab
IPA = build/ios/ipa/*.ipa

.PHONY: help get upgrade analyze format test test-cover run devices doctor \
        build-apk build-aab build-ios build-ipa build-all pod clean

## help: 列出所有可用目标
help:
	@grep -hE '^## [a-zA-Z_-]+: ' $(MAKEFILE_LIST) \
		| sed 's/^## //' \
		| awk -F': ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# ── 依赖与检查 ────────────────────────────────────────

## get: 拉取依赖（flutter pub get）
get:
	$(FLUTTER) pub get

## upgrade: 升级依赖到大版本最新（会改 pubspec.yaml，记得 review）
upgrade:
	$(FLUTTER) pub upgrade --major-versions

## analyze: 静态分析，CI 里应保持 0 issue
analyze:
	$(FLUTTER) analyze

## format: 按 dart format 规范格式化 lib/ 与 test/
format:
	dart format lib test

## doctor: 检查本机 Flutter / Xcode / Android 工具链
doctor:
	$(FLUTTER) doctor -v

## devices: 列出可运行的真机与模拟器
devices:
	$(FLUTTER) devices

# ── 测试 ──────────────────────────────────────────────

## test: 运行全部测试（24 个单测 + 3 个 widget 测试）
test:
	$(FLUTTER) test

## test-cover: 运行测试并生成覆盖率报告 coverage/lcov.info
test-cover:
	$(FLUTTER) test --coverage
	@echo "✅ 覆盖率报告 → coverage/lcov.info"

# ── 运行 ──────────────────────────────────────────────

## run: 运行到已连接的设备（可用 `make run d=<deviceId>` 指定设备）
run:
	$(FLUTTER) run $(if $(d),-d $(d),)

# ── 打包 ──────────────────────────────────────────────

## build-apk: 构建 Android APK（arm64-only），产物复制到 dist/
build-apk:
	$(FLUTTER) build apk --release
	@mkdir -p $(DIST)
	@cp $(APK) $(DIST)/$(APP)-$(VERSION)-android-arm64.apk
	@echo "✅ APK → $(DIST)/$(APP)-$(VERSION)-android-arm64.apk"

## build-aab: 构建 Android App Bundle（上架 Google Play 用）
build-aab:
	$(FLUTTER) build appbundle --release
	@mkdir -p $(DIST)
	@cp $(AAB) $(DIST)/$(APP)-$(VERSION)-android.aab
	@echo "✅ AAB → $(DIST)/$(APP)-$(VERSION)-android.aab"

## build-ios: 构建 iOS Runner.app（不签名，用于本地验证）
build-ios:
	$(ENV_CLEAN) $(FLUTTER) build ios --release --no-codesign
	@echo "✅ Runner.app → build/ios/iphoneos/Runner.app"

## build-ipa: 导出 iOS IPA（需本机配好签名；导出选项见 export.plist）
build-ipa:
	$(ENV_CLEAN) $(FLUTTER) build ipa --release --export-options-plist=export.plist
	@mkdir -p $(DIST)
	@cp $(IPA) $(DIST)/$(APP)-$(VERSION).ipa
	@echo "✅ IPA → $(DIST)/$(APP)-$(VERSION).ipa"

## build-all: 一次打出 APK / AAB / IPA 三端产物
build-all: build-apk build-aab build-ipa

# ── 维护 ──────────────────────────────────────────────

## pod: 在 ios/ 下执行 pod install（改了插件依赖后需要跑一次）
pod:
	cd ios && $(ENV_CLEAN) pod install

## clean: 清掉所有构建产物（等价于 flutter clean + 删除 dist/）
clean:
	$(FLUTTER) clean
	rm -rf $(DIST) coverage
	@echo "✅ Clean complete."
