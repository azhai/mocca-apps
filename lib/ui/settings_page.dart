import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../data/store.dart';
import 'login_page.dart';

/// 设置页：连接配置、账号、本地数据。
///
/// 刻意不展示「专属资源目录」（后端返回的 base_path）：
/// 它是服务端按账号下发的实现细节，对使用者没有可操作性，显示出来只会造成困惑。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _SectionHeader('外观'),
            _AppearanceSection(),
            const Divider(height: 8),
            const _SectionHeader('连接'),
            _ValueTile(
              icon: Icons.dns_outlined,
              title: '服务器域名',
              value: store.serverUrl,
              onTap: () => _edit(
                context,
                title: '服务器域名',
                hint: 'http://mocca.vod',
                helper: '应用连接的服务器地址，默认 http://mocca.vod:8000。',
                current: store.serverUrl,
                onSave: store.setServerUrl,
                requireNonEmpty: true,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: const Text('测试连接'),
              subtitle: Text('探测 ${store.serverUrl} 是否可达'),
              onTap: () => _testConnection(context),
            ),

            const Divider(height: 24),
            const _SectionHeader('账号'),
            ListTile(
              leading: Icon(
                store.loggedIn ? Icons.account_circle : Icons.person_outline,
              ),
              title: Text(store.loggedIn ? store.username : '未登录'),
              subtitle: Text(
                store.loggedIn ? '观看记录与收藏已归属到该账号' : '未登录也可以浏览；登录后才会记录个人数据',
              ),
            ),
            if (store.loggedIn)
              ListTile(
                leading: const Icon(Icons.switch_account_outlined),
                title: const Text('切换账号'),
                onTap: () => _openAuth(context),
              ),
            ListTile(
              leading: Icon(store.loggedIn ? Icons.logout : Icons.login),
              title: Text(store.loggedIn ? '退出登录' : '登录 / 注册'),
              subtitle: Text(
                store.loggedIn ? '仅清除本机令牌与账号信息，不影响服务器数据' : '在服务器上已有账号，或注册一个新账号',
              ),
              onTap: () async {
                if (!store.loggedIn) {
                  await _openAuth(context);
                  return;
                }
                final ok = await _confirmLogout(context);
                if (ok == true) await store.logout();
              },
            ),

            const Divider(height: 24),
            const _SectionHeader('本地数据'),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('观看记录'),
              subtitle: Text(
                store.loggedIn ? '${store.history.length} 条' : '未登录时不展示',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('收藏'),
              subtitle: Text(
                store.loggedIn ? '${store.favorites.length} 项' : '未登录时不展示',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.watch_later_outlined),
              title: const Text('稍后再看'),
              subtitle: Text(
                store.loggedIn ? '${store.watchLater.length} 项' : '未登录时不展示',
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '清空全部本地数据',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('观看记录、收藏、稍后再看将全部删除'),
              onTap: () => _clearAll(context),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 交互

  Future<void> _openAuth(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
  }

  Future<bool?> _confirmLogout(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('退出登录？'),
      content: const Text('本机的观看记录、收藏与稍后再看会保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('退出'),
        ),
      ],
    ),
  );

  /// 通用「单值编辑」弹窗。地址类走 [ApiClient.normalizeBaseUrl]。
  Future<void> _edit(
    BuildContext context, {
    required String title,
    required String hint,
    required String helper,
    required String current,
    required Future<void> Function(String) onSave,
    bool requireNonEmpty = false,
  }) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(hintText: hint, helperText: helper),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    final normalized = ApiClient.normalizeBaseUrl(value);
    if (requireNonEmpty && normalized.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('地址不合法，请检查后重试')));
      }
      return;
    }
    await onSave(normalized);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _testConnection(BuildContext context) async {
    final store = AppStore.instance;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在测试连接…')));
    final err = await store.api.ping();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(err ?? '连接成功：${store.serverUrl}')),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final store = AppStore.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部本地数据？'),
        content: const Text('观看记录、收藏与稍后再看都会被删除，且不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.clearHistory();
    await store.clear(SavedGroup.favorite);
    await store.clear(SavedGroup.watchLater);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清空本地数据')));
    }
  }
}

/// 「标题 + 当前值」的行，点击进入编辑。
class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 「外观」切换区：四套配色即点即换。
///
/// 页面级已包裹在 [AppStore] 的 [ListenableBuilder] 中，这里直接读取当前配色。
/// 注意：本组件**不能标 const**。父级 [ListenableBuilder] 重建时若新旧实例相同
/// （const 规范化），Flutter 会跳过整棵子树的重建，导致选中高亮停留在旧值上。
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final p in MoccaPalette.values) ...[
            if (p != MoccaPalette.values.first) const SizedBox(width: 8),
            Expanded(
              child: _PaletteChip(
                palette: p,
                selected: store.palette == p,
                onTap: () => store.setPalette(p),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个可选配色：显示主色圆点 + 名称，选中态高亮。
class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final MoccaPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = MoccaTheme.themeOf(palette).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              palette.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
