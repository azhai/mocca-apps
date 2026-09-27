import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../data/store.dart';
import 'login_page.dart';
import 'media_launcher.dart';
import 'widgets/media_actions.dart';

/// 「个人」页：观看记录、收藏、稍后再看。
///
/// 这些数据都存于本机（SharedPreferences），**不依赖服务器**，换服务器后仍在。
///
/// 与账号的关系（本页的核心设计）：
/// - 未登录时**不展示任何个人记录** —— 因为记录属于「某个人」，没人登录时
///   无法归属给谁，展示出来反而会让共用设备的用户看到别人的痕迹；
/// - 登录后按当前账号展示。账号切换时记录会重新按账号过滤。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('个人'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '观看记录', icon: Icon(Icons.history)),
              Tab(text: '收藏', icon: Icon(Icons.favorite_border)),
              Tab(text: '稍后再看', icon: Icon(Icons.watch_later_outlined)),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            if (!store.loggedIn) return const _NotLoggedInState();
            return const TabBarView(
              children: [
                _HistoryTab(),
                _SavedTab(group: SavedGroup.favorite),
                _SavedTab(group: SavedGroup.watchLater),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 未登录时的占位：说明为什么看不到记录，并给出登录入口。
class _NotLoggedInState extends StatelessWidget {
  const _NotLoggedInState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              '未登录，暂无个人记录',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '观看记录、收藏与稍后再看会归属到具体账号。\n'
              '登录后即可查看，浏览目录无需登录。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginPage()),
              ),
              icon: const Icon(Icons.login),
              label: const Text('登录 / 注册'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 观看记录

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final records = store.history;
        if (records.isEmpty) {
          return const _EmptyState(
            icon: Icons.history_toggle_off,
            title: '还没有观看记录',
            hint: '播放过的视频与音频会出现在这里，并记住上次看到的位置',
          );
        }
        return Column(
          children: [
            _Toolbar(
              summary: '共 ${records.length} 条',
              actions: [
                TextButton.icon(
                  onPressed: () => _confirmClear(context, store),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
            Expanded(child: _HistoryList(records: records)),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context, AppStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空观看记录？'),
        content: const Text('将删除全部播放进度，此操作不可撤销。收藏与稍后再看不受影响。'),
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
    if (ok == true) await store.clearHistory();
  }
}

/// 按「今天 / 昨天 / 具体日期」分组的观看记录列表。
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.records});

  final List<PlayRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // records 已按最近观看倒序，按自然日切分成有序分组，保持倒序
    final groups = <({DateTime day, List<PlayRecord> items})>[];
    for (final r in records) {
      final day = DateTime(
        r.updatedAt.year,
        r.updatedAt.month,
        r.updatedAt.day,
      );
      if (groups.isEmpty || groups.last.day != day) {
        groups.add((day: day, items: [r]));
      } else {
        groups.last.items.add(r);
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              formatDayLabel(groups[i].day),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          for (final r in groups[i].items) _RecordTile(record: r),
        ],
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final PlayRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppStore.instance;
    final marks = store.marksOf(record.path);
    final hasProgress = record.durationMs > 0;

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      leading: _Thumb(
        path: record.path,
        thumb: record.thumb,
        kind: record.kind,
      ),
      title: Text(record.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                switch (record.kind) {
                  MediaKind.video => Icons.movie_outlined,
                  MediaKind.audio => Icons.music_note_outlined,
                  MediaKind.image => Icons.image_outlined,
                  _ => Icons.insert_drive_file_outlined,
                },
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                hasProgress
                    ? (record.isFinished
                          ? '已看完'
                          : '看到 ${formatDuration(record.positionMs)} / ${formatDuration(record.durationMs)}')
                    : MediaKind.label(record.kind),
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                formatRelative(record.updatedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: record.progress,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '累计观看 ${formatDuration(record.watchedMs)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: '更多',
        onPressed: () => _showMenu(context, store, marks),
      ),
      onTap: () => openMedia(
        context,
        obj: objFromSaved(
          name: record.name,
          kind: record.kind,
          thumb: record.thumb,
        ),
        path: record.path,
      ),
      onLongPress: () => _showMenu(context, store, marks),
    );
  }

  void _showMenu(
    BuildContext context,
    AppStore store,
    ({bool favorite, bool later}) marks,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                record.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                record.durationMs > 0
                    ? '上次停在 ${formatDuration(record.positionMs)}'
                    : '观看于 ${formatRelative(record.updatedAt)}',
              ),
            ),
            const Divider(height: 1),
            MediaActions(
              path: record.path,
              obj: objFromSaved(
                name: record.name,
                kind: record.kind,
                thumb: record.thumb,
              ),
              showOpen: true,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('从记录中移除'),
              onTap: () async {
                await store.removeRecord(record.path);
                if (ctx.mounted) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ 收藏 / 稍后再看

class _SavedTab extends StatelessWidget {
  const _SavedTab({required this.group});

  final SavedGroup group;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = group == SavedGroup.favorite
            ? store.favorites
            : store.watchLater;
        if (items.isEmpty) {
          return _EmptyState(
            icon: group == SavedGroup.favorite
                ? Icons.favorite_border
                : Icons.watch_later_outlined,
            title: group == SavedGroup.favorite ? '还没有收藏' : '稍后再看是空的',
            hint: '在浏览页长按任意媒体，或播放时点击右上角图标即可加入',
          );
        }
        return Column(
          children: [
            _Toolbar(
              summary: '共 ${items.length} 项',
              actions: [
                TextButton.icon(
                  onPressed: () => _confirmClear(context, store),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 88),
                itemBuilder: (context, i) =>
                    _SavedTile(item: items[i], group: group),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context, AppStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空${group.label}？'),
        content: Text('将移除全部 ${group.label} 条目，此操作不可撤销。'),
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
    if (ok == true) await store.clear(group);
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.item, required this.group});

  final SavedItem item;
  final SavedGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppStore.instance;
    final record = store.recordFor(item.path);

    return ListTile(
      leading: _Thumb(path: item.path, thumb: item.thumb, kind: item.kind),
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          MediaKind.label(item.kind),
          if (record != null && record.positionMs > 0)
            record.isFinished
                ? '已看完'
                : '看到 ${formatDuration(record.positionMs)}',
          '${group.label}于 ${formatRelative(item.addedAt)}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: '更多',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 1),
                MediaActions(
                  path: item.path,
                  obj: objFromSaved(
                    name: item.name,
                    kind: item.kind,
                    thumb: item.thumb,
                  ),
                  showOpen: true,
                ),
              ],
            ),
          ),
        ),
      ),
      onTap: () => openMedia(
        context,
        obj: objFromSaved(name: item.name, kind: item.kind, thumb: item.thumb),
        path: item.path,
      ),
    );
  }
}

// --------------------------------------------------------------------- 公共

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.thumb, required this.kind});

  final String path;
  final String thumb;
  final int kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 后端 `thumb` 恒为空，老记录里可能存着图片地址；为空就按类型现拼封面，
    // 规则与浏览页共用 ApiClient.coverUrl，历史与目录里的缩略图才长得一样。
    final api = AppStore.instance.api;
    final url = thumb.isNotEmpty
        ? api.resolveUrl(thumb)
        : api.coverUrl(kind, path);
    final showable = url != null && url.isNotEmpty;

    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: showable
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _fallback(theme),
                placeholder: (_, _) => _fallback(theme),
              )
            : _fallback(theme),
      ),
    );
  }

  Widget _fallback(ThemeData theme) => Container(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(switch (kind) {
      MediaKind.video => Icons.movie_outlined,
      MediaKind.audio => Icons.music_note_outlined,
      MediaKind.image => Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    }, color: theme.colorScheme.onSurfaceVariant),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.summary, required this.actions});

  final String summary;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Text(
            summary,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
