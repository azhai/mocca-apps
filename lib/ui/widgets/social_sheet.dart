import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/social.dart';
import '../../data/social_store.dart';
import '../../data/store.dart';

/// 打开弹幕 / 评论面板。
///
/// [position] 用于把弹幕发在当前播放时刻；[danmakuVisible] 是播放页里那个
/// 弹幕开关的同一份状态，在面板里切换会直接作用到画面上。
Future<void> showSocialSheet(
  BuildContext context, {
  required SocialStore store,
  required ValueListenable<int> position,
  required ValueNotifier<bool> danmakuVisible,
  ValueChanged<int>? onSeek,
}) async {
  await store.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SocialSheet(
      store: store,
      position: position,
      danmakuVisible: danmakuVisible,
      onSeek: onSeek,
    ),
  );
}

/// 弹幕与评论面板：两个 Tab 各带一个输入框，未登录时只能看不能发。
class SocialSheet extends StatefulWidget {
  const SocialSheet({
    super.key,
    required this.store,
    required this.position,
    required this.danmakuVisible,
    this.onSeek,
  });

  final SocialStore store;
  final ValueListenable<int> position;

  /// 与播放页共用的弹幕显示开关。
  final ValueNotifier<bool> danmakuVisible;

  /// 点击弹幕时跳转到的时刻（毫秒）。
  final ValueChanged<int>? onSeek;

  @override
  State<SocialSheet> createState() => _SocialSheetState();
}

