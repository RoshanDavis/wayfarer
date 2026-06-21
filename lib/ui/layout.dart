/// Cross-screen responsive layout: the scene and surfaces fill the whole window
/// while the readable UI stays a comfortable, centred size.
///
/// The phone UI is designed at a fixed width. On larger windows the *scrollable
/// surface* (and the scene, backgrounds and window chrome) fill the window, but
/// each readable content block — the timer, the journey text, a control — is
/// laid out at the design width, scaled up only modestly (capped) and centred
/// via [ContentBox]. So the background scales to the window, the scrollbar and
/// settings gear sit at the window edge/corner, and the content reads like a
/// phone app held in the middle of a wide scene rather than blown up to fill it.
library;

import 'package:flutter/widgets.dart';

/// The width the phone UI is designed at. Content blocks lay out at this width
/// and are scaled — never reflowed — for larger windows.
const double kContentDesignWidth = 480;

/// How far a content block may scale up before it locks. Past this the window
/// keeps growing but the content doesn't, so the scene fills the margins.
const double kMaxContentScale = 1.2;

/// The factor a content block is scaled by for a given window: 1 on phones (at
/// or below the design width), rising with width up to [kMaxContentScale].
double contentScaleFor(Size window) {
  if (window.width <= kContentDesignWidth) return 1;
  return (window.width / kContentDesignWidth).clamp(1.0, kMaxContentScale);
}

/// Lays [child] out at [kContentDesignWidth], scales it up by [contentScaleFor]
/// (capped) and centres it horizontally, taking only the scaled height. Wrap a
/// single readable content block in this — the scrollable, its scrollbar, the
/// scene and the surfaces around it stay full-window, so the background scales
/// to the window while the content stays a comfortable, centred size. Phones
/// (≤ the design width) pass through untouched.
class ContentBox extends StatelessWidget {
  final Widget child;
  const ContentBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final win = MediaQuery.sizeOf(context);
    if (win.width <= kContentDesignWidth) return child;
    final scale = contentScaleFor(win);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: kContentDesignWidth * scale,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          child: SizedBox(width: kContentDesignWidth, child: child),
        ),
      ),
    );
  }
}
