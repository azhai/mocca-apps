import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../data/store.dart';

/// JPG / PNG 等图片查看页。
///
/// - 左右滑动切换同目录图片（地址按需懒加载并缓存）
/// - 双指捏合缩放；双击在「适应屏幕」与「2 倍」之间切换
///
/// 图片没有播放进度，但仍会写入观看记录（仅记录观看时间与来源），
/// 以便在「媒体库 → 观看记录」里回溯，并支持收藏 / 稍后再看。
class ImagePage extends StatefulWidget {
  const ImagePage({
    super.key,
    required this.siblings,
    required this.index,
    required this.initialUrl,
    this.initialHeaders = const {},
    this.password,
  });

  final List<({MediaObj obj, String path})> siblings;
  final int index;
  final String initialUrl;
  final Map<String, String> initialHeaders;
  final String? password;

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  late final PageController _pageController = PageController(
    initialPage: widget.index,
  );
  late int _index = widget.index;

  /// 已解析出的绝对地址：索引 → URL，避免来回切页时重复请求。
  late final Map<int, String> _urls = {};

  @override
  void initState() {
    super.initState();
    _urls[widget.index] = widget.initialUrl;
    _recordView(widget.index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ({MediaObj obj, String path}) get _current => widget.siblings[_index];

  /// 记录一次查看：图片无进度，只更新时间与缩略图。
  void _recordView(int index) {
    final item = widget.siblings[index];
    final url = _urls[index] ?? '';
    AppStore.instance.upsertRecord(
      path: item.path,
      name: item.obj.name,
      kind: MediaKind.image,
      positionMs: 0,
      durationMs: 0,
      thumb: url.isNotEmpty ? url : item.obj.thumb,
    );
  }

  /// 懒加载指定索引的图片地址。
  Future<String> _resolve(int index) async {
    final cached = _urls[index];
    if (cached != null && cached.isNotEmpty) return cached;
    final item = widget.siblings[index];
    final detail = await AppStore.instance.api.get(
      item.path,
      password: widget.password,
    );
    final url = AppStore.instance.api.resolveUrl(detail.rawUrl);
    _urls[index] = url;
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final cur = _current;
    final marks = store.marksOf(cur.path);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          cur.obj.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (widget.siblings.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '${_index + 1} / ${widget.siblings.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          IconButton(
            tooltip: marks.favorite ? '取消收藏' : '收藏',
            icon: Icon(marks.favorite ? Icons.favorite : Icons.favorite_border),
            onPressed: () => store.toggle(
              SavedGroup.favorite,
              SavedItem(
                path: cur.path,
                name: cur.obj.name,
                kind: MediaKind.image,
                thumb: _urls[_index] ?? '',
              ),
            ),
          ),
          IconButton(
            tooltip: marks.later ? '移出稍后再看' : '稍后再看',
            icon: Icon(
              marks.later ? Icons.watch_later : Icons.watch_later_outlined,
            ),
            onPressed: () => store.toggle(
              SavedGroup.watchLater,
              SavedItem(
                path: cur.path,
                name: cur.obj.name,
                kind: MediaKind.image,
                thumb: _urls[_index] ?? '',
              ),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.siblings.length,
        onPageChanged: (i) {
          setState(() => _index = i);
          _recordView(i);
        },
        itemBuilder: (context, i) => _ZoomableImage(
          key: ValueKey(widget.siblings[i].path),
          resolve: () => _resolve(i),
        ),
      ),
    );
  }
}

/// 单张可缩放图片：双指捏合 + 双击切换缩放级别。
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({super.key, required this.resolve});

  final Future<String> Function() resolve;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transform = TransformationController();
  late final Future<String> _url = widget.resolve();
  bool _zoomed = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 双击缩放：在「适应屏幕」与「2 倍」之间切换。
  ///
  /// 先平移再缩放，使放大锚点落在画面中心；否则会锚定在左上角，
  /// 观感上像是图片被推到了右下。
  void _onDoubleTap(Size viewport) {
    const scale = 2.0;
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      final dx = -viewport.width * (scale - 1) / 2;
      final dy = -viewport.height * (scale - 1) / 2;
      _transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    setState(() => _zoomed = !_zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final url = snapshot.data ?? '';
        if (snapshot.hasError || url.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.hasError
                        ? '无法加载图片：${snapshot.error}'
                        : '服务器未返回图片地址',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }
        return GestureDetector(
          onDoubleTap: () => _onDoubleTap(MediaQuery.sizeOf(context)),
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 6,
            onInteractionEnd: (_) {
              final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
              if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
