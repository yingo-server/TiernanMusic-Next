// L4 core/net/endpoints · 音质档位纯数据（功能对齐批3-C · GAP #30）
// 依据 docs/PARITY_NOTES.md §2：VIP 9 档（128/320/flac/high/super/
// viper_atmos/viper_tape/viper_clear/multitrack）+ 魔法 6 档
// （magic_piano/acappella/dj/surnay/subwoofer/ancient）三态全通，合计 15 档。
// v6/priv_url 的 qualities[] 用同串；魔法档在 /v5/url 以 magic_<q>=1 传递
// （见 play_endpoints.dart getPlayUrlV5）。纯数据：零 import、零 IO、零 UI。
// ⚠️ 协议档位 `super` 是 Dart 保留字，枚举成员名写 `qSuper`；协议值仍为 'super'。

/// 15 档：普通 5 / 蝰蛇 3 / 多轨 1 / 魔法 6（顺序即 UI 分组顺序）。
enum AudioQuality {
  q128, q320, flac, high, qSuper,
  viperAtmos, viperTape, viperClear, multitrack,
  magicPiano, magicAcappella, magicDj, magicSurnay, magicSubwoofer,
  magicAncient,
}

const String _magicPrefix = 'magic_';

/// /v5/url 协议档位值：魔法 6 档带 magic_ 前缀，其余为原生 quality 串。
/// Dart 3 穷尽 switch 表达式（新增枚举值时编译期报错，不漏档）。
String qualityParam(AudioQuality q) => switch (q) {
      AudioQuality.q128 => '128',
      AudioQuality.q320 => '320',
      AudioQuality.flac => 'flac',
      AudioQuality.high => 'high',
      AudioQuality.qSuper => 'super',
      AudioQuality.viperAtmos => 'viper_atmos',
      AudioQuality.viperTape => 'viper_tape',
      AudioQuality.viperClear => 'viper_clear',
      AudioQuality.multitrack => 'multitrack',
      AudioQuality.magicPiano => 'magic_piano',
      AudioQuality.magicAcappella => 'magic_acappella',
      AudioQuality.magicDj => 'magic_dj',
      AudioQuality.magicSurnay => 'magic_surnay',
      AudioQuality.magicSubwoofer => 'magic_subwoofer',
      AudioQuality.magicAncient => 'magic_ancient',
    };

/// 直接喂给 getPlayUrlV5 / PlaybackService.resolvePlaySource 的 quality 值：
/// 魔法档去掉 magic_ 前缀（play_endpoints.dart 会补 magic_<q>=1 且 quality=128）。
String toPlayUrlQuality(AudioQuality q) {
  final v = qualityParam(q);
  return v.startsWith(_magicPrefix) ? v.substring(_magicPrefix.length) : v;
}

/// VIP 9 档（顺序契约：普通 5 → 蝰蛇 3 → 多轨 1，供 UI 分组切片）。
List<AudioQuality> vipQualities() => const <AudioQuality>[
      AudioQuality.q128, AudioQuality.q320, AudioQuality.flac,
      AudioQuality.high, AudioQuality.qSuper, AudioQuality.viperAtmos,
      AudioQuality.viperTape, AudioQuality.viperClear, AudioQuality.multitrack,
    ];

/// 魔法 6 档（匿名 / 非 VIP / VIP 三态全通）。
List<AudioQuality> magicQualities() => const <AudioQuality>[
      AudioQuality.magicPiano, AudioQuality.magicAcappella,
      AudioQuality.magicDj, AudioQuality.magicSurnay,
      AudioQuality.magicSubwoofer, AudioQuality.magicAncient,
    ];

/// 偏好串 → 档位；兼容协议值 / 枚举名 / 魔法裸名，未知退回 q128。
AudioQuality fromPref(String pref) {
  final s = pref.trim().toLowerCase();
  switch (s) {
    case '128': case 'q128': return AudioQuality.q128;
    case '320': case 'q320': return AudioQuality.q320;
    case 'flac': return AudioQuality.flac;
    case 'high': return AudioQuality.high;
    case 'super': case 'qsuper': return AudioQuality.qSuper;
    case 'viper_atmos': case 'viperatmos': return AudioQuality.viperAtmos;
    case 'viper_tape': case 'vipertape': return AudioQuality.viperTape;
    case 'viper_clear': case 'viperclear': return AudioQuality.viperClear;
    case 'multitrack': return AudioQuality.multitrack;
    case 'magic_piano': case 'piano': case 'magicpiano':
      return AudioQuality.magicPiano;
    case 'magic_acappella': case 'acappella': case 'magicacappella':
      return AudioQuality.magicAcappella;
    case 'magic_dj': case 'dj': case 'magicdj':
      return AudioQuality.magicDj;
    case 'magic_surnay': case 'surnay': case 'magicsurnay':
      return AudioQuality.magicSurnay;
    case 'magic_subwoofer': case 'subwoofer': case 'magicsubwoofer':
      return AudioQuality.magicSubwoofer;
    case 'magic_ancient': case 'ancient': case 'magicancient':
      return AudioQuality.magicAncient;
  }
  return AudioQuality.q128;
}

/// 档位 → 持久化偏好串（与 qualityParam 同源，稳定可迁移）。
String toPref(AudioQuality q) => qualityParam(q);
