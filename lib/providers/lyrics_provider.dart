import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'music_provider.dart';

class _SkipNetwork implements Exception {
  const _SkipNetwork();
}

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

enum LyricsState { idle, loading, synced, plain, notFound, instrumental, offline }

/// Lirik dari LRCLIB (lrclib.net): gratis, tanpa API key, mendukung lirik
/// tersinkron (LRC). Sinkronisasi memakai posisi lagu dari MPRIS.
class LyricsProvider extends ChangeNotifier {
  static const _headers = {'User-Agent': 'DynamicIsland/1.0'};

  LyricsState _state = LyricsState.idle;
  List<LyricLine> _lines = const [];
  String _plain = '';
  String _lastTitle = '', _lastArtist = '', _lastFile = '';
  int _gen = 0;
  MusicProvider? _music;

  LyricsState get state => _state;
  List<LyricLine> get lines => _lines;
  String get plain => _plain;

  void bind(MusicProvider m) {
    _music?.removeListener(_onMusic);
    _music = m..addListener(_onMusic);
    _onMusic();
  }

  void _onMusic() {
    final m = _music;
    if (m == null) return;
    if (!m.hasTrack) {
      if (_lastTitle.isNotEmpty) {
        _lastTitle = _lastArtist = _lastFile = '';
        _gen++;
        _state = LyricsState.idle;
        _lines = const [];
        _plain = '';
        notifyListeners();
      }
      return;
    }
    final file = m.filePath ?? '';
    if (m.title == _lastTitle && m.artist == _lastArtist && file == _lastFile) {
      return;
    }
    _lastTitle = m.title;
    _lastArtist = m.artist;
    _lastFile = file;
    _fetch(m.title, m.artist, m.album, m.duration.inSeconds, file);
  }

  /// Index baris yang sedang dinyanyikan pada posisi [p] (-1 = belum mulai).
  int indexAt(Duration p) {
    var idx = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= p) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  static String _cleanTitle(String t) => t
      .replaceAll(
          RegExp(r'\s*[\(\[][^\)\]]*(remaster|live|version|feat|ft\.|explicit|mono|stereo|edit)[^\)\]]*[\)\]]',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'\s+-\s+(remaster|live|\d{4}|single|radio|mono|stereo).*$',
              caseSensitive: false),
          '')
      .trim();

