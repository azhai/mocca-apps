import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../data/store.dart';
import 'media_launcher.dart';
import 'widgets/media_actions.dart';

/// 媒体浏览页：在服务器目录间导航，只展示可播放的媒体与子目录。
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final List<String> _stack = ['/'];

  List<MediaObj> _items = const [];
  bool _loading = true;
  String? _error;

  /// 类型筛选：null 表示全部。
  int? _filter;

  /// 网格 / 列表。null 表示按屏幕宽度自动决定。
  bool? _forceGrid;

  String get _path => _stack.last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppStore.instance.api.list(_path);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  void _enter(String name) {
    final next = _path == '/' ? '/$name' : '$_path/$name';
    setState(() => _stack.add(next));
    _load();
  }

  bool _goUp() {
    if (_stack.length <= 1) return false;
    setState(() => _stack.removeLast());
    _load();
    return true;
  }

  /// 目录中用于播放器「上一个 / 下一个」的同类型媒体。
  List<({MediaObj obj, String path})> _siblingsOf(int kind) =>
      playableSiblings(_items, _path, kind);

  /// 应用筛选后的可见条目：目录始终保留（否则无法进入子目录）。
  List<MediaObj> get _visible {
    final playable = _items.where((o) => !o.isDir).toList(growable: false);
    final dirs = _items.where((o) => o.isDir).toList(growable: false);
    // 目录按名称排序；媒体类文件按名称自然顺序（后端已排序，这里保持稳定）
    final media = _filter == null
        ? playable
        : playable.where((o) => o.type == _filter).toList(growable: false);
    return [...dirs, ...media];
  }

  bool get _grid {
    if (_forceGrid != null) return _forceGrid!;
    // 图片目录默认网格，其它默认列表；平板上更倾向网格
    final anyImage = _items.any((o) => o.type == MediaKind.image);
    return anyImage || !context.isCompact;
  }

  void _showItemMenu(MediaObj obj, String childPath) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                obj.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${MediaKind.label(obj.type)} · ${formatSize(obj.size)}'),
            ),
            const Divider(height: 1),
            MediaActions(path: childPath, obj: obj),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        // 仅在「浏览页自身就是顶层路由」时才拦截返回去上级目录，
        // 否则正在播放的视频被 push 在它之上时，系统返回（尤其 Android
        // 预测式返回）会穿透到本路由，误触发 _goUp 把目录往上退一级。
        if (!didPop && (ModalRoute.of(context)?.isCurrent ?? true)) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_stack.length <= 1 ? '浏览' : _path),
          leading: _stack.length > 1
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goUp,
                )
              : null,
          actions: [
            IconButton(
              tooltip: _grid ? '切换为列表' : '切换为网格',
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
              onPressed: () => setState(() => _forceGrid = !_grid),
            ),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    const SizedBox(width: 8),
                    for (final kind in const [
                      MediaKind.video,
                      MediaKind.audio,
                      MediaKind.image,
                    ]) ...[
                      FilterChip(
                        label: Text(MediaKind.label(kind)),
                        selected: _filter == kind,
                        onSelected: (_) =>
                            setState(() => _filter = _filter == kind ? null : kind),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(
                message: _error!,
                onRetry: _load,
                canGoUp: _stack.length > 1,
                onUp: _goUp,
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: _buildBody(theme),
              ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final items = _visible;
    if (items.isEmpty) {
      return ListView(
        // 保证下拉刷新在空列表上仍可用
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  _filter == null ? '该目录为空' : '没有${MediaKind.label(_filter!)}文件',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _grid ? _buildGrid(items) : _buildList(items);
  }

  Widget _buildGrid(List<MediaObj> items) {
    final columns = Breakpoints.gridColumns(MediaQuery.sizeOf(context).width);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final obj = items[i];
        final childPath = _path == '/' ? '/${obj.name}' : '$_path/${obj.name}';
        return _GridCard(
          obj: obj,
          onTap: () => obj.isDir
              ? _enter(obj.name)
              : _open(obj, childPath),
          onLongPress: () => _showItemMenu(obj, childPath),
        );
      },
    );
  }

  Widget _buildList(List<MediaObj> items) {
    final theme = Theme.of(context);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final obj = items[i];
        final childPath = _path == '/' ? '/${obj.name}' : '$_path/${obj.name}';
        final store = AppStore.instance;
        final marks = store.marksOf(childPath);
        final record = store.recordFor(childPath);

        return ListTile(
          leading: _leading(theme, obj, childPath),
          title: Text(
            obj.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _subtitle(theme, obj, record),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (marks.favorite)
                Icon(
                  Icons.favorite,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              if (marks.later)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.watch_later,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: '更多',
                onPressed: () => _showItemMenu(obj, childPath),
              ),
            ],
          ),
          onTap: () => obj.isDir ? _enter(obj.name) : _open(obj, childPath),
          onLongPress: () => _showItemMenu(obj, childPath),
        );
      },
    );
  }

  Future<void> _open(MediaObj obj, String childPath) async {
    var kind = obj.type;
    if (!MediaKind.isPlayable(kind)) kind = guessKindFromName(obj.name);
    if (!MediaKind.isPlayable(kind)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${obj.name}」不是可播放的媒体文件')),
      );
      return;
    }
    final siblings = _siblingsOf(kind);
    await openMedia(
      context,
      obj: obj,
      path: childPath,
      siblings: siblings,
      siblingIndex: indexOfSibling(siblings, childPath),
    );
  }

  Widget _leading(ThemeData theme, MediaObj obj, String childPath) {
    if (obj.isDir) {
      return CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.folder,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
    }
    final thumb = obj.thumb.isEmpty
        ? null
        : AppStore.instance.api.resolveUrl(obj.thumb);
    if (thumb != null && obj.type == MediaKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: thumb,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _kindIcon(theme, obj),
          placeholder: (_, _) => _kindIcon(theme, obj),
        ),
      );
    }
    return _kindIcon(theme, obj);
  }

  Widget _kindIcon(ThemeData theme, MediaObj obj) => CircleAvatar(
    backgroundColor: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      switch (obj.type) {
        MediaKind.video => Icons.movie_outlined,
        MediaKind.audio => Icons.music_note_outlined,
        MediaKind.image => Icons.image_outlined,
        _ => Icons.insert_drive_file_outlined,
      },
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );

  Widget _subtitle(ThemeData theme, MediaObj obj, PlayRecord? record) {
    final parts = <String>[MediaKind.label(obj.type)];
    if (!obj.isDir && obj.size > 0) parts.add(formatSize(obj.size));
    if (record != null) {
      if (record.durationMs > 0) {
        parts.add(
          record.isFinished
              ? '已看完'
              : '看到 ${formatDuration(record.positionMs)}',
        );
      } else if (record.kind == MediaKind.image) {
        parts.add('看过 ${formatRelative(record.updatedAt)}');
      }
    }
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );
  }
}

