import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/album.dart';
import 'audio_player_handler.dart';

/// Fasada nad [AudioPlayerHandler] zachowujaca dotychczasowe API uzywane przez
/// UI (ChangeNotifier + Provider). Cala logika odtwarzania i sesja medialna
/// (ekran blokady, Android Auto) zyje w [AudioPlayerHandler].
class AudioService extends ChangeNotifier {
  final AudioPlayerHandler _handler;
  final OnAudioQuery _audioQuery = OnAudioQuery();

  AudioService(this._handler) {
    _handler.onChanged = notifyListeners;
    _handler.resolveUri = _resolvePathToUri;
  }

  static const MethodChannel _mediaStore = MethodChannel('kolekcja/mediastore');

  /// Cache mapy: surowa sciezka pliku -> content:// URI z MediaStore.
  Map<String, String>? _pathToUri;

  /// Zamienia surowa sciezke (`/storage/...`) na content:// URI z MediaStore.
  /// Na Androidzie 13+ tylko URI respektuje uprawnienie READ_MEDIA_AUDIO —
  /// odtwarzanie po surowej sciezce konczy sie bledem EACCES.
  Future<String?> _resolvePathToUri(String path) async {
    if (path.startsWith('content://')) return path;
    // Na web nie ma MediaStore, a Platform.* z dart:io rzuca wyjatek.
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;

    // 1. Natywny ContentResolver — niezawodny, niezalezny od on_audio_query.
    try {
      final uri = await _mediaStore.invokeMethod<String>(
        'uriForPath',
        {'path': path},
      );
      if (uri != null && uri.isNotEmpty) return uri;
    } catch (_) {
      // np. kanal niedostepny w trybie headless — sprobuj fallbacku nizej.
    }

    // 2. Fallback: on_audio_query (gdyby kanal natywny byl niedostepny).
    try {
      _pathToUri ??= {
        for (final s in await _audioQuery.querySongs(uriType: UriType.EXTERNAL))
          if (s.data.isNotEmpty && (s.uri ?? '').isNotEmpty) s.data: s.uri!,
      };
      return _pathToUri![path];
    } catch (_) {
      return null;
    }
  }

  /// Callback do zapisu historii odtwarzania.
  set onTrackPlayed(
    void Function(String albumId, String trackTitle, int durationSeconds)? cb,
  ) {
    _handler.onTrackPlayed = cb;
  }

  void Function(String albumId, String trackTitle, int durationSeconds)?
      get onTrackPlayed => _handler.onTrackPlayed;

  // Gettery (delegowane do handlera)
  AudioPlayerHandler get handler => _handler;
  AudioPlayer get player => _handler.player;
  AndroidEqualizer get equalizer => _handler.equalizer;
  int? get audioSessionId => _handler.audioSessionId;
  bool get isPlaying => _handler.isPlaying;
  bool get isLoading => _handler.isLoading;
  Duration get position => _handler.position;
  Duration get duration => _handler.duration;
  Album? get currentAlbum => _handler.currentAlbum;
  int get currentTrackIndex => _handler.currentTrackIndex;
  Track? get currentTrack => _handler.currentTrack;
  bool get shuffle => _handler.shuffle;
  LoopMode get loopMode => _handler.loopMode;
  bool get crossfadeEnabled => _handler.crossfadeEnabled;
  int get crossfadeDuration => _handler.crossfadeDuration;
  double get progress => _handler.progress;

  // ----- Uprawnienia i skanowanie (bez zmian) -----

  Future<bool> checkPermissions() async {
    // Na web nie ma uprawnien plikowych, a Platform.* z dart:io rzuca wyjatek.
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final status = await Permission.audio.request();
      if (status.isGranted) return true;

      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }

  Future<List<SongModel>> scanMusicFiles() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Brak uprawnien do odczytu plikow');
    }

    return await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
  }

  Future<List<AlbumModel>> scanAlbums() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Brak uprawnien do odczytu plikow');
    }

    return await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
  }

  Future<List<SongModel>> getSongsFromAlbum(int albumId) async {
    return await _audioQuery.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      albumId,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
    );
  }

  Track songToTrack(SongModel song) {
    return Track(
      title: song.title,
      filePath: song.data,
      durationSeconds: (song.duration ?? 0) ~/ 1000,
      trackNumber: song.track ?? 0,
    );
  }

  Future<Album> albumModelToAlbum(AlbumModel albumModel) async {
    final songs = await getSongsFromAlbum(albumModel.id);
    final tracks = songs.map((s) => songToTrack(s)).toList();

    tracks.sort((a, b) => a.trackNumber.compareTo(b.trackNumber));

    return Album(
      id: 'device_${albumModel.id}',
      artist: albumModel.artist ?? 'Nieznany artysta',
      title: albumModel.album,
      year: null,
      genre: 'other',
      format: 'digital',
      rating: 3,
      tracks: tracks,
    );
  }

  // ----- Sterowanie (delegowane do handlera) -----

  Future<void> playTrack(Album album, int trackIndex) async {
    // Na Androidzie 13+ odczyt pliku audio wymaga READ_MEDIA_AUDIO —
    // upewnij sie, ze jest przyznane zanim odtwarzacz otworzy plik.
    await checkPermissions();
    return _handler.playTrack(album, trackIndex);
  }

  Future<void> playAlbum(Album album) async {
    await checkPermissions();
    return _handler.playAlbum(album);
  }

  Future<void> togglePlayPause() => _handler.togglePlayPause();

  Future<void> nextTrack() => _handler.nextTrack();

  Future<void> previousTrack() => _handler.previousTrack();

  Future<void> seekTo(Duration position) => _handler.seekTo(position);

  Future<void> seekToPercent(double percent) =>
      _handler.seekToPercent(percent);

  Future<void> stop() => _handler.stopPlayback();

  void toggleShuffle() => _handler.toggleShuffle();

  void toggleLoopMode() => _handler.toggleLoopMode();

  void setCrossfade(bool enabled) => _handler.setCrossfade(enabled);

  void setCrossfadeDuration(int seconds) =>
      _handler.setCrossfadeDuration(seconds);

  static String formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _handler.dispose();
    super.dispose();
  }
}