  Future<dynamic> _json(Uri uri) async {
    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // ---- offline: file .lrc di samping lagu + cache lirik di disk ----

  static Future<String?> _readText(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return utf8.decode(await f.readAsBytes(), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Cari file .lrc / .txt dengan nama sama di folder lagu lokal.
  Future<bool> _loadSidecar(String filePath, int gen) async {
    final sep = RegExp(r'[\\/]');
    final dot = filePath.lastIndexOf('.');
    final base = dot > filePath.lastIndexOf(sep) ? filePath.substring(0, dot) : filePath;
    for (final ext in ['lrc', 'LRC', 'txt']) {
      final text = await _readText('$base.$ext');
      if (text == null || text.trim().isEmpty) continue;
      if (gen != _gen) return true;
      final lines = ext.toLowerCase() == 'lrc' ? _parseLrc(text) : const <LyricLine>[];
      if (lines.isNotEmpty) {
        _lines = lines;
        _state = LyricsState.synced;
      } else {
        _plain = text.trim();
        _state = LyricsState.plain;
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  static File? _cacheFile(String track, String artist) {
    try {
      final env = Platform.environment;
      final base = Platform.isWindows
          ? env['LOCALAPPDATA']
          : (env['XDG_CACHE_HOME'] ??
              (env['HOME'] != null ? '${env['HOME']}/.cache' : null));
      if (base == null) return null;
      final key = '${track.toLowerCase()}|${artist.toLowerCase()}';
      var h = 5381;
      for (final c in key.codeUnits) {
        h = ((h * 33) ^ c) & 0x7fffffff;
      }
      final safe = key.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final name = safe.length > 50 ? safe.substring(0, 50) : safe;
      final sep = Platform.pathSeparator;
      return File('$base${sep}dynamic_island${sep}lyrics$sep${name}_$h.json');
    } catch (_) {
      return null;
    }
  }

  static Future<Map?> _readCache(String track, String artist) async {
    final f = _cacheFile(track, artist);
    if (f == null) return null;
    final t = await _readText(f.path);
    if (t == null) return null;
    try {
      final j = jsonDecode(t);
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String track, String artist, Map hit) async {
    final f = _cacheFile(track, artist);
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'instrumental': hit['instrumental'] == true,
        'syncedLyrics': hit['syncedLyrics'] ?? '',
        'plainLyrics': hit['plainLyrics'] ?? '',
      }));
    } catch (_) {}
  }

  Future<void> _fetch(String title, String artist, String album, int durSec,
      String filePath) async {
    final gen = ++_gen;
    _state = LyricsState.loading;
    _lines = const [];
    _plain = '';
    notifyListeners();

    final track = _cleanTitle(title);
    final firstArtist = artist.split(',').first.trim();
    Map? hit;
    var netFailed = false;

    // 1) Lirik lokal di samping file lagu (paling cepat, tanpa internet).
    if (filePath.isNotEmpty && await _loadSidecar(filePath, gen)) return;

    // 2) Cache dari pencarian sebelumnya.
    hit = await _readCache(track, firstArtist);
    if (gen != _gen) return;

    try {
      if (hit != null) throw const _SkipNetwork();
      // 1) Pencocokan tepat
      final exact = await _json(Uri.https('lrclib.net', '/api/get', {
        'track_name': track,
        'artist_name': firstArtist,
        if (album.isNotEmpty) 'album_name': album,
        if (durSec > 0) 'duration': '$durSec',
      }));
      if (exact is Map) hit = exact;

      // 2) Pencarian
      if (hit == null) {
        for (final params in [
          {'track_name': track, 'artist_name': firstArtist},
          {'q': '$track $firstArtist'},
        ]) {
          final r = await _json(Uri.https('lrclib.net', '/api/search', params));
          if (r is List && r.isNotEmpty) {
            final items = r.whereType<Map>().toList();
            bool near(Map e) =>
                durSec <= 0 ||
                (((e['duration'] as num?)?.round() ?? 0) - durSec).abs() <= 5;
            bool synced(Map e) =>
                ((e['syncedLyrics'] as String?) ?? '').isNotEmpty;
            hit = items.firstWhere((e) => synced(e) && near(e),
                orElse: () => items.firstWhere(synced,
                    orElse: () => items.first));
            break;
          }
        }
      }
    } on _SkipNetwork {
      // Sudah ada di cache.
    } catch (_) {
      hit = null;
      netFailed = true;
    }

    if (gen != _gen) return; // lagu sudah berganti

    if (hit != null && !netFailed) {
      // Simpan hasil terbaru agar bisa dipakai offline.
      _writeCache(track, firstArtist, hit);
    }

    if (hit == null) {
      _state = netFailed ? LyricsState.offline : LyricsState.notFound;
    } else if (hit['instrumental'] == true) {
      _state = LyricsState.instrumental;
    } else {
      final synced = (hit['syncedLyrics'] as String?) ?? '';
      final plain = (hit['plainLyrics'] as String?) ?? '';
      if (synced.isNotEmpty) {
        _lines = _parseLrc(synced);
        _state = _lines.isEmpty ? LyricsState.notFound : LyricsState.synced;
      } else if (plain.isNotEmpty) {
        _plain = plain;
        _state = LyricsState.plain;
      } else {
        _state = LyricsState.notFound;
      }
    }
    notifyListeners();
  }

  static List<LyricLine> _parseLrc(String lrc) {
    final tag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final out = <LyricLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final matches = tag.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.replaceAll(tag, '').trim();
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final fracStr = m.group(3) ?? '0';
        final ms = int.parse(fracStr.padRight(3, '0').substring(0, 3));
        out.add(LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms), text));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  @override
  void dispose() {
    _music?.removeListener(_onMusic);
    super.dispose();
  }
}