class _SocialSheetState extends State<SocialSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _danmakuCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  /// 正在回复的评论；为空表示发的是顶层评论。
  String? _replyToId;
  String? _replyToName;

  @override
  void dispose() {
    _tabs.dispose();
    _danmakuCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  bool get _canPost => AppStore.instance.loggedIn;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendDanmaku() async {
    final err = await widget.store.sendDanmaku(
      offsetMs: widget.position.value,
      content: _danmakuCtrl.text,
    );
    if (!mounted) return;
    if (err != null) return _notify(err);
    _danmakuCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _sendComment() async {
    final err = await widget.store.sendComment(
      content: _commentCtrl.text,
      parentId: _replyToId ?? '',
    );
    if (!mounted) return;
    if (err != null) return _notify(err);
    _commentCtrl.clear();
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _remove(SocialEntry e) async {
    final err = await widget.store.delete(e);
    if (!mounted) return;
    if (err != null) _notify(err);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 键盘弹出时把输入行顶上来，否则输入框会被遮住
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_buildDanmakuTab(), _buildCommentTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('弹幕与评论', style: theme.textTheme.titleMedium),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: widget.danmakuVisible,
                builder: (context, visible, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('弹幕'),
                    Switch(
                      value: visible,
                      onChanged: (v) => widget.danmakuVisible.value = v,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '弹幕 ${widget.store.danmaku.length}'),
            Tab(text: '评论 ${widget.store.commentCount}'),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────── 弹幕

  Widget _buildDanmakuTab() {
    return Column(
      children: [
        _InputBar(
          controller: _danmakuCtrl,
          hint: '发条弹幕…',
          maxLength: maxDanmakuLength,
          enabled: _canPost && !widget.store.sending,
          lockedHint: '登录后可发送弹幕',
          button: '发送',
          onSend: _sendDanmaku,
          leading: ValueListenableBuilder<int>(
            valueListenable: widget.position,
            builder: (context, ms, _) => Chip(
              visualDensity: VisualDensity.compact,
              label: Text(formatDuration(ms)),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              final store = widget.store;
              if (store.loadingDanmaku && !store.loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              if (store.danmakuError != null) {
                return _Hint(
                  message: store.danmakuError!,
                  action: '重试',
                  onAction: store.refresh,
                );
              }
              if (store.danmaku.isEmpty) {
                return const _Hint(message: '还没有弹幕，来发第一条');
              }
              return RefreshIndicator(
                onRefresh: store.refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: store.danmaku.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final e = store.danmaku[i];
                    return ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 52,
                        child: Text(
                          formatDuration(e.offsetMs),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      title: Text(e.content),
                      subtitle: Text(e.userName),
                      trailing: _canDelete(e)
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除',
                              onPressed: () => _remove(e),
                            )
                          : null,
                      onTap: widget.onSeek == null
                          ? null
                          : () => widget.onSeek!(e.offsetMs),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────── 评论

  Widget _buildCommentTab() {
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              final store = widget.store;
              if (store.loadingComments && !store.loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              if (store.commentsError != null) {
                return _Hint(
                  message: store.commentsError!,
                  action: '重试',
                  onAction: store.refresh,
                );
              }
              if (store.comments.isEmpty) {
                return const _Hint(message: '还没有评论，来说两句');
              }
              return RefreshIndicator(
                onRefresh: store.refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: store.comments.length,
                  itemBuilder: (context, i) {
                    final thread = store.comments[i];
                    return _CommentTile(
                      entry: thread.root,
                      deletable: _canDelete(thread.root),
                      onDelete: () => _remove(thread.root),
                      onReply: () {
                        setState(() {
                          _replyToId = thread.root.id;
                          _replyToName = thread.root.userName;
                        });
                        FocusScope.of(context).requestFocus();
                      },
                      replies: [
                        for (final r in thread.replies)
                          _CommentTile(
                            entry: r,
                            isReply: true,
                            deletable: _canDelete(r),
                            onDelete: () => _remove(r),
                            onReply: () {
                              // 只支持一层回复，回复回复时仍挂到同一条顶层评论下
                              setState(() {
                                _replyToId = thread.root.id;
                                _replyToName = r.userName;
                              });
                            },
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        _InputBar(
          controller: _commentCtrl,
          hint: '说点什么…',
          maxLength: maxCommentLength,
          enabled: _canPost && !widget.store.sending,
          lockedHint: '登录后可发表评论',
          button: '发表',
          onSend: _sendComment,
          replyingTo: _replyToName,
          onCancelReply: () => setState(() {
            _replyToId = null;
            _replyToName = null;
          }),
        ),
      ],
    );
  }

  /// 只有作者本人与管理员能删。
  bool _canDelete(SocialEntry e) =>
      AppStore.instance.loggedIn &&
      (e.isMine(AppStore.instance.userId) || AppStore.instance.isAdmin);
}

/// 输入行：输入框 + 发送按钮；未登录时整体禁用并给出提示。
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hint,
    required this.maxLength,
    required this.enabled,
    required this.lockedHint,
    required this.button,
    required this.onSend,
    this.leading,
    this.replyingTo,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final bool enabled;
  final String lockedHint;
  final String button;
  final VoidCallback onSend;

  /// 输入框左侧的附加信息（弹幕用它显示当前时间点）。
  final Widget? leading;

  final String? replyingTo;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    '回复 @$replyingTo',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onCancelReply,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: maxLength,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => enabled ? onSend() : null,
                  decoration: InputDecoration(
                    hintText: enabled ? hint : lockedHint,
                    isDense: true,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: enabled ? onSend : null,
                child: Text(button),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一条评论（[isReply] 为 true 时缩进显示）。
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.entry,
    required this.deletable,
    required this.onDelete,
    required this.onReply,
    this.isReply = false,
    this.replies = const [],
  });

  final SocialEntry entry;
  final bool deletable;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  final bool isReply;
  final List<Widget> replies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = avatarColor(entry.userAvatar);
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 56 : 12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isReply ? 14 : 18,
                backgroundColor: color,
                foregroundColor: Colors.white,
                child: Text(
                  avatarLabel(entry.userName),
                  style: TextStyle(fontSize: isReply ? 12 : 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        Text(
                          formatRelative(entry.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(entry.content, style: theme.textTheme.bodyMedium),
                    Row(
                      children: [
                        TextButton(
                          onPressed: onReply,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('回复'),
                        ),
                        if (deletable) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: onDelete,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              foregroundColor: theme.colorScheme.error,
                            ),
                            child: const Text('删除'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ...replies,
        ],
      ),
    );
  }
}

/// 加载中 / 出错 / 空列表的统一占位。
class _Hint extends StatelessWidget {
  const _Hint({required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}
