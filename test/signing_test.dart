// 签名引擎测试锚点：MD5 标准向量 + 签名算法行为锁定
import 'package:flutter_test/flutter_test.dart';
import 'package:tiernan_music_next/core/net/signing.dart';

void main() {
  test('md5 standard vectors', () {
    expect(md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
    expect(md5Hex('The quick brown fox jumps over the lazy dog'),
        '9e107d9d372bb6826bd81d3542a419d6');
    expect(md5Hex('a' * 1000), 'cabe45dcc9ae5b66ba86600cca6b8ba8');
  });

  test('android signature: sorted k=v no separator, md5(salt+s+salt)', () {
    // 空参数 → md5(salt + '' + '' + salt)
    final empty = md5Hex(KugouSign.androidSalt +
        '' +
        KugouSign.androidSalt);
    expect(KugouSign.android({}), empty);
    // 参数排序与拼接：手算参照
    final sig = KugouSign.android({'b': '2', 'a': '1'});
    final manual = md5Hex(KugouSign.androidSalt + 'a=1b=2' + KugouSign.androidSalt);
    expect(sig, manual);
  });

  test('android signature with body appends body before trailing salt', () {
    final sig = KugouSign.android({'k': 'v'}, body: '{"x":1}');
    final manual = md5Hex(
        KugouSign.androidSalt + 'k=v' + '{"x":1}' + KugouSign.androidSalt);
    expect(sig, manual);
  });

  test('web signature sorts k=v strings', () {
    final sig = KugouSign.web({'b': '2', 'a': '1'});
    // parts sorted: 'a=1','b=2' → joined 'a=1b=2'
    final manual = md5Hex(KugouSign.webSalt + 'a=1b=2' + KugouSign.webSalt);
    expect(sig, manual);
  });

  test('register signature sorts values only', () {
    final sig = KugouSign.register({'x': '9', 'y': '3'});
    final manual = md5Hex('1014' + '39' + '1014');
    expect(sig, manual);
  });

  test('playKey formula', () {
    final k = KugouSign.playKey('abc', 'mid1', 'u1');
    expect(k, md5Hex('abc57ae12eb6890223e355ccfcb74edf70d1005mid1u1'));
    // 空 userid → 0
    expect(KugouSign.playKey('abc', 'mid1', ''),
        md5Hex('abc57ae12eb6890223e355ccfcb74edf70d1005mid10'));
  });

  test('signParamsKey formula', () {
    expect(KugouSign.signParamsKey('1700000000000'),
        md5Hex('1005OIlwieks28dk2k092lksi2UIkp204891700000000000'));
  });
}
