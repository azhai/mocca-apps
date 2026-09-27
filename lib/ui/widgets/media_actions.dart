import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../data/store.dart';
import '../media_launcher.dart';

/// 从一个已保存的条目重建 [MediaObj]，用于在收藏 / 记录页直接播放。
///
/// 保存的条目只含展示所需字段（名称、类型、缩略图），
/// 播放时真正需要的 `raw_url` 会在打开时重新向后端索取，
/// 因此这里缺失的 size / 时间等信息不影响播放。
MediaObj objFromSaved({
  required String name,
  required int kind,
  String thumb = '',
}) => MediaObj(name: name, size: 0, isDir: false, type: kind, thumb: thumb);

/// 「收藏 / 稍后再看 / 从头播放」等操作的列表项集合。
///
/// 供浏览页的长按菜单与媒体库页的条目菜单复用。
class MediaActions extends StatelessWidget {
  const MediaActions({
    super.key,
    required this.path,
    required this.obj,
    this.showOpen = false,
  });

  final String path;
  final MediaObj obj;

  /// 是否显示「播放」项（媒体库页里通常直接点条目即播放，无需重复）。
  final bool showOpen;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final marks = store.marksOf(path);
    final record = store.recordFor(path);

    Future<void> toggle(SavedGroup group, BuildContext ctx) async {
      final nowSaved = await store.toggle(
        group,
        SavedItem(path: path, name: obj.name, kind: obj.type, thumb: obj.thumb),
      );
      if (!ctx.mounted) return;
      Navigator.of(ctx).maybePop();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(nowSaved ? '已加入${group.label}' : '已从${group.label}移除'),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOpen)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('播放'),
            onTap: () {
              Navigator.of(context).maybePop();
              openMedia(context, obj: obj, path: path);
            },
          ),
        ListTile(
          leading: Icon(
            marks.favorite ? Icons.favorite : Icons.favorite_border,
          ),
          title: Text(marks.favorite ? '取消收藏' : '收藏'),
          onTap: () => toggle(SavedGroup.favorite, context),
        ),
        ListTile(
          leading: Icon(
            marks.later ? Icons.watch_later : Icons.watch_later_outlined,
          ),
          title: Text(marks.later ? '移出稍后再看' : '稍后再看'),
          onTap: () => toggle(SavedGroup.watchLater, context),
        ),
        if (record != null && record.positionMs > 0)
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('清除播放进度'),
            subtitle: Text('当前停留在 ${formatDuration(record.positionMs)}'),
            onTap: () async {
              await store.resetProgress(path);
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已清除播放进度，下次将从头播放')));
            },
          ),
      ],
    );
  }
}
