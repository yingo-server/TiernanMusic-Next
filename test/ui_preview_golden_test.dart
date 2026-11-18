// UI golden preview: render the real widget tree (dark theme + bottom nav)
// to a PNG using Flutter's own engine, so the rendered result can be inspected
// in CI without a device. English labels avoid CJK font dependencies.
//
// NOTE: this test does NOT compare against a committed baseline. It simply
// forces Flutter to render the tree into a PNG via matchesGoldenFile with a
// deliberately missing baseline: golden test writes the actual image to disk
// and fails the comparison, but the PNG artifact is still produced for review.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tiernan_music_next/surface/design/tokens.dart';

void main() {
  // Only run under the dedicated golden-preview CI step (env flag), so the
  // regular `flutter test` gate is unaffected by the intentionally missing
  // golden baseline.
  if (!const bool.fromEnvironment('GOLDEN_PREVIEW')) {
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render home shell preview (dark)', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final scheme = Sp.theme(dark: true).colorScheme;
    await tester.pumpWidget(MaterialApp(
      theme: Sp.theme(dark: true),
      home: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(title: const Text('Home'), backgroundColor: scheme.surface),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text('Daily Mix',
                style: TextStyle(color: scheme.onSurface, fontSize: 16)),
            const SizedBox(height: 8),
            Text('No daily mix yet (available after sign in)',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 24),
            Text('Recommended Playlists',
                style: TextStyle(color: scheme.onSurface, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: Row(children: <Widget>[
                _Thumb(color: scheme.surfaceContainer),
                const SizedBox(width: 12),
                _Thumb(color: scheme.surfaceContainer),
                const SizedBox(width: 12),
                _Thumb(color: scheme.surfaceContainer),
              ]),
            ),
            const SizedBox(height: 24),
            Text('Charts',
                style: TextStyle(color: scheme.onSurface, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  _Chart(color: scheme.primary),
                  const SizedBox(width: 12),
                  _Chart(color: scheme.primary),
                  const SizedBox(width: 12),
                  _Chart(color: scheme.primary),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          height: 80,
          backgroundColor: scheme.surfaceContainer,
          indicatorColor: scheme.primaryContainer,
          selectedIndex: 0,
          destinations: const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlist'),
            NavigationDestination(
                icon: Icon(Icons.library_music_outlined), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // matchesGoldenFile writes the rendered PNG to disk. With no committed
    // baseline CI still produces the image under build/golden/ for inspection.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/ui_preview_dark.png'),
    );
  });
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
}

class _Chart extends StatelessWidget {
  const _Chart({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('TOP500', style: TextStyle(color: Colors.black, fontSize: 14)),
            Text('2026-11-18',
                style: TextStyle(color: Color(0xDD000000), fontSize: 10)),
          ],
        ),
      );
}
