/// The floating control must never capture scrolling. It sits in a `Positioned`
/// overlay over the scroll surface (see lib/ui/screens/home.dart), so its buttons
/// are `HitTestBehavior.translucent` and its cushion is wrapped in `IgnorePointer`.
/// Without that, the mouse wheel — a pointer signal the buttons/cushion would
/// otherwise swallow — is dead across the whole control row (the recurring bug
/// this guards). These tests drive the real [BigControl] over a scroll view.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/app/theme.dart';
import 'package:wayfarer/core/maps.dart';
import 'package:wayfarer/ui/widgets/controls.dart';

const _cushionKey = Key('cushion');

/// A ListView behind a faithful copy of the home overlay: a full-width cushion
/// that ignores pointers, and a centred translucent [BigControl].
Widget _harness(ScrollController controller, {VoidCallback? onTap}) {
  final palette = buildPalette(map: kMaps.first, brightness: Brightness.light);
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: PaletteScope(
        palette: palette,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 40, child: Text('row $i')),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 250,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      key: _cushionKey,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x33000000)),
                      ),
                    ),
                  ),
                  Center(child: BigControl(label: 'Begin', onTap: onTap ?? () {})),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _wheelAt(WidgetTester tester, Offset position) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(position));
  await tester.sendEventToBinding(pointer.scroll(const Offset(0, 160)));
  await tester.pump();
}

void main() {
  testWidgets('wheel over the translucent button scrolls the surface behind',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    expect(controller.offset, 0);
    await _wheelAt(tester, tester.getCenter(find.byType(BigControl)));
    expect(controller.offset, greaterThan(0),
        reason: 'the button must not swallow the wheel');
  });

  testWidgets('wheel over the full-width cushion (a margin) scrolls',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    final marginPoint =
        tester.getTopLeft(find.byKey(_cushionKey)) + const Offset(12, 12);
    await _wheelAt(tester, marginPoint);
    expect(controller.offset, greaterThan(0),
        reason: 'the cushion must not swallow the wheel in the margins');
  });

  testWidgets('a stationary tap still fires the control and does not scroll',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var tapped = false;
    await tester.pumpWidget(_harness(controller, onTap: () => tapped = true));

    await tester.tap(find.byType(BigControl));
    await tester.pump();
    expect(tapped, isTrue);
    expect(controller.offset, 0);
  });
}
