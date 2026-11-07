import 'package:flutter_test/flutter_test.dart';

import 'package:dynamic_island/theme/island_theme.dart';
import 'package:dynamic_island/providers/settings_provider.dart';

void main() {
  test('IslandTheme tersedia untuk semua VisualStyle', () {
    for (final v in VisualStyle.values) {
      final t = IslandTheme.from(v);
      expect(t.expandedWidth, greaterThan(t.pillWidth));
      expect(t.blurSigma, lessThanOrEqualTo(8));
    }
  });
  customSizeTest();
}

void customSizeTest() {
  test('copyWith mengganti ukuran dan sudut', () {
    final t = IslandTheme.from(VisualStyle.ios17).copyWith(
      pillWidth: 200,
      expandedHeight: 500,
      borderRadius: 10,
      expandedRadius: 30,
    );
    expect(t.pillWidth, 200);
    expect(t.expandedHeight, 500);
    expect(t.borderRadius, 10);
    expect(t.expandedRadius, 30);
  });
}
