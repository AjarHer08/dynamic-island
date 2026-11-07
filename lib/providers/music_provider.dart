import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

enum MusicSource { spotify, youtubeMusic, appleMusic, soundcloud, other }

class _Snap {
  final String bus, identity, status, title, artist, album;
  final String? artUrl, url;
  final Duration length, position;

  _Snap({
    required this.bus,
    required this.identity,
    required this.status,
    required this.title,
    required this.artist,
    required this.album,
    required this.artUrl,
    required this.url,
    required this.length,
    required this.position,
  });

  int get rank => status == 'Playing' ? 2 : (status == 'Paused' ? 1 : 0);
}

/// Musik asli lewat MPRIS (D-Bus). Mendukung semua pemutar yang mengekspos
/// MPRIS: Spotify (aplikasi desktop), YouTube Music / Apple Music / SoundCloud
/// (di browser atau aplikasi desktop-nya), VLC, dll.
/// Spektrum visualizer diambil dari audio sistem (parec) dan di-FFT;
/// bila parec tidak ada, jatuh ke animasi simulasi.
class MusicProvider extends ChangeNotifier {
  static const _playerPath = '/org/mpris/MediaPlayer2';
  static const _ifPlayer = 'org.mpris.MediaPlayer2.Player';
  static const _ifRoot = 'org.mpris.MediaPlayer2';
  static const _bands = 32;
  static const _n = 512; // ukuran FFT

  // ---- state yang dilihat UI ----
  bool _playing = false;
  bool _hasPlayer = false;
  String _title = '', _artist = '', _album = '', _sourceName = '';
  String? _artUrl;
  String? _fileUrl; // file:// untuk musik lokal (offline)
  MusicSource _source = MusicSource.other;
  Duration _duration = Duration.zero;
  Duration _basePos = Duration.zero;
  DateTime _basePosAt = DateTime.now();
  List<double> _spectrum = List<double>.filled(_bands, 0.0);

  bool get isPlaying => _playing;
  bool get hasTrack => _hasPlayer && _title.isNotEmpty;
  String get title => _title;
  String get artist => _artist;
  String get album => _album;
  String get sourceName => _sourceName;
  MusicSource get source => _source;
  String? get artUrl => _artUrl;

  /// Path file lagu bila yang diputar adalah file lokal, selain itu null.
  String? get filePath {
    final u = _fileUrl;
    if (u == null || !u.startsWith('file://')) return null;
    try {
      return Uri.parse(u).toFilePath();
    } catch (_) {
      return null;
    }
  }
  /// Perkiraan: yang sedang diputar adalah video (film/anime/YouTube),
  /// bukan musik. Dipakai untuk menyembunyikan island otomatis.
  bool get isVideoPlaying {
    if (!_playing) return false;
    final u = (_fileUrl ?? '').toLowerCase();
    if (RegExp(r'\.(mp4|mkv|avi|webm|mov|wmv|flv|m4v|ts)(\?|$)').hasMatch(u)) {
      return true;
    }
    if (_source != MusicSource.other) return false; // Spotify, YT Music, dst.
    final n = '${_sourceName.toLowerCase()} ${(_bus ?? '').toLowerCase()}';
    const players = [
      'vlc', 'mpv', 'celluloid', 'totem', 'haruna', 'smplayer', 'mplayer',
      'kodi', 'plex', 'jellyfin', 'netflix', 'firefox', 'chrom', 'brave',
      'edge', 'opera', 'vivaldi', 'zen', 'librewolf',
    ];
    return players.any(n.contains) && !u.contains('music.') && !u.contains('soundcloud');
  }

  Duration get duration => _duration;
  List<double> get spectrum => _spectrum;

  Duration get position {
    var p = _basePos;
    if (_playing) p += DateTime.now().difference(_basePosAt);
    if (_duration > Duration.zero && p > _duration) p = _duration;
    return p;
  }

  double get progress => _duration.inMilliseconds > 0
      ? (position.inMilliseconds / _duration.inMilliseconds)
          .clamp(0.0, 1.0)
          .toDouble()
      : 0.0;

  // ---- D-Bus ----
  DBusClient? _client;
  String? _bus;
  final Map<String, String> _identity = {};
  Timer? _poll, _uiTimer;
  bool _polling = false;

