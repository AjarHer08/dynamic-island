import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeoPlace {
  final String name, region, country;
  final double lat, lon;
  const GeoPlace(this.name, this.region, this.country, this.lat, this.lon);

  String get display {
    final parts = <String>[name];
    if (region.isNotEmpty && region != name) parts.add(region);
    if (country.isNotEmpty) parts.add(country);
    return parts.join(', ');
  }
}

String weatherLabel(int? code, String lang) {
  final id = lang == 'id';
  if (code == null) return '--';
  if (code == 0) return id ? 'Cerah' : 'Clear';
  if (code == 1) return id ? 'Cerah berawan' : 'Mostly clear';
  if (code == 2) return id ? 'Berawan sebagian' : 'Partly cloudy';
  if (code == 3) return id ? 'Berawan' : 'Overcast';
  if (code == 45 || code == 48) return id ? 'Berkabut' : 'Fog';
  if (code >= 51 && code <= 57) return id ? 'Gerimis' : 'Drizzle';
  if (code >= 61 && code <= 67) return id ? 'Hujan' : 'Rain';
  if (code >= 71 && code <= 77) return id ? 'Salju' : 'Snow';
  if (code >= 80 && code <= 82) return id ? 'Hujan lokal' : 'Showers';
  if (code == 85 || code == 86) return id ? 'Hujan salju' : 'Snow showers';
  if (code == 95) return id ? 'Badai petir' : 'Thunderstorm';
  if (code == 96 || code == 99) return id ? 'Badai petir & es' : 'Thunderstorm, hail';
  return id ? 'Tidak diketahui' : 'Unknown';
}

IconData weatherIcon(int? code, bool isDay) {
  if (code == null) return Icons.cloud_queue;
  if (code == 0 || code == 1) return isDay ? Icons.wb_sunny : Icons.nightlight_round;
  if (code == 2) return isDay ? Icons.wb_cloudy : Icons.cloud;
  if (code == 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67) return Icons.grain;
  if (code >= 71 && code <= 77) return Icons.ac_unit;
  if (code >= 80 && code <= 86) return Icons.umbrella;
  return Icons.thunderstorm;
}

/// Cuaca dari Open-Meteo (gratis, tanpa API key).
/// Lokasi: deteksi otomatis lewat IP (akurasi tingkat kota) atau pilih kota
/// sendiri lewat pencarian (paling akurat). Pilihan disimpan permanen.
class WeatherProvider extends ChangeNotifier {
  static const _headers = {'User-Agent': 'DynamicIsland/1.0'};

  String _city = '';
  double? _lat, _lon;
  bool _auto = true;
  bool _inited = false;

  double? _tempC, _feels, _wind, _hi, _lo;
  int? _humidity, _code, _rain;
  bool _isDay = true;
  bool _loading = false;
  String? _error;
  DateTime? _updated;
  Timer? _timer;
  int _reqId = 0; // hanya permintaan terbaru yang boleh mengisi data
  bool _disposed = false;

  String get city => _city.isEmpty ? '...' : _city;
  bool get autoLocation => _auto;
  double? get tempC => _tempC;
  double? get feelsC => _feels;
  double? get windKmh => _wind;
  double? get highC => _hi;
  double? get lowC => _lo;
  int? get humidity => _humidity;
  int? get rainChance => _rain;
  int? get code => _code;
  bool get isDay => _isDay;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get updated => _updated;

  /// Titik masuk (dipanggil sekali saat start).
  Future<void> fetchWeather() async {
    if (_inited) return refresh();
    _inited = true;
    final p = await SharedPreferences.getInstance();
    _auto = p.getBool('wx_auto') ?? true;
    _city = p.getString('wx_city') ?? '';
    _lat = p.getDouble('wx_lat');
    _lon = p.getDouble('wx_lon');
    notifyListeners();
    if (_auto || _lat == null) {
      await detectLocation();
    } else {
      await refresh();
    }
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Future<void> _saveLocation() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('wx_auto', _auto);
    await p.setString('wx_city', _city);
    if (_lat != null) await p.setDouble('wx_lat', _lat!);
    if (_lon != null) await p.setDouble('wx_lon', _lon!);
  }

