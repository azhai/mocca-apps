import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../data/store.dart';

/// 登录 / 注册页。
///
/// 定位说明：本页**不再是应用入口**。浏览目录不需要登录，因此应用启动
/// 直接进入主界面；本页只从「设置」或「个人」页按需推入，用于：
/// 1. 登录（用户名 + 密码，密码在本地做静态哈希后传输）
/// 2. 注册（服务端开启后可用；成功后自动登录）
/// 3. 管理员令牌登录（适合只做播放、不需要账号的场景）
///
/// 服务器地址与接口前缀属于「连接配置」，统一放在设置页里改，这里只做展示，
/// 避免同一项配置出现两个入口、互相覆盖。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// 页面上的三种凭证方式。
enum _AuthMode {
  login('登录', Icons.login),
  register('注册', Icons.person_add_alt),
  token('令牌', Icons.key_outlined);

  const _AuthMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _token = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _confirm.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final store = AppStore.instance;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      switch (_mode) {
        case _AuthMode.login:
          await store.login(_user.text.trim(), _pass.text);
        case _AuthMode.register:
          await store.register(_user.text.trim(), _pass.text);
        case _AuthMode.token:
          await store.loginWithToken(_token.text.trim());
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _mode == _AuthMode.register ? '注册成功，已自动登录' : '已登录',
          ),
        ),
      );
      // 从设置 / 个人页推入的，登录成功即返回
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              // 平板上限宽，避免输入框被拉伸得过宽
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Brand(theme: theme),
                    const SizedBox(height: 24),

                    SegmentedButton<_AuthMode>(
                      segments: [
                        for (final m in _AuthMode.values)
                          ButtonSegment(
                            value: m,
                            label: Text(m.label),
                            icon: Icon(m.icon, size: 18),
                          ),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _mode = s.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 20),

                    if (_mode == _AuthMode.token)
                      TextFormField(
                        controller: _token,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '管理员令牌',
                          hintText: '服务器「设置 → 其他」中的 token',
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? '请填写令牌' : null,
                        onFieldSubmitted: (_) => _submit(),
                      )
                    else ...[
                      TextFormField(
                        controller: _user,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return '请填写用户名';
                          if (_mode == _AuthMode.register && s.length < 3) {
                            return '用户名至少 3 个字符';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pass,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? '显示密码' : '隐藏密码',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          final s = v ?? '';
                          if (s.isEmpty) return '请填写密码';
                          if (_mode == _AuthMode.register && s.length < 6) {
                            return '密码至少 6 位';
                          }
                          return null;
                        },
                      ),
                      if (_mode == _AuthMode.register) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: '确认密码',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (v) =>
                              v != _pass.text ? '两次输入的密码不一致' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!, theme: theme),
                    ],

                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_mode.icon),
                      label: Text(
                        _busy
                            ? '处理中…'
                            : (_mode == _AuthMode.register ? '注册并登录' : '登录'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _mode == _AuthMode.register
                          ? '注册需要服务端开启该功能；未开启时会提示相应错误。'
                          : '浏览目录不需要登录，登录后才会记录播放历史与收藏。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 品牌区：抹茶色咖啡杯 + 名称。
class _Brand extends StatelessWidget {
  const _Brand({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primaryContainer,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Icon(
            Icons.local_cafe_rounded,
            size: 34,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Mocca',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '连接你的 Mocca 服务器',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.theme});

  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
