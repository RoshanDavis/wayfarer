/// Builds the Windows app icon ([windows/runner/resources/app_icon.ico]) from
/// the shared source mark ([assets/icon.png]).
///
/// flutter_launcher_icons only emits a single 256×256 image for Windows, which
/// the shell downscales poorly at small sizes (taskbar, Explorer lists,
/// alt-tab). This packs a proper multi-resolution .ico so every size the shell
/// asks for is crisp. The web favicon/PWA icons are still handled by
/// flutter_launcher_icons; Android keeps its hand-crafted adaptive icon.
///
/// Run from the project root after changing the source mark:
///
///   dart run tool/gen_windows_icon.dart
library;

import 'dart:io';

import 'package:image/image.dart' as img;

/// The sizes Windows shells request. 256 carries the high-DPI/large-tile icon;
/// the smaller frames keep taskbar and list views sharp.
const _sizes = [16, 24, 32, 48, 64, 128, 256];

void main() {
  final src = img.decodePng(File('assets/icon.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode assets/icon.png');
    exit(1);
  }
  // `average` (area) sampling gives the cleanest large reductions (512 → 16).
  final frames = [
    for (final s in _sizes)
      img.copyResize(
        src,
        width: s,
        height: s,
        interpolation: img.Interpolation.average,
      ),
  ];
  final bytes = img.IcoEncoder().encodeImages(frames);
  final out = File('windows/runner/resources/app_icon.ico');
  out.writeAsBytesSync(bytes);
  stdout.writeln('Wrote ${bytes.length} bytes to ${out.path} '
      '(sizes: ${_sizes.join(", ")})');
}
