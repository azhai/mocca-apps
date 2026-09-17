import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../data/store.dart';
import 'player/audio_page.dart';
import 'player/image_page.dart';
import 'player/video_page.dart';

/// 打开一个媒体对象。
///
/// 流程：向 `/api/fs/get` 取详情 → 补全为绝对播放地址 → 按类型推入对应播放器。
/// 之所以统一走这里，是因为只有 `/api/fs/get` 会返回带签名的 `raw_url`
/// （受保护路径不带签名会 401）。
///
/// [siblings] 是同一目录下的同类媒体，用于在播放器内实现上一个 / 下一个。
Future<void> openMedia(
  BuildContext context, {
  required MediaObj obj,
  required String path,
  List<({MediaObj obj, String path})> siblings = const [],
  int siblingIndex = 0,
  String? password,
}) async {
  final store = AppStore.instance;
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _LoadingDialog(),
  );

  try {
    final detail = await store.api.get(path, password: password);
    final url = store.api.resolveUrl(detail.rawUrl);
    if (url.isEmpty) throw ApiException(500, '服务器未返回可播放地址');

    var kind = detail.obj.type;
    if (!MediaKind.isPlayable(kind)) kind = guessKindFromName(obj.name);

    final title = obj.name;
    final thumb = detail.obj.thumb.isNotEmpty ? detail.obj.thumb : obj.thumb;
    final headers = detail.parsedHeaders();

    navigator.pop(); // 关闭加载提示

    final Widget page = switch (kind) {
      MediaKind.image => ImagePage(
        siblings: siblings.isEmpty
            ? [(obj: obj, path: path)]
            : siblings,
        index: siblings.isEmpty ? 0 : siblingIndex,
        initialUrl: url,
        initialHeaders: headers,
        password: password,
      ),
      MediaKind.audio => AudioPage(
        siblings: siblings.isEmpty
            ? [(obj: obj, path: path)]
            : siblings,
        index: siblings.isEmpty ? 0 : siblingIndex,
        initialUrl: url,
        initialHeaders: headers,
        password: password,
      ),
      _ => VideoPage(
        path: path,
        title: title,
        url: url,
        headers: headers,
        thumb: thumb,
        siblings: siblings,
        index: siblingIndex,
        password: password,
      ),
    };

    if (!context.mounted) return;
    await navigator.push(MaterialPageRoute(builder: (_) => page));
  } on ApiException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('打开失败：$e')));
  }
}

/// 从目录内容中筛出可播放项，供播放器做上一个 / 下一个。
List<({MediaObj obj, String path})> playableSiblings(
  List<MediaObj> items,
  String dirPath,
  int kind,
) {
  final base = dirPath == '/' ? '' : dirPath;
  return items
      .where((o) => !o.isDir && o.type == kind)
      .map((o) => (obj: o, path: '$base/${o.name}'))
      .toList(growable: false);
}

/// 在目录中定位某个对象的兄弟索引。
int indexOfSibling(
  List<({MediaObj obj, String path})> siblings,
  String path,
) {
  final i = siblings.indexWhere((e) => e.path == path);
  return i < 0 ? 0 : i;
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) => const PopScope(
    canPop: false,
    child: Center(child: CircularProgressIndicator()),
  );
}
