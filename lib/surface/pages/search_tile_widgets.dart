// L7 surface/pages · 搜索页叶子组件（结果行/空态/错误重试）。
// 从 search_page.dart 拆出（format 后超 500 行门禁）。
import 'package:flutter/material.dart';

import '../../bridges/bridge_core.dart' show SongBrief;
import '../design/tokens.dart';

class SearchSongTile extends StatelessWidget {
  const SearchSongTile({
    required this.song,
    required this.onTap,
    required this.onAlbum,
  });
  final SongBrief song;
  final VoidCallback onTap;
  final VoidCallback onAlbum;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Sp.pagePad),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(Sp.rM),
        child: SizedBox(
          width: Sp.tileCover,
          height: Sp.tileCover,
          child: song.cover.isEmpty
              ? Container(color: Sp.cardHigh)
              : Image.network(
                  song.cover,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                      Container(color: Sp.cardHigh),
                ),
        ),
      ),
      title: Text(
        song.name.isEmpty ? '未知歌曲' : song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: Sp.fItem,
          color: Sp.text,
          fontWeight: song.isVip ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        song.singer.isEmpty ? '未知歌手' : song.singer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: Sp.fSub, color: Sp.textSub),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (song.albumId.isNotEmpty)
            IconButton(
              tooltip: '专辑',
              iconSize: 18,
              color: Sp.textFaint,
              onPressed: onAlbum,
              icon: const Icon(Icons.album_outlined),
            ),
          Text(
            song.durationSec > 0 ? '${song.durationSec}s' : '',
            style: const TextStyle(fontSize: Sp.fTiny, color: Sp.textFaint),
          ),
        ],
      ),
    );
  }
}

/// 空态。
class SearchEmptyBox extends StatelessWidget {
  const SearchEmptyBox(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Sp.pagePad,
      vertical: Sp.gapXL,
    ),
    child: Text(
      message,
      style: const TextStyle(fontSize: Sp.fSub, color: Sp.textFaint),
    ),
  );
}

/// 错误 + 重试。
class SearchErrorRetry extends StatelessWidget {
  const SearchErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Sp.pagePad,
      vertical: Sp.gapXL,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: Sp.fSub, color: Sp.red),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text(
            '重试',
            style: TextStyle(fontSize: Sp.fSub, color: Sp.green),
          ),
        ),
      ],
    ),
  );
}
