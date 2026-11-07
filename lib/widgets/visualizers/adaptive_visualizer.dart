import 'package:flutter/material.dart';
import '../../providers/settings_provider.dart';
import 'bars_visualizer.dart';
import 'circular_wave_visualizer.dart';
import 'particle_visualizer.dart';

class AdaptiveVisualizer extends StatelessWidget {
  final List<double> spectrum;
  final Color color;
  final VisualizerMode mode;

  const AdaptiveVisualizer({
    super.key,
    required this.spectrum,
    required this.color,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) => switch (mode) {
        VisualizerMode.bars => BarsVisualizer(spectrum: spectrum, color: color),
        VisualizerMode.circularWave =>
          CircularWaveVisualizer(spectrum: spectrum, color: color),
        VisualizerMode.particleSystem =>
          ParticleVisualizer(spectrum: spectrum, color: color),
        VisualizerMode.adaptive => _adaptive(),
      };

  /// Adaptive: circular saat musik "ramai", bars saat tenang (lebih hemat).
  Widget _adaptive() {
    final avg = spectrum.isEmpty
        ? 0.0
        : spectrum.reduce((a, b) => a + b) / spectrum.length;
    return avg > 0.25
        ? CircularWaveVisualizer(spectrum: spectrum, color: color)
        : BarsVisualizer(spectrum: spectrum, color: color, height: 28);
  }
}