  void start() {
    if (!Platform.isLinux || _poll != null) return;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _pollOnce());
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_playing) notifyListeners(); // geser progress bar
    });
    _pollOnce();
  }

  // ---- musik lokal (offline) ----

  /// File lokal sering tanpa tag: ambil judul/artis dari nama file,
  /// mis. "01 - Artis - Judul.mp3" -> (Artis, Judul).
  static (String, String)? _fromFileName(String? url) {
    if (url == null || !url.startsWith('file://')) return null;
    String path;
    try {
      path = Uri.parse(url).toFilePath();
    } catch (_) {
      return null;
    }
    var name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = name.replaceFirst(RegExp(r'^\d{1,3}\s*[.\-_]\s*'), '').trim();
    if (name.isEmpty) return null;
    final i = name.indexOf(' - ');
    if (i > 0) return (name.substring(0, i).trim(), name.substring(i + 3).trim());
    return ('', name);
  }

  final Map<String, String?> _coverCache = {};

  /// Cover album di folder yang sama (cover.jpg, folder.png, dst.).
  String? _coverNear(String? url) {
    if (url == null || !url.startsWith('file://')) return null;
    String dir;
    try {
      final path = Uri.parse(url).toFilePath();
      final i = path.lastIndexOf(RegExp(r'[\\/]'));
      if (i <= 0) return null;
      dir = path.substring(0, i);
    } catch (_) {
      return null;
    }
    return _coverCache.putIfAbsent(dir, () {
      const names = ['cover', 'folder', 'front', 'album', 'albumart', 'artwork'];
      const exts = ['jpg', 'jpeg', 'png', 'webp'];
      for (final n in names) {
        for (final e in exts) {
          for (final cand in [n, '${n[0].toUpperCase()}${n.substring(1)}']) {
            final f = File('$dir${Platform.pathSeparator}$cand.$e');
            try {
              if (f.existsSync()) return Uri.file(f.path).toString();
            } catch (_) {}
          }
        }
      }
      return null;
    });
  }

  Future<_Snap?> _read(DBusClient c, String name) async {
    try {
      final obj = DBusRemoteObject(c,
          name: name, path: DBusObjectPath(_playerPath));
      final props = await obj.getAllProperties(_ifPlayer);
      final status = props['PlaybackStatus']?.toNative()?.toString() ?? 'Stopped';
      final raw = props['Metadata']?.toNative();
      final md = raw is Map ? raw : const {};

      String artist = '';
      final a = md['xesam:artist'];
      if (a is Iterable) {
        artist = a.map((e) => e.toString()).join(', ');
      } else if (a != null) {
        artist = a.toString();
      }
      final len = md['mpris:length'];
      final pos = props['Position']?.toNative();

      var identity = _identity[name];
      if (identity == null) {
        try {
          final v = await obj.getProperty(_ifRoot, 'Identity');
          identity = v.toNative().toString();
        } catch (_) {
          identity = '';
        }
        _identity[name] = identity;
      }

      final url = md['xesam:url']?.toString();
      var title = md['xesam:title']?.toString() ?? '';
      if (title.isEmpty) {
        // File lokal tanpa tag: pakai nama file.
        final f = _fromFileName(url);
        if (f != null) {
          title = f.$2;
          if (artist.isEmpty) artist = f.$1;
        }
      }
      var art = md['mpris:artUrl']?.toString();
      if (art == null || art.isEmpty) art = _coverNear(url);

      return _Snap(
        bus: name,
        identity: identity,
        status: status,
        title: title,
        artist: artist,
        album: md['xesam:album']?.toString() ?? '',
        artUrl: art,
        url: url,
        length: Duration(microseconds: len is num ? len.toInt() : 0),
        position: Duration(microseconds: pos is num ? pos.toInt() : 0),
      );
    } catch (_) {
      return null;
    }
  }

  (MusicSource, String) _detect(_Snap s) {
    final bus = s.bus.toLowerCase();
    final url = (s.url ?? '').toLowerCase();
    if (bus.contains('spotify')) return (MusicSource.spotify, 'Spotify');
    if (url.contains('music.youtube.com') ||
        bus.contains('youtubemusic') ||
        bus.contains('youtube-music') ||
        bus.contains('ytmdesktop') ||
        bus.contains('pear')) {
      return (MusicSource.youtubeMusic, 'YouTube Music');
    }
    if (url.contains('soundcloud.com') || bus.contains('soundcloud')) {
      return (MusicSource.soundcloud, 'SoundCloud');
    }
    if (url.contains('music.apple.com') ||
        bus.contains('applemusic') ||
        bus.contains('cider')) {
      return (MusicSource.appleMusic, 'Apple Music');
    }
    final name = s.identity.isNotEmpty
        ? s.identity
        : s.bus.replaceFirst('$_ifRoot.', '');
    return (MusicSource.other, name);
  }

  Future<void> _pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      final c = _client ??= DBusClient.session();
      final names = await c.listNames();
      final players = names.where((n) =>
          n.startsWith('$_ifRoot.') && !n.contains('playerctld'));

      _Snap? best;
      var bestScore = -1;
      for (final n in players) {
        final snap = await _read(c, n);
        if (snap == null) continue;
        // Pemutar idle tanpa judul (mis. browser terbuka) diabaikan.
        if (snap.title.isEmpty && snap.rank < 2) continue;
        final score = snap.rank * 2 + (n == _bus ? 1 : 0);
        if (score > bestScore) {
          best = snap;
          bestScore = score;
        }
      }

      if (best == null) {
        if (_hasPlayer) {
          final wasPlaying = _playing;
          _hasPlayer = false;
          _playing = false;
          _bus = null;
          _title = _artist = _album = _sourceName = '';
          _artUrl = null;
          _fileUrl = null;
          _duration = _basePos = Duration.zero;
          notifyListeners();
          if (wasPlaying) _syncAudio();
        }
        return;
      }

      _bus = best.bus;
      final (src, label) = _detect(best);
      final playing = best.status == 'Playing';
      final drift = (best.position - position).abs();
      final changed = !_hasPlayer ||
          playing != _playing ||
          best.title != _title ||
          best.artist != _artist ||
          best.artUrl != _artUrl ||
          best.url != _fileUrl ||
          best.length != _duration ||
          src != _source ||
          label != _sourceName;
      final playingChanged = playing != _playing;

      _hasPlayer = true;
      _playing = playing;
      _title = best.title;
      _artist = best.artist;
      _album = best.album;
      _artUrl = best.artUrl;
      _fileUrl = best.url;
      _duration = best.length;
      _source = src;
      _sourceName = label;
      _basePos = best.position;
      _basePosAt = DateTime.now();

      if (changed || drift > const Duration(seconds: 2)) notifyListeners();
      if (playingChanged) _syncAudio();
    } catch (_) {
      // D-Bus tidak tersedia: biarkan state kosong.
    } finally {
      _polling = false;
    }
  }

  // ---- kontrol ----
  Future<void> _call(String method) async {
    final bus = _bus, c = _client;
    if (bus == null || c == null) return;
    try {
      final obj =
          DBusRemoteObject(c, name: bus, path: DBusObjectPath(_playerPath));
      await obj.callMethod(_ifPlayer, method, [],
          replySignature: DBusSignature(''));
    } catch (_) {}
    _pollOnce();
  }

  Future<void> toggle() {
    // Optimistis: UI langsung berubah, poll berikutnya mengoreksi.
    _basePos = position;
    _basePosAt = DateTime.now();
    _playing = !_playing;
    notifyListeners();
    _syncAudio();
    return _call('PlayPause');
  }

  Future<void> next() => _call('Next');
  Future<void> previous() => _call('Previous');

  // ---- spektrum audio ----
  Process? _parec;
  StreamSubscription<List<int>>? _audioSub;
  bool _capturing = false;
  Timer? _fake;
  final _rng = Random();
  final BytesBuilder _buf = BytesBuilder(copy: false);
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  final Float64List _re = Float64List(_n), _im = Float64List(_n);
  late final Float64List _win = Float64List.fromList(
      List<double>.generate(_n, (i) => 0.5 - 0.5 * cos(2 * pi * i / (_n - 1))));
  late final List<int> _edges = List<int>.generate(_bands + 1, (i) {
    // 22050 Hz / 512 = ~43 Hz per bin. Pita log dari bin 2 sampai bin 200.
    return (2 * pow(100.0, i / _bands)).round();
  });

  void _syncAudio() {
    if (_playing) {
      if (!_capturing) _startCapture();
    } else {
      _stopCapture();
      _fake?.cancel();
      _fake = null;
      _spectrum = List<double>.filled(_bands, 0.0);
      notifyListeners();
    }
  }

  Future<void> _startCapture() async {
    if (!Platform.isLinux) return;
    _capturing = true;
    try {
      final p = await Process.start('parec', [
        '-d', '@DEFAULT_MONITOR@',
        '--format=s16le',
        '--rate=22050',
        '--channels=1',
        '--latency-msec=30',
        '--client-name=dynamic_island',
      ]);
      if (!_capturing) {
        p.kill();
        return;
      }
      _parec = p;
      p.stderr.drain<void>();
      _audioSub = p.stdout.listen(_onAudio);
      p.exitCode.then((_) {
        if (identical(_parec, p)) {
          _parec = null;
          _audioSub?.cancel();
          _audioSub = null;
          if (_capturing && _playing) _startFake();
        }
      });
    } catch (_) {
      if (_playing) _startFake();
    }
  }

  void _stopCapture() {
    _capturing = false;
    _audioSub?.cancel();
    _audioSub = null;
    _parec?.kill();
    _parec = null;
    _buf.clear();
  }

  void _startFake() {
    _fake?.cancel();
    _fake = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_playing) return;
      _spectrum = List<double>.generate(_bands,
          (i) => _spectrum[i] + (_rng.nextDouble() - _spectrum[i]) * 0.18);
      notifyListeners();
    });
  }

  void _onAudio(List<int> chunk) {
    _buf.add(chunk);
    if (_buf.length < _n * 2) return;
    final bytes = _buf.takeBytes();
    if (bytes.length.isOdd) _buf.addByte(bytes.last);
    final end = bytes.length - (bytes.length & 1);

    final now = DateTime.now();
    if (now.difference(_lastFrame) < const Duration(milliseconds: 40)) return;
    _lastFrame = now;

    final bd = ByteData.sublistView(bytes, end - _n * 2, end);
    for (var i = 0; i < _n; i++) {
      _re[i] = bd.getInt16(i * 2, Endian.little) / 32768.0 * _win[i];
      _im[i] = 0.0;
    }
    _fft();

    final next = List<double>.filled(_bands, 0.0);
    for (var b = 0; b < _bands; b++) {
      final lo = _edges[b];
      final hi = max(_edges[b + 1], lo + 1);
      var sum = 0.0;
      for (var k = lo; k < hi && k < _n ~/ 2; k++) {
        sum += sqrt(_re[k] * _re[k] + _im[k] * _im[k]);
      }
      final m = sum / (hi - lo) / (_n / 2);
      final db = 20 * log(m + 1e-9) / ln10;
      var v = (db + 80) / 50 + (b / _bands) * 0.15; // sedikit angkat nada tinggi
      v = v.clamp(0.0, 1.0).toDouble();
      next[b] = max(v, _spectrum[b] * 0.82); // attack cepat, decay halus
    }
    _spectrum = next;
    notifyListeners();
  }

  void _fft() {
    // Bit-reversal
    var j = 0;
    for (var i = 1; i < _n; i++) {
      var bit = _n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = _re[i];
        _re[i] = _re[j];
        _re[j] = tr;
        final ti = _im[i];
        _im[i] = _im[j];
        _im[j] = ti;
      }
    }
    for (var len = 2; len <= _n; len <<= 1) {
      final ang = -2 * pi / len;
      final wlr = cos(ang), wli = sin(ang);
      final half = len >> 1;
      for (var i = 0; i < _n; i += len) {
        var wr = 1.0, wi = 0.0;
        for (var k = 0; k < half; k++) {
          final a = i + k, b = a + half;
          final vr = _re[b] * wr - _im[b] * wi;
          final vi = _re[b] * wi + _im[b] * wr;
          _re[b] = _re[a] - vr;
          _im[b] = _im[a] - vi;
          _re[a] += vr;
          _im[a] += vi;
          final nwr = wr * wlr - wi * wli;
          wi = wr * wli + wi * wlr;
          wr = nwr;
        }
      }
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _uiTimer?.cancel();
    _fake?.cancel();
    _stopCapture();
    _client?.close();
    super.dispose();
  }
}
