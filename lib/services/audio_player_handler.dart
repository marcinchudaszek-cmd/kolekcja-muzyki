import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import '../models/album.dart';

/// Rdzen odtwarzania oparty o [audio_service].
///
/// Laczy odtwarzanie [just_audio] z sesja medialna systemu Android, dzieki
/// czemu dziala sterowanie z ekranu blokady, powiadomienie odtwarzacza ORAZ
/// Android Auto (przegladanie kolekcji przez [getChildren]).
///
/// Cala logika odtwarzania zyje tutaj. Klasa [AudioService] (ChangeNotifier)
/// jest tylko cienka fasada delegujaca do tego handlera i powiadamiajaca UI.
class AudioPlayerHandler extends BaseAudioHandler {
  AudioPlayerHandler() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [_equalizer],
      ),
    );
    _init();
  }

  final AndroidEqualizer _equalizer = AndroidEqualizer();
  late final AudioPlayer _player;

  /// Wywolywane przy kazdej zmianie stanu — fasada podpina tu notifyListeners.
  VoidCallback? onChanged;

  /// Callback do zapisu historii odtwarzania (uzywany przez HomeScreen).
  void Function(String albumId, String trackTitle, int durationSeconds)?
      onTrackPlayed;

  /// Zamienia surowa sciezke pliku na content:// URI z MediaStore.
  /// Ustawiany przez fasade (uzywa on_audio_query). Konieczny, bo na
  /// Androidzie 13+ ExoPlayer nie moze otworzyc plikow w pamieci
  /// wspoldzielonej po surowej sciezce (EACCES) — tylko po content URI.
  Future<String?> Function(String path)? resolveUri;

  // Stan odtwarzania
  Album? _currentAlbum;
  int _currentTrackIndex = 0;
  Track? _currentTrack;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  bool _crossfadeEnabled = false;
  int _crossfadeDuration = 3; // sekundy
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Gettery
  AudioPlayer get player => _player;
  AndroidEqualizer get equalizer => _equalizer;
  int? get audioSessionId => _player.androidAudioSessionId;
  bool get isPlaying => _player.playing;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  Album? get currentAlbum => _currentAlbum;
  int get currentTrackIndex => _currentTrackIndex;
  Track? get currentTrack => _currentTrack;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDuration => _crossfadeDuration;

  double get progress {
    if (_duration.inMilliseconds == 0) return 0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  void _init() {
    // Rozglos stan do sesji medialnej (ekran blokady / Android Auto).
    _player.playbackEventStream.listen(_broadcastState);

    _player.playerStateStream.listen((state) {
      _isLoading = state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering;
      onChanged?.call();
    });

    _player.positionStream.listen((pos) {
      _position = pos;
      onChanged?.call();
    });

    _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      onChanged?.call();
    });

    // Automatyczne przejscie do nastepnego utworu.
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onTrackComplete();
      }
    });
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentTrackIndex,
    ));
  }

  // ----- Metadane / okladki -----

  Uri? _albumArtUri(Album album) {
    final path = album.coverPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Uri.file(path);
    }
    final url = album.coverUrl;
    if (url != null && url.isNotEmpty) {
      return Uri.tryParse(url);
    }
    return null;
  }

  MediaItem _trackToMediaItem(Album album, int index) {
    final t = album.tracks[index];
    return MediaItem(
      id: 'track/${album.id}/$index',
      title: t.title,
      album: album.title,
      artist: album.artist,
      duration: t.durationSeconds != null
          ? Duration(seconds: t.durationSeconds!)
          : null,
      artUri: _albumArtUri(album),
      playable: true,
    );
  }

  /// Buduje zrodlo audio dla utworu. Preferuje content:// URI (dziala z
  /// uprawnieniem READ_MEDIA_AUDIO na Androidzie 13+); surowa sciezka pliku
  /// jest tylko fallbackiem dla plikow w prywatnej pamieci aplikacji.
  Future<AudioSource> _audioSourceFor(Track track) async {
    final path = track.filePath!;
    if (path.startsWith('content://')) {
      return AudioSource.uri(Uri.parse(path));
    }
    // Mapuj surowa sciezke na content:// URI (wymagane na Androidzie 10+).
    final resolved = await resolveUri?.call(path);
    if (resolved != null && resolved.isNotEmpty) {
      return AudioSource.uri(Uri.parse(resolved));
    }
    // Fallback dla plikow w prywatnej pamieci aplikacji.
    return AudioSource.uri(Uri.file(path));
  }

  // ----- Sterowanie odtwarzaniem (uzywane przez fasade i UI) -----

  Future<void> playTrack(Album album, int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= album.tracks.length) return;

    final track = album.tracks[trackIndex];
    if (!track.hasFile) {
      throw Exception('Brak pliku dla tego utworu');
    }

    _currentAlbum = album;
    _currentTrackIndex = trackIndex;
    _currentTrack = track;
    _isLoading = true;
    onChanged?.call();

    // Opublikuj kolejke i aktualny utwor dla sesji medialnej / Android Auto.
    queue.add([
      for (int i = 0; i < album.tracks.length; i++) _trackToMediaItem(album, i),
    ]);
    mediaItem.add(_trackToMediaItem(album, trackIndex));

    try {
      await _player.setAudioSource(await _audioSourceFor(track));
      await _player.play();
      onTrackPlayed?.call(album.id, track.title, track.durationSeconds ?? 0);
    } catch (e) {
      debugPrint('Blad odtwarzania: $e');
      _isLoading = false;
      onChanged?.call();
      rethrow;
    }
  }

  Future<void> playAlbum(Album album) async {
    if (album.tracks.isEmpty) return;

    int firstPlayable = 0;
    for (int i = 0; i < album.tracks.length; i++) {
      if (album.tracks[i].hasFile) {
        firstPlayable = i;
        break;
      }
    }

    await playTrack(album, firstPlayable);
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
      if (_currentAlbum != null && _currentTrack != null) {
        onTrackPlayed?.call(
          _currentAlbum!.id,
          _currentTrack!.title,
          _currentTrack!.durationSeconds ?? 0,
        );
      }
    }
  }

  Future<void> nextTrack() async {
    if (_currentAlbum == null) return;

    int nextIndex = _currentTrackIndex + 1;
    while (nextIndex < _currentAlbum!.tracks.length) {
      if (_currentAlbum!.tracks[nextIndex].hasFile) {
        await playTrack(_currentAlbum!, nextIndex);
        return;
      }
      nextIndex++;
    }

    // Koniec albumu — sprawdz loop mode.
    if (_loopMode == LoopMode.all) {
      for (int i = 0; i < _currentAlbum!.tracks.length; i++) {
        if (_currentAlbum!.tracks[i].hasFile) {
          await playTrack(_currentAlbum!, i);
          return;
        }
      }
    } else {
      await stopPlayback();
    }
  }

  Future<void> previousTrack() async {
    if (_currentAlbum == null) return;

    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    int prevIndex = _currentTrackIndex - 1;
    while (prevIndex >= 0) {
      if (_currentAlbum!.tracks[prevIndex].hasFile) {
        await playTrack(_currentAlbum!, prevIndex);
        return;
      }
      prevIndex--;
    }

    await _player.seek(Duration.zero);
  }

  Future<void> seekTo(Duration position) => _player.seek(position);

  Future<void> seekToPercent(double percent) async {
    final newPosition = Duration(
      milliseconds: (_duration.inMilliseconds * percent).toInt(),
    );
    await seekTo(newPosition);
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    _currentAlbum = null;
    _currentTrack = null;
    _currentTrackIndex = 0;
    _position = Duration.zero;
    _duration = Duration.zero;
    mediaItem.add(null);
    onChanged?.call();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    onChanged?.call();
  }

  void toggleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        _player.setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        _player.setLoopMode(LoopMode.off);
        break;
    }
    onChanged?.call();
  }

  void _onTrackComplete() {
    if (_loopMode == LoopMode.one) {
      // Powtorzenie obsluguje sam AudioPlayer.
      return;
    }
    nextTrack();
  }

  void setCrossfade(bool enabled) {
    _crossfadeEnabled = enabled;
    onChanged?.call();
  }

  void setCrossfadeDuration(int seconds) {
    _crossfadeDuration = seconds.clamp(1, 10);
    onChanged?.call();
  }

  // ----- Drzewo przegladania dla Android Auto -----

  Album? _findAlbum(String id) {
    if (!Hive.isBoxOpen('albums')) return null;
    final box = Hive.box<Album>('albums');
    for (final a in box.values) {
      if (a.id == id) return a;
    }
    return null;
  }

  ({String albumId, int index})? _parseTrackId(String mediaId) {
    if (!mediaId.startsWith('track/')) return null;
    final parts = mediaId.split('/');
    if (parts.length < 3) return null;
    final index = int.tryParse(parts.last);
    if (index == null) return null;
    // Identyfikator albumu moglby teoretycznie zawierac '/', wiec sklejamy
    // wszystko pomiedzy prefiksem a indeksem.
    final albumId = parts.sublist(1, parts.length - 1).join('/');
    return (albumId: albumId, index: index);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      if (!Hive.isBoxOpen('albums')) return [];
      final box = Hive.box<Album>('albums');
      final albums = box.values
          .where((a) => !a.isWishlist && a.tracks.any((t) => t.hasFile))
          .toList();
      return [
        for (final a in albums)
          MediaItem(
            id: 'album/${a.id}',
            title: a.title,
            artist: a.artist,
            artUri: _albumArtUri(a),
            playable: false,
          ),
      ];
    }

    if (parentMediaId.startsWith('album/')) {
      final albumId = parentMediaId.substring('album/'.length);
      final album = _findAlbum(albumId);
      if (album == null) return [];
      return [
        for (int i = 0; i < album.tracks.length; i++)
          if (album.tracks[i].hasFile) _trackToMediaItem(album, i),
      ];
    }

    return [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final parsed = _parseTrackId(mediaId);
    if (parsed == null) return null;
    final album = _findAlbum(parsed.albumId);
    if (album == null || parsed.index >= album.tracks.length) return null;
    return _trackToMediaItem(album, parsed.index);
  }

  // ----- Overrides sesji medialnej (przyciski w aucie / na ekranie blokady) -----

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => nextTrack();

  @override
  Future<void> skipToPrevious() => previousTrack();

  @override
  Future<void> stop() async {
    await stopPlayback();
    await super.stop();
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final parsed = _parseTrackId(mediaId);
    if (parsed != null) {
      final album = _findAlbum(parsed.albumId);
      if (album != null) await playTrack(album, parsed.index);
      return;
    }
    if (mediaId.startsWith('album/')) {
      final album = _findAlbum(mediaId.substring('album/'.length));
      if (album != null) await playAlbum(album);
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
