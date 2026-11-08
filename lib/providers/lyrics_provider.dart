import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'music_provider.dart';
import 'settings_provider.dart';

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

  // ---- terjemahan ----
  SettingsProvider? _settings;
  String _trKey = '';
  int _trGen = 0;
  bool _translating = false;
  List<String> _trLines = const [];

  // ---- romaji (lagu Jepang) ----
  int _roGen = 0;
  bool _romanizing = false;
  List<String> _roLines = const [];

  LyricsState get state => _state;
  List<LyricLine> get lines => _lines;
  String get plain => _plain;
  bool get translating => _translating;
  bool get romanizing => _romanizing;
  bool get hasRomaji => _roLines.any((e) => e.trim().isNotEmpty);

  /// Romaji untuk baris ke-[i] (hanya lagu Jepang), atau null.
  String? romajiAt(int i) {
    if (i < 0 || i >= _roLines.length) return null;
    final t = _roLines[i].trim();
    return t.isEmpty ? null : t;
  }

  /// Baris lirik polos (untuk mode non-sinkron).
  List<String> get plainLines => _plain.split('\n');

  /// Terjemahan untuk baris ke-[i] (lirik tersinkron / polos), atau null.
  String? translationAt(int i) {
    if (i < 0 || i >= _trLines.length) return null;
    final t = _trLines[i].trim();
    return t.isEmpty ? null : t;
  }

  bool get hasTranslation => _trLines.any((e) => e.trim().isNotEmpty);

  void bindSettings(SettingsProvider s) {
    _settings?.removeListener(_onSettings);
    _settings = s..addListener(_onSettings);
    _trKey = _curKey();
  }

  String _curKey() {
    final s = _settings;
    return s == null
        ? ''
        : '${s.lyricsTranslate}|${s.lyricsTargetLang}|${s.lyricsRomaji}';
  }

  void _onSettings() {
    final k = _curKey();
    if (k == _trKey) return;
    _trKey = k;
    _refreshExtras();
  }

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
        _trGen++;
        _trLines = const [];
        _translating = false;
        _roGen++;
        _roLines = const [];
        _romanizing = false;
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
      _refreshExtras();
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
    _trGen++;
    _trLines = const [];
    _translating = false;
    _roGen++;
    _roLines = const [];
    _romanizing = false;
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
    _refreshExtras();
  }

  // ---------------------------------------------------------------------
  // Terjemahan lirik (Google Translate endpoint gratis, tanpa API key).
  // Bahasa sumber dideteksi otomatis sehingga semua region/bahasa didukung.
  // ---------------------------------------------------------------------

  static String _primary(String code) =>
      code.toLowerCase().split(RegExp(r'[-_]')).first;

  static File? _trCacheFile(String key) => _cacheFile('tr', key);

  static int _hash(String key) {
    var h = 5381;
    for (final c in key.codeUnits) {
      h = ((h * 33) ^ c) & 0x7fffffff;
    }
    return h;
  }

  void _refreshExtras() {
    _translateCurrent();
    _romanizeCurrent();
  }

  List<String> _srcLines() {
    if (_state == LyricsState.synced) return _lines.map((e) => e.text).toList();
    if (_state == LyricsState.plain) return plainLines;
    return const [];
  }

  static final _kanaRe = RegExp(r'[\u3040-\u30ff]');
  static final _cjkRe = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');

  /// Romaji lagu Jepang: lagu dianggap Jepang jika memuat kana. Tiap baris
  /// yang berisi huruf Jepang dibacakan lewat Google Translate (dt=rm).
  Future<void> _romanizeCurrent() async {
    final id = ++_roGen;
    final s = _settings;
    final src = _srcLines();
    final isJa = src.any(_kanaRe.hasMatch);
    if (s == null || !s.lyricsRomaji || !isJa) {
      if (_romanizing || _roLines.isNotEmpty) {
        _romanizing = false;
        _roLines = const [];
        notifyListeners();
      }
      return;
    }
    _roLines = const [];
    _romanizing = true;
    notifyListeners();

    List<String>? result;
    try {
      final key = 'ro|${_hash(src.join('\n'))}|${src.length}';
      final cache = _trCacheFile(key);
      if (cache != null) {
        final t = await _readText(cache.path);
        if (t != null) {
          try {
            final j = jsonDecode(t);
            if (j is List && j.length == src.length) {
              result = j.map((e) => '$e').toList();
            }
          } catch (_) {}
        }
      }
      if (result == null) {
        final out = List<String>.filled(src.length, '');
        final idx = [
          for (var i = 0; i < src.length; i++)
            if (_cjkRe.hasMatch(src[i])) i
        ];
        var ok = false;
        for (var i = 0; i < idx.length; i += 4) {
          if (id != _roGen) return;
          final end = (i + 4 < idx.length) ? i + 4 : idx.length;
          final got = await Future.wait(
              [for (var k = i; k < end; k++) _romaji(src[idx[k]])]);
          for (var k = 0; k < got.length; k++) {
            if (got[k] != null) {
              out[idx[i + k]] = got[k]!;
              ok = true;
            }
          }
        }
        if (ok) {
          result = out;
          if (cache != null) {
            try {
              await cache.parent.create(recursive: true);
              await cache.writeAsString(jsonEncode(out));
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      result = null;
    }
    if (id != _roGen) return;
    _romanizing = false;
    _roLines = result ?? const [];
    notifyListeners();
  }

  Future<String?> _romaji(String line) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'ja',
      'tl': 'en',
      'dt': ['t', 'rm'],
      'dj': '0',
    });
    try {
      final res = await http
          .post(uri, headers: _headers, body: {'q': line.replaceAll('\n', ' ')})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! List || j.isEmpty || j[0] is! List) return null;
      // Entri transliterasi: [null, null, <romaji terjemahan>, <romaji sumber>]
      final sb = StringBuffer();
      for (final seg in j[0] as List) {
        if (seg is List && seg.length > 3 && seg[0] == null && seg[3] is String) {
          if (sb.isNotEmpty) sb.write(' ');
          sb.write(seg[3] as String);
        }
      }
      final r = sb.toString().trim();
      return r.isEmpty ? null : r;
    } catch (_) {
      return null;
    }
  }

  Future<void> _translateCurrent() async {
    final id = ++_trGen;
    final s = _settings;
    final List<String> src;
    if (_state == LyricsState.synced) {
      src = _lines.map((e) => e.text).toList();
    } else if (_state == LyricsState.plain) {
      src = plainLines;
    } else {
      src = const [];
    }
    if (s == null || !s.lyricsTranslate || src.every((e) => e.trim().isEmpty)) {
      if (_translating || _trLines.isNotEmpty) {
        _translating = false;
        _trLines = const [];
        notifyListeners();
      }
      return;
    }
    final target = s.lyricsTargetLang;
    _trLines = const [];
    _translating = true;
    notifyListeners();

    List<String>? result;
    try {
      final key = '$target|${_hash(src.join('\n'))}|${src.length}';
      final cache = _trCacheFile(key);
      if (cache != null) {
        final t = await _readText(cache.path);
        if (t != null) {
          try {
            final j = jsonDecode(t);
            if (j is List && j.length == src.length) {
              result = j.map((e) => '$e').toList();
            }
          } catch (_) {}
        }
      }
      if (result == null) {
        result = await _translateAll(src, target);
        if (result != null && cache != null) {
          try {
            await cache.parent.create(recursive: true);
            await cache.writeAsString(jsonEncode(result));
          } catch (_) {}
        }
      }
    } catch (_) {
      result = null;
    }
    if (id != _trGen) return; // lagu/pengaturan sudah berganti
    _translating = false;
    _trLines = result ?? const [];
    notifyListeners();
  }

  /// Terjemahkan semua baris. Mengembalikan daftar sepanjang [src] (baris
  /// kosong / yang sudah berbahasa tujuan menjadi ''), atau null jika gagal.
  Future<List<String>?> _translateAll(List<String> src, String target) async {
    final idx = <int>[
      for (var i = 0; i < src.length; i++)
        if (src[i].trim().isNotEmpty) i
    ];
    final out = List<String>.filled(src.length, '');
    var pos = 0;
    var any = false;
    while (pos < idx.length) {
      // Kelompokkan baris hingga ~1800 karakter per permintaan.
      final chunk = <int>[];
      var len = 0;
      while (pos < idx.length && (chunk.isEmpty || len + src[idx[pos]].length < 1800)) {
        chunk.add(idx[pos]);
        len += src[idx[pos]].length + 1;
        pos++;
      }
      final texts = chunk.map((i) => src[i].replaceAll('\n', ' ').trim()).toList();
      final r = await _translateChunk(texts, target);
      if (r == null) {
        if (!any) return null;
        continue; // sebagian berhasil: tampilkan yang ada
      }
      any = true;
      for (var k = 0; k < chunk.length; k++) {
        final o = texts[k];
        final t = r[k].trim();
        // Sembunyikan jika hasilnya identik (baris sudah dalam bahasa tujuan).
        out[chunk[k]] = t.toLowerCase() == o.toLowerCase() ? '' : t;
      }
    }
    return any ? out : null;
  }

  /// Satu permintaan; jika jumlah baris hasil tidak cocok, ulangi per baris.
  Future<List<String>?> _translateChunk(List<String> texts, String target) async {
    final joined = await _gtx(texts.join('\n'), target);
    if (joined == null) return null;
    final parts = joined.split('\n');
    if (parts.length == texts.length) return parts;
    // Fallback: per baris, 4 permintaan paralel.
    final res = List<String>.filled(texts.length, '');
    var ok = false;
    for (var i = 0; i < texts.length; i += 4) {
      final end = (i + 4 < texts.length) ? i + 4 : texts.length;
      final got = await Future.wait(
          [for (var k = i; k < end; k++) _gtx(texts[k], target)]);
      for (var k = 0; k < got.length; k++) {
        if (got[k] != null) {
          res[i + k] = got[k]!.replaceAll('\n', ' ');
          ok = true;
        }
      }
    }
    return ok ? res : null;
  }

  Future<String?> _gtx(String text, String target) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': target,
      'dt': 't',
      'dj': '0',
    });
    try {
      final res = await http
          .post(uri, headers: _headers, body: {'q': text})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! List || j.isEmpty || j[0] is! List) return null;
      final sb = StringBuffer();
      for (final seg in j[0] as List) {
        if (seg is List && seg.isNotEmpty && seg[0] is String) sb.write(seg[0]);
      }
      // Lagu yang sudah berbahasa tujuan tidak perlu diterjemahkan.
      final det = j.length > 2 && j[2] is String ? j[2] as String : '';
      if (det.isNotEmpty && _primary(det) == _primary(target)) return text;
      return sb.toString();
    } catch (_) {
      return null;
    }
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
    _settings?.removeListener(_onSettings);
    _music?.removeListener(_onMusic);
    super.dispose();
  }
}