  Future<dynamic> _getJson(Uri uri) async {
    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// Deteksi lokasi dari IP publik.
  Future<void> detectLocation() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      GeoPlace? found;
      try {
        final j = await _getJson(Uri.https('ipwho.is', '/')) as Map;
        if (j['success'] == true && j['latitude'] is num) {
          found = GeoPlace(
              (j['city'] ?? '').toString(),
              (j['region'] ?? '').toString(),
              (j['country'] ?? '').toString(),
              (j['latitude'] as num).toDouble(),
              (j['longitude'] as num).toDouble());
        }
      } catch (_) {}
      if (found == null) {
        final j = await _getJson(Uri.https('ipapi.co', '/json/')) as Map;
        if (j['latitude'] is num) {
          found = GeoPlace(
              (j['city'] ?? '').toString(),
              (j['region'] ?? '').toString(),
              (j['country_name'] ?? '').toString(),
              (j['latitude'] as num).toDouble(),
              (j['longitude'] as num).toDouble());
        }
      }
      if (found == null) throw Exception('no location');
      _city = found.name.isNotEmpty ? found.name : found.display;
      _lat = found.lat;
      _lon = found.lon;
      _auto = true;
      await _saveLocation();
    } catch (_) {
      if (_lat == null) {
        _error = 'Location not detected - choose a city';
        _loading = false;
        notifyListeners();
        return;
      }
    }
    await refresh();
  }

  /// Cari kota (geocoding Open-Meteo).
  Future<List<GeoPlace>> searchCity(String query, String lang) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final j = await _getJson(Uri.https('geocoding-api.open-meteo.com',
        '/v1/search', {'name': q, 'count': '8', 'language': lang, 'format': 'json'}));
    final list = (j is Map ? j['results'] : null) as List? ?? const [];
    return list.map((e) {
      final m = e as Map;
      return GeoPlace(
        (m['name'] ?? '').toString(),
        (m['admin1'] ?? '').toString(),
        (m['country'] ?? '').toString(),
        (m['latitude'] as num).toDouble(),
        (m['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  Future<void> selectPlace(GeoPlace g) async {
    _city = g.name;
    _lat = g.lat;
    _lon = g.lon;
    _auto = false;
    // Data kota lama dibuang supaya tidak tampil di bawah nama kota baru.
    _tempC = _feels = _wind = _hi = _lo = null;
    _humidity = _code = _rain = null;
    _error = null;
    notifyListeners();
    await _saveLocation();
    await refresh();
  }

  Future<void> refresh() async {
    final lat = _lat, lon = _lon;
    if (lat == null || lon == null) return;
    final id = ++_reqId;
    _loading = true;
    _safeNotify();
    try {
      final j = await _getJson(Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m',
        'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': '1',
      })) as Map;
      if (id != _reqId) return; // sudah ada permintaan yang lebih baru
      final cur = j['current'] as Map;
      _tempC = (cur['temperature_2m'] as num?)?.toDouble();
      _feels = (cur['apparent_temperature'] as num?)?.toDouble();
      _humidity = (cur['relative_humidity_2m'] as num?)?.round();
      _wind = (cur['wind_speed_10m'] as num?)?.toDouble();
      _code = (cur['weather_code'] as num?)?.toInt();
      _isDay = ((cur['is_day'] as num?) ?? 1) == 1;

      double? first(String k) {
        final d = (j['daily'] as Map?)?[k] as List?;
        return (d != null && d.isNotEmpty) ? (d.first as num?)?.toDouble() : null;
      }

      _hi = first('temperature_2m_max');
      _lo = first('temperature_2m_min');
      _rain = first('precipitation_probability_max')?.round();
      _updated = DateTime.now();
      _error = null;
    } catch (_) {
      if (id != _reqId) return;
      _error = _tempC == null ? 'Offline' : 'Offline - cached data';
    } finally {
      if (id == _reqId) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