/// 网格卡片：图片显示缩略图，其它显示类型图标；底部可选择显示进度条。
class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.obj,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaObj obj;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = obj.type == MediaKind.image;
    final thumb = obj.thumb.isEmpty
        ? null
        : AppStore.instance.api.resolveUrl(obj.thumb);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: obj.isDir
                  ? Icon(
                      Icons.folder,
                      size: 48,
                      color: theme.colorScheme.primary,
                    )
                  : thumb != null && isImage
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorWidget: (_, _, _) => Icon(
                        Icons.image_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      switch (obj.type) {
                        MediaKind.video => Icons.movie_outlined,
                        MediaKind.audio => Icons.music_note_outlined,
                        MediaKind.image => Icons.image_outlined,
                        _ => Icons.insert_drive_file_outlined,
                      },
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    obj.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (!obj.isDir && obj.size > 0)
                    Text(
                      formatSize(obj.size),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.canGoUp,
    required this.onUp,
  });

  final String message;
  final VoidCallback onRetry;

  /// 是否处于子目录。注意这里用纯数据传入，不要在 build 期间调用会改状态的回调。
  final bool canGoUp;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canGoUp) ...[
                OutlinedButton(onPressed: onUp, child: const Text('返回上级')),
                const SizedBox(width: 12),
              ],
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ],
      ),
    ),
  );
}
