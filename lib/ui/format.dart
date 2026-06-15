/// Number and time formatting — real units, quiet presentation.
library;

String thousands(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    out.write(s[i]);
    final rem = s.length - i - 1;
    if (rem > 0 && rem % 3 == 0) out.write(',');
  }
  return out.toString();
}

/// "0.4 km", "4.4 km", "338 km", "293,096 km".
String formatKm(double km, {bool withUnit = true}) {
  final number = km < 10 && km > -10
      ? km.toStringAsFixed(km == km.roundToDouble() && km >= 1 ? 0 : 1)
      : thousands(km.round());
  return withUnit ? '$number km' : number;
}

/// "1.0 km/h", "54 km/h", "703,432 km/h".
String formatPace(double kmh) {
  final number =
      kmh < 10 ? kmh.toStringAsFixed(1) : thousands(kmh.round());
  return '$number km/h';
}

/// "25:00" countdown numeral.
String formatCountdown(int ms) {
  final totalSeconds = (ms / 1000).ceil();
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// "26 min" under an hour, then "1.5 h", "46 h", "1,204 h".
String formatFocusTime(int seconds) {
  if (seconds < 3600) return '${seconds ~/ 60} min';
  final hours = seconds / 3600;
  if (hours < 10) {
    final tenths = (hours * 10).round() / 10;
    return tenths == tenths.roundToDouble()
        ? '${tenths.round()} h'
        : '${tenths.toStringAsFixed(1)} h';
  }
  return '${thousands(hours.round())} h';
}
