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

  /// 用户显式选择的网格 / 列表。null 表示由 [_autoGrid] 决定。
  bool? _forceGrid;

  /// 自动判定的视图模式：每次载入目录时按当时的宽度算一次并固定。
  ///
  /// 关键在于「固定」：若让它随宽度实时变化，播放页盖在上面转横屏时
  /// （宽度越过平板断点）列表会变成网格。两者是不同的滚动组件，
  /// 互换会把它整个重建，滚动位置随之归零，返回时就回不到原来那一屏。
  bool _autoGrid = false;

  /// 网格滚动控制器。宽度变化后要把位置按新排版换算回来，得有入口。
  /// `keepScrollOffset: false`：位置的记忆交给下面的锚点，避免隐式的
  /// PageStorage 恢复掺进来。
  final ScrollController _gridScroll = ScrollController(
    keepScrollOffset: false,
  );

  /// 上一次布局用到的网格排版，用来判断宽度变化有没有改动排版。
  _GridMetrics? _gridMetrics;

  /// 网格的阅读锚点：视口顶部所在行 + 行内比例。用户滚动时持续更新。
  ///
  /// 专门记「第几行」而不是像素：列数 / 格高随宽度变，同一个像素在新排版
  /// 下会落到别的条目上；而且排版变窄时像素会被裁到末尾，事后从像素也
  /// 推不回原来的行。
  ({int row, double ratio})? _gridAnchor;

  /// 正在按新排版还原锚点。这段时间里位置是被排版挤压 / 裁掉的，不是用户
  /// 读到的地方，所以不接受新的锚点写入（还原自身也会发出滚动通知）。
  bool _restoringGridAnchor = false;

  String get _path => _stack.last;

  /// 条目在当前目录下的完整路径。
  String _childPath(MediaObj obj) =>
      _path == '/' ? '/${obj.name}' : '$_path/${obj.name}';

  @override
  void initState() {
    super.initState();
    _gridScroll.addListener(_captureGridAnchor);
    _load();
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final metrics = _gridMetricsFor(
      MediaQuery.sizeOf(context).width,
      MediaQuery.textScalerOf(context),
    );
    final prev = _gridMetrics;
    // 宽度变化会改变列数与格高（转横屏尤其明显）。像素偏移不能直接沿用：
    // 同一个像素在新排版下会落到别的条目上，偏出几十行都有可能。改用记住的
    // 阅读锚点，等新排版铺好后换算回像素跳过去。
    if (prev != null &&
        prev != metrics &&
        _grid &&
        _gridScroll.hasClients &&
        _gridAnchor != null) {
      _restoringGridAnchor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyGridAnchor());
    }
    _gridMetrics = metrics;
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
        // 换目录时重新按当前宽度判定一次默认视图，之后不再随宽度变化
        _autoGrid = _decideAutoGrid(items);
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

  bool get _grid => _forceGrid ?? _autoGrid;

  /// 默认视图的判定：图片目录用网格，其它用列表；平板上更倾向网格。
  bool _decideAutoGrid(List<MediaObj> items) =>
      items.any((o) => o.type == MediaKind.image) || !context.isCompact;

  /// 切换网格 / 列表。切过去是另一套滚动组件，位置从头开始，锚点一并作废。
  void _toggleGrid() {
    setState(() {
      _forceGrid = !_grid;
      // 锚点记的是切换前那一套排版里的行；留着它，下一次宽度变化会把用户
      // 拽回切换前读到的位置，与眼前从头开始的列表对不上。
      _gridAnchor = null;
      _restoringGridAnchor = false;
    });
  }

  /// 网格排版：只取决于可用宽度与字体缩放。
  _GridMetrics _gridMetricsFor(double width, TextScaler textScaler) {
    final spec = Breakpoints.gridSpec(width);
    // 格高 = 缩略图（按比例）+ 固定说明区。缩略图取 16:10：服务端截的多是
    // 横画幅视频帧，这个比例最接近原图、上下留白最少。
    return (
      columns: spec.columns,
      margin: spec.margin,
      gutter: spec.gutter,
      tileWidth: spec.tileWidth,
      tileHeight: spec.tileWidth * 10 / 16 + _gridFooterHeight(textScaler),
    );
  }

  /// 像素偏移 → 「视口顶部是第几行 + 行内比例」。
  ///
  /// 减去外边距：网格的 padding 也是滚动内容的一部分，第 0 行的顶边在
  /// `margin` 处，不是 0。
  static ({int row, double ratio}) _anchorOf(double pixels, _GridMetrics m) {
    final y = pixels - m.margin;
    if (y <= 0) return (row: 0, ratio: 0);
    final extent = m.tileHeight + m.gutter;
    final row = y ~/ extent;
    return (row: row, ratio: (y - row * extent) / extent);
  }

  /// 用户滚动时更新阅读锚点。还原期间不接受写入：那段时间的位置是被新排版
  /// 挤压 / 裁掉的，不是用户读到的地方，照它记下来会把锚点一起带偏。
  void _captureGridAnchor() {
    if (_restoringGridAnchor) return;
    final m = _gridMetrics;
    final positions = _gridScroll.positions;
    // 只在唯一的滚动位置上取锚点：过渡帧里可能一个都还没挂上，或新旧并存。
    if (m == null || positions.length != 1) return;
    final p = positions.first;
    if (!p.hasPixels || !p.hasContentDimensions) return;
    final anchor = _anchorOf(p.pixels, m);
    // 已经在顶部时不必还原，留 null 也免得把外边距当成一行记下来。
    _gridAnchor = (anchor.row > 0 || anchor.ratio > 0) ? anchor : null;
  }

  /// 锚点 → 当前排版下的像素偏移（把同一行按原比例放回视口顶部）。
  static double _pixelsOf(({int row, double ratio}) anchor, _GridMetrics m) =>
      m.margin + (anchor.row + anchor.ratio) * (m.tileHeight + m.gutter);

  /// 把阅读锚点落到新排版上。排版刚换过，得等这一帧铺完、新的
  /// `maxScrollExtent` 出来后才能跳。
  ///
  /// 注意这里用的是记下的锚点，而不是当前的像素偏移：新排版更矮时当前像素
  /// 早被裁到末尾了，从它推不回用户原本读到的那一行。
  void _applyGridAnchor() {
    final anchor = _gridAnchor;
    final metrics = _gridMetrics;
    if (anchor == null ||
        metrics == null ||
        !mounted ||
        !_gridScroll.hasClients) {
      _restoringGridAnchor = false;
      return;
    }
    _gridScroll.jumpTo(
      _pixelsOf(
        anchor,
        metrics,
      ).clamp(0.0, _gridScroll.position.maxScrollExtent),
    );
    // jumpTo 会同步发出滚动通知，放在它后面复位，那次通知才被挡住；
    // 之后用户的滚动照常记进锚点。
    _restoringGridAnchor = false;
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
              subtitle: Text(
                '${MediaKind.label(obj.type)} · ${formatSize(obj.size)}',
              ),
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
              ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goUp)
              : null,
          actions: [
            IconButton(
              tooltip: _grid ? '切换为列表' : '切换为网格',
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
              onPressed: _toggleGrid,
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
                        onSelected: (_) => setState(
                          () => _filter = _filter == kind ? null : kind,
                        ),
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
            : RefreshIndicator(onRefresh: _load, child: _buildBody(theme)),
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
                  _filter == null
                      ? '该目录为空'
                      : '没有${MediaKind.label(_filter!)}文件',
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
    final metrics = _gridMetricsFor(
      MediaQuery.sizeOf(context).width,
      MediaQuery.textScalerOf(context),
    );
    return GridView.builder(
      controller: _gridScroll,
      padding: EdgeInsets.all(metrics.margin),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: metrics.columns,
        mainAxisSpacing: metrics.gutter,
        crossAxisSpacing: metrics.gutter,
        // 固定格高而不是固定宽高比：格宽由可用宽度整除得出，行内不残留空隙；
        // 格高固定后，说明文字的底边也就逐行对齐了。
        mainAxisExtent: metrics.tileHeight,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final obj = items[i];
        final childPath = _childPath(obj);
        return _GridCard(
          obj: obj,
          childPath: childPath,
          tileWidth: metrics.tileWidth,
          onTap: () => obj.isDir ? _enter(obj.name) : _open(obj, childPath),
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
        final childPath = _childPath(obj);
        final store = AppStore.instance;
        final marks = store.marksOf(childPath);
        final record = store.recordFor(childPath);

        return ListTile(
          leading: _leading(theme, obj, childPath),
          title: Text(obj.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('「${obj.name}」不是可播放的媒体文件')));
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
        child: Icon(_dirIcon(obj), color: theme.colorScheme.onPrimaryContainer),
      );
    }
    final cover = AppStore.instance.api.coverUrl(obj.type, childPath);
    // 与网格同一份规则；目录在上面已提前返回，图标保住了
    // 「挂载点 / 目录」的层级线索。加载中与失败都回退到类型图标。
    if (cover != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: cover,
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
    child: Icon(switch (obj.type) {
      MediaKind.video => Icons.movie_outlined,
      MediaKind.audio => Icons.music_note_outlined,
      MediaKind.image => Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    }, color: theme.colorScheme.onSurfaceVariant),
  );

  Widget _subtitle(ThemeData theme, MediaObj obj, PlayRecord? record) => Text(
    _metaText(obj, record),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.bodySmall,
  );
}

/// 条目的说明行文案：`类型 · 体积 · 观看状态`。
///
/// 网格与列表共用同一份文案，两种视图的信息层级才不会各说各话。
String _metaText(MediaObj obj, PlayRecord? record) {
  final parts = <String>[MediaKind.label(obj.type)];
  if (!obj.isDir && obj.size > 0) parts.add(formatSize(obj.size));
  if (record != null) {
    if (record.durationMs > 0) {
      parts.add(
        record.isFinished ? '已看完' : '看到 ${formatDuration(record.positionMs)}',
      );
    } else if (record.kind == MediaKind.image) {
      parts.add('看过 ${formatRelative(record.updatedAt)}');
    }
  }
  return parts.join(' · ');
}

/// 目录条目的图标：挂载点（存储）与普通目录区分。
IconData _dirIcon(MediaObj obj) => obj.isMount ? Icons.storage : Icons.folder;

/// 网格排版：列数、外边距、间距与格宽 / 格高。只由可用宽度与字体缩放决定，
/// 用来在排版变化时把滚动位置从「像素」换算成「第几行」。
typedef _GridMetrics = ({
  int columns,
  double margin,
  double gutter,
  double tileWidth,
  double tileHeight,
});

/// 网格说明区的排版常量。
///
/// [_gridFooterHeight] 要靠它们反推格子总高，所以与下面卡片里的 [Text] 样式
/// 共用同一份数值，避免「算出来的高度」和「实际渲染的高度」对不上。
const double _gridTitleSize = 13.5;
const double _gridTitleHeight = 1.32;
const double _gridMetaSize = 11.5;
const double _gridMetaHeight = 1.25;
const double _gridTitleGap = 5;

/// 说明区高度：上下内边距 + 两行标题 + 行距 + 一行说明。
///
/// 跟随系统字体缩放，放大后也不会把文字裁掉。
double _gridFooterHeight(TextScaler textScaler) =>
    8 +
    10 +
    _gridTitleGap +
    textScaler.scale(_gridTitleSize) * _gridTitleHeight * 2 +
    textScaler.scale(_gridMetaSize) * _gridMetaHeight;

/// 网格卡片。
///
/// 自上而下是「预览区 + 说明区」：预览区用 [Expanded] 吃掉格子的剩余高度，
/// 说明区高度固定，于是同一行里标题占 1 行还是 2 行，说明文字的底边始终对齐。
/// 观看进度做成预览区底部的一条细进度条，不占说明区高度。
class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.obj,
    required this.childPath,
    required this.tileWidth,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaObj obj;
  final String childPath;

  /// 仅用于把封面图标按格子大小缩放，避免大屏上图标显得过小。
  final double tileWidth;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = AppStore.instance.api.coverUrl(obj.type, childPath);
    final marks = AppStore.instance.marksOf(childPath);
    final record = AppStore.instance.recordFor(childPath);
    final progress = record == null || record.durationMs <= 0
        ? 0.0
        : record.progress;

    return Card(
      margin: EdgeInsets.zero,
      // 卡片的圆角裁剪由主题里的 clipBehavior 负责，水波纹因此不会溢出圆角
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 视频/音频出服务端封面，图片出原图；目录与没有封面的类型用图标，
                  // 「挂载点 / 目录」的层级才一眼可辨（见 _dirIcon）。
                  if (cover != null)
                    CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      // 网格里同时有几十个圈在转非常吵，用中性色块代替
                      placeholder: (_, _) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                      errorWidget: (_, _, _) => _poster(scheme),
                    )
                  else
                    _poster(scheme),
                  if (marks.favorite || marks.later)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _MarksBadges(marks: marks),
                    ),
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: scheme.scrim.withValues(alpha: 0.32),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    obj.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: _gridTitleSize,
                      height: _gridTitleHeight,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  SizedBox(height: _gridTitleGap),
                  Text(
                    _metaText(obj, record),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: _gridMetaSize,
                      height: _gridMetaHeight,
                      color: scheme.onSurfaceVariant,
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

  /// 无缩略图时的封面：类型图标居中，目录用主色在层级上区分出来。
  Widget _poster(ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        obj.isDir
            ? _dirIcon(obj)
            : switch (obj.type) {
                MediaKind.video => Icons.movie_outlined,
                MediaKind.audio => Icons.music_note_outlined,
                MediaKind.image => Icons.image_outlined,
                _ => Icons.insert_drive_file_outlined,
              },
        size: (tileWidth * 0.28).clamp(28.0, 56.0),
        color: obj.isDir ? scheme.primary : scheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 预览区右上角的「收藏 / 稍后再看」角标。
///
/// 与列表视图用的是同一组语义色，只是列表放在标题行尾、网格压在缩略图上。
class _MarksBadges extends StatelessWidget {
  const _MarksBadges({required this.marks});

  final ({bool favorite, bool later}) marks;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (marks.favorite) const _MarkBadge(icon: Icons.favorite),
      if (marks.later) ...[
        const SizedBox(width: 4),
        const _MarkBadge(icon: Icons.watch_later),
      ],
    ],
  );
}

/// 单个角标：半透明深色底 + 白色图标，明暗配色下都看得清。
class _MarkBadge extends StatelessWidget {
  const _MarkBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 13, color: Colors.white),
    ),
  );
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
