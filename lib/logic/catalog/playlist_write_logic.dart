// L5 logic/catalog · 歌单写操作门面（功能对齐批5-B）
// 注入 KugouClient + PlaylistDao + onChanged 失效回调。
// 写语义（PARITY_NOTES.md 质量原则）：
// - 写操作禁止回退/重试（防重复提交）——一次提交，失败即返回 false/null。
// - 幂等：重复 delete 不报错（第二次返回 true 并 Log.d 留痕）。
// - 写成功后失效本地镜像缓存（触发注入的 onChanged 回调）+ Log 留痕。
// 每方法 try/catch + Log('logic.playlist.write')。
import '../../bridges/bridge_kernel.dart' show Log;
import '../../bridges/bridge_core.dart' show KugouClient, PlaylistDao, PlaylistBrief, createPlaylist, deletePlaylist, removeSongsFromPlaylist, getPlaylistTags, getUserPlaylists;

const String _tag = 'logic.playlist.write';

class PlaylistWriteLogic {
  PlaylistWriteLogic({
    required KugouClient client,
    required PlaylistDao playlistDao,
    void Function()? onChanged,
  })  : _client = client,
        _dao = playlistDao,
        _onChanged = onChanged {
    Log.d(_tag, 'init');
  }

  final KugouClient _client;
  final PlaylistDao _dao;
  final void Function()? _onChanged;

  /// 写成功后失效本地镜像缓存（清镜像 + 通知回调）。
  Future<void> _invalidate(String listid) async {
    try {
      await _dao.delete(listid);
    } catch (e, st) {
      // 镜像清理失败不阻断主流程（在线态为准），留痕即可。
      Log.e(_tag, 'invalidate mirror $listid failed', e, st);
    }
    try {
      _onChanged?.call();
    } catch (e, st) {
      Log.e(_tag, 'onChanged callback failed', e, st);
    }
    Log.d(_tag, 'invalidate $listid done');
  }

  /// 建歌单。成功返回新歌单 listid；失败/未登录返回 null。
  /// 写操作：一次提交，不重试。
  Future<String?> create(String name) async {
    try {
      if (_client.session.userid.isEmpty) {
        Log.w(_tag, 'create: not logged in');
        return null;
      }
      final id = await createPlaylist(_client, name);
      if (id != null && id.isNotEmpty) {
        Log.d(_tag, 'create ok id=$id');
        await _invalidate(id);
      }
      return id;
    } catch (e, st) {
      Log.e(_tag, 'create failed name=$name', e, st);
      return null;
    }
  }

  /// 删歌单。幂等：本地镜像不存在视为已删（返回 true，Log.d）。
  /// 写操作：一次提交，不重试。
  Future<bool> delete(String listid) async {
    try {
      final id = listid.trim();
      if (id.isEmpty) {
        Log.w(_tag, 'delete: empty listid');
        return false;
      }
      if (_client.session.userid.isEmpty) {
        Log.w(_tag, 'delete: not logged in');
        return false;
      }
      final ok = await deletePlaylist(_client, id);
      if (ok) {
        Log.d(_tag, 'delete ok id=$id');
        await _invalidate(id);
      }
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'delete failed listid=$listid', e, st);
      return false;
    }
  }

  /// 歌单删歌。写操作：一次提交，不重试；成功后失效镜像。
  Future<bool> removeSongs(String listid, List<String> hashes) async {
    try {
      final id = listid.trim();
      if (id.isEmpty || hashes.isEmpty) {
        Log.w(_tag, 'removeSongs: empty listid or hashes');
        return false;
      }
      if (_client.session.userid.isEmpty) {
        Log.w(_tag, 'removeSongs: not logged in');
        return false;
      }
      final ok = await removeSongsFromPlaylist(_client, id, hashes);
      if (ok) {
        Log.d(_tag, 'removeSongs ok id=$id n=${hashes.length}');
        await _invalidate(id);
      }
      return ok;
    } catch (e, st) {
      Log.e(_tag, 'removeSongs failed listid=$listid', e, st);
      return false;
    }
  }

  /// 歌单分类 tags（读操作，无缓存失效）。
  Future<List<String>> tags() async {
    try {
      final t = await getPlaylistTags(_client);
      Log.d(_tag, 'tags got=${t.length}');
      return t;
    } catch (e, st) {
      Log.e(_tag, 'tags failed', e, st);
      return const <String>[];
    }
  }

  /// 用户歌单列表（读操作，无缓存失效）。
  Future<List<PlaylistBrief>> userPlaylists({int page = 1, int pageSize = 30}) async {
    try {
      if (_client.session.userid.isEmpty) {
        Log.w(_tag, 'userPlaylists: not logged in');
        return const <PlaylistBrief>[];
      }
      final list =
          await getUserPlaylists(_client, page: page, pageSize: pageSize);
      Log.d(_tag, 'userPlaylists page=$page got=${list.length}');
      return list;
    } catch (e, st) {
      Log.e(_tag, 'userPlaylists failed page=$page', e, st);
      return const <PlaylistBrief>[];
    }
  }
}
