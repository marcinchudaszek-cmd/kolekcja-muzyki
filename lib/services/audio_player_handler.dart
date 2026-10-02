import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediastore_resolver/mediastore_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    _playerA = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]),
    );
    _playerB = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB]),
    );
    _init();
    unawaited(_loadSettings().then((_) => _restoreSession(autoplay: false)));
  }

  /// Equalizer sterowany z UI (nalezy do gracza A) oraz jego kopia dla gracza B.
  /// Ustawienia sa lustrzane — patrz [setEqualizerBandGain] / [_syncEqualizerTo].
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidEqualizer _equalizerB = AndroidEqualizer();
  final Random _random = Random();

  /// Crossfade wymaga nakladania sie dwoch utworow, wiec dwoch odtwarzaczy.
  /// [_player] to ten, ktory aktualnie "jest" biezacym utworem;
  /// [_standby] to drugi — uzywany do przygotowania nastepnego utworu.
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;
  bool _useA = true;
  AudioPlayer get _player => _useA ? _playerA : _playerB;
  AudioPlayer get _standby => _useA ? _playerB : _playerA;
  AndroidEqualizer get _standbyEqualizer => _useA ? _equalizerB : _equalizer;

  /// Wywolywane przy kazdej zmianie stanu — fasada podpina tu notifyListeners.
  VoidCallback? onChanged;

  /// Callback do zapisu historii odtwarzania (uzywany przez HomeScreen).
  void Function(String albumId, String trackTitle, int durationSeconds)?
      onTrackPlayed;

  /// Etykiety drzewa Android Auto. Ustawiane z UI, bo handler nie ma dostepu
  /// do tlumaczen (dziala poza drzewem widgetow). Wartosci domyslne zostaja,
  /// gdy aplikacje uruchomil sam Android Auto — bez UI.
  String autoAlbumsLabel = 'Albumy';
  String autoArtistsLabel = 'Wykonawcy';
  String randomAlbumLabel = 'Losowo';
  String autoPlayRandomAlbumLabel = 'Zagraj losowy album';
  String autoPlayRandomArtistLabel = 'Zagraj losowego wykonawcę';

  /// Zamienia surowa sciezke pliku na content:// URI z MediaStore.
  /// Fasada podmienia go na wersje z dodatkowym fallbackiem. Bez fasady
  /// (start z Android Auto: jest tylko serwis, UI nie powstaje) dziala
  /// [_resolveUri] — wczesniej wtedy nie bylo zadnego resolvera i odtwarzanie
  /// w aucie konczylo sie bledem EACCES na Androidzie 13+.
  Future<String?> Function(String path)? resolveUri;

  Future<String?> _resolveUri(String path) async {
    final custom = resolveUri;
    if (custom != null) return custom(path);
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await MediastoreResolver.uriForPath(path);
    } catch (e) {
      debugPrint('MediaStore resolver nieudany: $e');
      return null;
    }
  }

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

  // Android Auto: w trakcie zmiany utworu odtwarzacz przechodzi przez stan
  // idle, ktory AA interpretuje jako "koniec odtwarzania" i zamyka ekran
  // now-playing. Ten flag pozwala zamiast idle raportowac loading.
  bool _switchingTrack = false;
  // Id albumu, dla ktorego opublikowano kolejke - unikamy ponownej publikacji
  // przy zmianie utworu w tym samym albumie (AA rebuildowaloby widok).
  String? _queueAlbumId;

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
    // Subskrybujemy OBA odtwarzacze, ale reagujemy tylko na ten aktywny —
    // drugi w tle przygotowuje/dogrywa utwor podczas crossfade.
    for (final p in [_playerA, _playerB]) {
      p.playbackEventStream.listen((event) {
        if (!identical(p, _player)) return;
        _broadcastState(event);
      });

      p.playerStateStream.listen((state) {
        if (!identical(p, _player)) return;
        _isLoading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        // Pauza = dobry moment na zapis miejsca do wznowienia.
        if (!state.playing && _wasPlaying) _saveSession();
        _wasPlaying = state.playing;
        onChanged?.call();
      });

      p.positionStream.listen((pos) {
        if (!identical(p, _player)) return;
        _position = pos;
        onChanged?.call();
        _maybeStartCrossfade();
        _maybeSaveProgress();
      });

      p.durationStream.listen((dur) {
        if (!identical(p, _player)) return;
        _duration = dur ?? Duration.zero;
        onChanged?.call();
      });

      // Automatyczne przejscie do nastepnego utworu.
      p.processingStateStream.listen((state) {
        if (!identical(p, _player)) return;
        if (state == ProcessingState.completed) {
          // Przy crossfade nastepny utwor juz gra — nie przeskakuj drugi raz.
          if (_crossfading) return;
          _onTrackComplete();
        }
      });
    }
  }

  // ----- Ustawienia trwale -----

  static const _prefsCrossfadeEnabled = 'crossfade_enabled';
  static const _prefsCrossfadeDuration = 'crossfade_duration';
  static const _prefsShuffle = 'shuffle_enabled';
  static const _prefsLastAlbum = 'last_album_id';
  static const _prefsLastTrack = 'last_track_index';
  static const _prefsLastPosition = 'last_position_ms';

  SharedPreferences? _prefs;

  Future<void> _loadSettings() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _crossfadeEnabled = prefs.getBool(_prefsCrossfadeEnabled) ?? false;
      _crossfadeDuration = prefs.getInt(_prefsCrossfadeDuration) ?? 3;
      _shuffle = prefs.getBool(_prefsShuffle) ?? false;
      onChanged?.call();
    } catch (e) {
      debugPrint('Nie udalo sie wczytac ustawien odtwarzania: $e');
    }
  }

  // ----- Wznawianie od ostatniego miejsca -----

  bool _wasPlaying = false;
  Duration _lastSavedPosition = Duration.zero;

  /// Zapisuje album, utwor i pozycje — z tego [_restoreSession] wznawia
  /// odtwarzanie po ponownym uruchomieniu (takze w Android Auto).
  void _saveSession({Duration? position}) {
    final prefs = _prefs;
    final album = _currentAlbum;
    if (prefs == null || album == null || _switchingTrack) return;
    final pos = position ?? _player.position;
    _lastSavedPosition = pos;
    unawaited(prefs.setString(_prefsLastAlbum, album.id));
    unawaited(prefs.setInt(_prefsLastTrack, _currentTrackIndex));
    unawaited(prefs.setInt(_prefsLastPosition, pos.inMilliseconds));
  }

  /// Podczas grania zapisuj co ~5 s, zeby nagle ubicie procesu (wylaczenie
  /// auta, brak baterii) nie cofalo wznowienia o caly utwor.
  void _maybeSaveProgress() {
    if (!_player.playing || _switchingTrack || _crossfading) return;
    if ((_position - _lastSavedPosition).abs() >= const Duration(seconds: 5)) {
      _saveSession(position: _position);
    }
  }

  ({String albumId, int index, Duration position})? _savedSession() {
    final prefs = _prefs;
    final albumId = prefs?.getString(_prefsLastAlbum);
    if (prefs == null || albumId == null) return null;
    return (
      albumId: albumId,
      index: prefs.getInt(_prefsLastTrack) ?? 0,
      position: Duration(milliseconds: prefs.getInt(_prefsLastPosition) ?? 0),
    );
  }

  /// Laduje ostatnio grany utwor w miejscu, w ktorym go przerwano.
  /// [autoplay] = false tylko przygotowuje (aplikacja/auto pokazuje utwor,
  /// "graj" rusza od zapamietanego miejsca). Zwraca false, gdy nie ma czego
  /// wznowic (brak zapisu, album usuniety, plik niedostepny).
  Future<bool> _restoreSession({required bool autoplay}) async {
    if (_currentAlbum != null) {
      if (autoplay && !_player.playing) unawaited(_player.play());
      return true;
    }
    _prefs ??= await SharedPreferences.getInstance();
    final saved = _savedSession();
    if (saved == null) return false;
    final album = _findAlbum(saved.albumId);
    if (album == null || album.isWishlist) return false;

    var index = saved.index;
    var position = saved.position;
    if (index < 0 || index >= album.tracks.length ||
        !album.tracks[index].hasFile) {
      index = album.tracks.indexWhere((t) => t.hasFile);
      position = Duration.zero;
      if (index < 0) return false;
    }
    // Uzytkownik zdazyl cos wlaczyc, zanim wczytalismy zapis — nie nadpisuj.
    if (_currentAlbum != null) return true;
    final myGeneration = _playGeneration + 1;
    try {
      await playTrack(album, index, startAt: position, autoplay: autoplay);
      return true;
    } catch (e) {
      debugPrint('Wznowienie ostatniej sesji nieudane: $e');
      // Nie zostawiaj "wiszacego" utworu, ktorego nie da sie odtworzyc —
      // chyba ze w miedzyczasie uzytkownik wlaczyl cos innego.
      if (_playGeneration == myGeneration) {
        _currentAlbum = null;
        _currentTrack = null;
        _queueAlbumId = null;
        mediaItem.add(null);
        onChanged?.call();
      }
      return false;
    }
  }

  // ----- Equalizer (lustrzany na obu odtwarzaczach) -----

  /// Kopiuje ustawienia equalizera z gracza A na wskazany equalizer, zeby
  /// po crossfade brzmienie sie nie zmienilo.
  Future<void> _syncEqualizerTo(AndroidEqualizer target) async {
    // Limit czasu jest tu zabezpieczeniem, a nie ostroznoscia: `parameters`
    // nie konczy sie, dopoki odtwarzacz nie zostanie aktywowany, wiec bez
    // niego jedno zawieszenie zablokowaloby crossfade do konca sesji.
    const limit = Duration(seconds: 3);
    try {
      await target.setEnabled(_equalizer.enabled);
      final src = await _equalizer.parameters.timeout(limit);
      final dst = await target.parameters.timeout(limit);
      for (int i = 0; i < src.bands.length && i < dst.bands.length; i++) {
        await dst.bands[i].setGain(src.bands[i].gain);
      }
    } on TimeoutException {
      // Brzmienie moze sie chwilowo roznic, ale przejscie ma sie odbyc.
      debugPrint('Sync equalizera: przekroczony czas — pomijam');
    } catch (e) {
      debugPrint('Sync equalizera nieudany: $e');
    }
  }

  /// Wlacza/wylacza equalizer na obu odtwarzaczach.
  Future<void> setEqualizerEnabled(bool enabled) async {
    await _equalizer.setEnabled(enabled);
    await _equalizerB.setEnabled(enabled);
  }

  /// Ustawia wzmocnienie pasma na obu odtwarzaczach (UI podaje indeks pasma).
  Future<void> setEqualizerBandGain(int index, double gain) async {
    for (final eq in [_equalizer, _equalizerB]) {
      try {
        final params = await eq.parameters;
        if (index < params.bands.length) {
          await params.bands[index].setGain(gain);
        }
      } catch (e) {
        debugPrint('Ustawienie pasma equalizera nieudane: $e');
      }
    }
  }

  // ----- Crossfade -----

  Timer? _fadeTimer;
  bool _crossfading = false;

  /// Ktory utwor pojdzie jako nastepny (respektuje shuffle i tryb powtarzania).
  /// Wspoldzielone przez [nextTrack] i crossfade, zeby oba szly tak samo.
  int? _nextIndex() {
    final album = _currentAlbum;
    if (album == null) return null;
    final playable = _playableIndexes;
    if (playable.isEmpty) return null;

    if (_shuffle) {
      if (playable.length == 1) return playable.first;
      final candidates =
          playable.where((i) => i != _currentTrackIndex).toList();
      return candidates[_random.nextInt(candidates.length)];
    }

    for (int i = _currentTrackIndex + 1; i < album.tracks.length; i++) {
      if (album.tracks[i].hasFile) return i;
    }
    if (_loopMode == LoopMode.all) return playable.first;
    return null;
  }

  /// Odpala crossfade gdy do konca utworu zostalo tyle, ile trwa przejscie.
  void _maybeStartCrossfade() {
    if (!_crossfadeEnabled || _crossfading) return;
    if (_loopMode == LoopMode.one) return;
    if (!_player.playing) return;

    final total = _player.duration;
    if (total == null) return;
    // Utwor krotszy niz samo przejscie — crossfade nie ma sensu.
    if (total.inMilliseconds <= (_crossfadeDuration + 1) * 1000) return;

    final remaining = total - _position;
    if (remaining.inMilliseconds <= 0) return;
    if (remaining.inMilliseconds > _crossfadeDuration * 1000) return;

    final next = _nextIndex();
    if (next == null) return;
    unawaited(_startCrossfade(next));
  }

  Future<void> _startCrossfade(int nextIndex) async {
    final album = _currentAlbum;
    if (album == null || _crossfading) return;
    _crossfading = true;

    final from = _player;
    final to = _standby;

    try {
      await to.setVolume(0);
      // KOLEJNOSC JEST KRYTYCZNA: efekty dzwiekowe (equalizer) sa w just_audio
      // aktywowane dopiero, gdy odtwarzacz dostanie zrodlo. Jego `parameters`
      // to Completer wypelniany wlasnie przy tej aktywacji — synchronizacja
      // equalizera PRZED setAudioSource czekala w nieskonczonosc na odtwarzacz,
      // ktory nigdy nie zostal aktywowany, i cicho zabijala crossfade na cala
      // sesje (flaga _crossfading zostawala podniesiona).
      await to.setAudioSource(await _audioSourceFor(album.tracks[nextIndex]));
      await _syncEqualizerTo(_standbyEqualizer);
      // Jeszcze raz na zero — gdyby zaladowanie zrodla przywrocilo glosnosc,
      // nastepny utwor wystartowalby na pelnej zamiast wchodzic lagodnie.
      await to.setVolume(0);
      unawaited(to.play());
    } catch (e) {
      debugPrint('Crossfade — nie udalo sie przygotowac nastepnego utworu: $e');
      _crossfading = false;
      try {
        await to.stop();
      } catch (_) {}
      await to.setVolume(1.0);
      return;
    }

    const stepMs = 60;
    final steps = ((_crossfadeDuration * 1000) / stepMs).round().clamp(1, 2000);
    int step = 0;
    bool busy = false;

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) async {
      if (busy) return; // nie nakladaj wywolan setVolume
      busy = true;
      try {
        step++;
        final p = (step / steps).clamp(0.0, 1.0);
        await from.setVolume(1.0 - p);
        await to.setVolume(p);
        if (p >= 1.0) {
          t.cancel();
          await _finishCrossfade(from, to, nextIndex);
        }
      } catch (e) {
        debugPrint('Crossfade — blad przejscia: $e');
        t.cancel();
        await _finishCrossfade(from, to, nextIndex);
      } finally {
        busy = false;
      }
    });
  }

  Future<void> _finishCrossfade(
      AudioPlayer from, AudioPlayer to, int index) async {
    _fadeTimer?.cancel();
    _fadeTimer = null;

    final album = _currentAlbum;
    // Przelacz aktywny odtwarzacz na ten, ktory teraz gra.
    _useA = identical(to, _playerA);
    _currentTrackIndex = index;
    _currentTrack = (album != null && index < album.tracks.length)
        ? album.tracks[index]
        : null;

    await to.setVolume(1.0);
    try {
      await from.stop();
    } catch (_) {}
    await from.setVolume(1.0);

    // Odswiez stan z nowego aktywnego gracza — jego zdarzenia duration/position
    // byly odfiltrowane, dopoki gral w tle.
    _duration = to.duration ?? Duration.zero;
    _position = to.position;
    _isLoading = false;

    _crossfading = false;

    if (album != null && _currentTrack != null) {
      mediaItem.add(_trackToMediaItem(album, index, duration: to.duration));
      onTrackPlayed?.call(
        album.id,
        _currentTrack!.title,
        _currentTrack!.durationSeconds ?? 0,
      );
    }
    _broadcastState();
    onChanged?.call();
  }

  /// Przerywa trwajace przejscie (np. gdy user sam zmieni utwor).
  Future<void> _cancelCrossfade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (!_crossfading) {
      await _player.setVolume(1.0);
      return;
    }
    _crossfading = false;
    final standby = _standby;
    try {
      await standby.stop();
    } catch (_) {}
    await standby.setVolume(1.0);
    await _player.setVolume(1.0);
  }

  void _broadcastState([PlaybackEvent? event]) {
    final playing = _player.playing;
    final raw = _player.processingState;
    // W trakcie przelaczania utworu nie raportuj idle (AA zamkneloby ekran).
    final processingState = (_switchingTrack && raw == ProcessingState.idle)
        ? AudioProcessingState.loading
        : const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[raw]!;
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
        // Bez ogloszenia tych akcji Android Auto nie udostepnia wyszukiwania
        // (ani wyszukiwania glosowego "zagraj ...").
        MediaAction.playFromSearch,
        MediaAction.playFromMediaId,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentTrackIndex,
    ));
  }

  // ----- Metadane / okladki -----

  Uri? _albumArtUri(Album album) {
    // Preferuj URL sieciowy — Android Auto dziala w osobnym procesie i nie
    // odczyta lokalnego file://. Sciezka lokalna zostaje jako fallback (dziala
    // w powiadomieniu / na ekranie blokady tego samego procesu).
    final url = album.coverUrl;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) return uri;
    }
    final path = album.coverPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Uri.file(path);
    }
    return null;
  }

  MediaItem _trackToMediaItem(Album album, int index, {Duration? duration}) {
    final t = album.tracks[index];
    return MediaItem(
      id: 'track/${album.id}/$index',
      title: t.title,
      album: album.title,
      artist: album.artist,
      duration: duration ??
          (t.durationSeconds != null && t.durationSeconds! > 0
              ? Duration(seconds: t.durationSeconds!)
              : null),
      artUri: _albumArtUri(album),
      playable: true,
    );
  }

  /// Buduje zrodlo audio dla utworu. Preferuje content:// URI (dziala z
  /// uprawnieniem READ_MEDIA_AUDIO na Androidzie 13+); surowa sciezka pliku
  /// jest tylko fallbackiem dla plikow w prywatnej pamieci aplikacji.
  Future<AudioSource> _audioSourceFor(Track track) async {
    final path = track.filePath!;
    // content:// (Android MediaStore), blob: (import z dysku na web) i http(s)
    // sa juz gotowymi URI - nie mapuj ich.
    if (path.startsWith('content://') ||
        path.startsWith('blob:') ||
        path.startsWith('http')) {
      return AudioSource.uri(Uri.parse(path));
    }
    // Mapuj surowa sciezke na content:// URI (wymagane na Androidzie 10+).
    final resolved = await _resolveUri(path);
    if (resolved != null && resolved.isNotEmpty) {
      return AudioSource.uri(Uri.parse(resolved));
    }
    // Fallback dla plikow w prywatnej pamieci aplikacji.
    return AudioSource.uri(Uri.file(path));
  }

  // ----- Sterowanie odtwarzaniem (uzywane przez fasade i UI) -----

  /// Licznik wywolan [playTrack] — pozwala rozpoznac, czy blad dotyczy
  /// nadal biezacego utworu, czy juz zostal "przykryty" nowszym wyborem.
  int _playGeneration = 0;

  /// [startAt] — pozycja startowa (wznowienie). [autoplay] = false tylko
  /// laduje utwor w pauzie.
  Future<void> playTrack(
    Album album,
    int trackIndex, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    if (trackIndex < 0 || trackIndex >= album.tracks.length) return;

    final track = album.tracks[trackIndex];
    if (!track.hasFile) {
      throw Exception('Brak pliku dla tego utworu');
    }
    _playGeneration++;

    // Reczne uruchomienie utworu przerywa trwajace przejscie i przywraca
    // pelna glosnosc (crossfade mogl zostawic gracza wyciszonego).
    await _cancelCrossfade();

    _currentAlbum = album;
    _currentTrackIndex = trackIndex;
    _currentTrack = track;
    _isLoading = true;
    _switchingTrack = true;
    onChanged?.call();

    // Kolejke publikuj tylko przy zmianie albumu (nie przy kazdym utworze —
    // AA rebuildowaloby wtedy caly widok now-playing).
    if (_queueAlbumId != album.id) {
      queue.add([
        for (int i = 0; i < album.tracks.length; i++)
          _trackToMediaItem(album, i),
      ]);
      _queueAlbumId = album.id;
    }
    mediaItem.add(_trackToMediaItem(album, trackIndex));

    try {
      final loaded = await _player.setAudioSource(
        await _audioSourceFor(track),
        initialPosition: startAt,
      );
      _switchingTrack = false;
      // Ustaw realny czas trwania (skan folderu daje 0s) — dzieki temu
      // Android Auto pokazuje poprawny pasek postepu.
      if (loaded != null) {
        mediaItem.add(_trackToMediaItem(album, trackIndex, duration: loaded));
      }
      _isLoading = false;
      _saveSession(position: startAt ?? Duration.zero);
      _broadcastState();
      onChanged?.call();
      if (!autoplay) return;
      // UWAGA: na Androidzie Future z play() konczy sie dopiero przy koncu
      // utworu (STATE_ENDED), nie przy starcie odtwarzania. Awaitowanie go
      // wstrzymywalo kod wywolujacy (nawigacje, historie) do konca utworu,
      // a przerwanie przez "nastepny" odpalalo te zalegle kontynuacje
      // w losowych momentach (np. zdejmowalo ekran odtwarzacza).
      unawaited(_player.play());
      onTrackPlayed?.call(album.id, track.title, track.durationSeconds ?? 0);
    } catch (e) {
      debugPrint('Blad odtwarzania: $e');
      _isLoading = false;
      _switchingTrack = false;
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
      // play() konczy sie dopiero na koncu utworu - nie czekaj (patrz playTrack).
      unawaited(_player.play());
      if (_currentAlbum != null && _currentTrack != null) {
        onTrackPlayed?.call(
          _currentAlbum!.id,
          _currentTrack!.title,
          _currentTrack!.durationSeconds ?? 0,
        );
      }
    }
  }

  /// Indeksy utworow z plikiem — baza dla losowania.
  List<int> get _playableIndexes {
    final album = _currentAlbum;
    if (album == null) return const [];
    return [
      for (int i = 0; i < album.tracks.length; i++)
        if (album.tracks[i].hasFile) i,
    ];
  }

  Future<void> nextTrack() async {
    final album = _currentAlbum;
    if (album == null) return;

    // Reczna zmiana utworu przerywa trwajace przejscie.
    await _cancelCrossfade();

    final next = _nextIndex();
    if (next == null) {
      // Koniec albumu i brak powtarzania. Wznowienie zacznie album od
      // poczatku, a nie od ostatnich sekund ostatniego utworu.
      final first = album.tracks.indexWhere((t) => t.hasFile);
      _currentTrackIndex = first < 0 ? 0 : first;
      _saveSession(position: Duration.zero);
      await stopPlayback(saveSession: false);
      return;
    }
    await playTrack(album, next);
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

  Future<void> stopPlayback({bool saveSession = true}) async {
    if (saveSession) _saveSession();
    await _cancelCrossfade();
    await _player.stop();
    _currentAlbum = null;
    _currentTrack = null;
    _currentTrackIndex = 0;
    _queueAlbumId = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    mediaItem.add(null);
    onChanged?.call();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    onChanged?.call();
    unawaited(_persist((p) => p.setBool(_prefsShuffle, _shuffle)));
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

  bool _autoAdvancing = false;

  Future<void> _onTrackComplete() async {
    if (_loopMode == LoopMode.one) {
      // Powtorzenie obsluguje sam AudioPlayer.
      return;
    }
    // Guard: stream stanu moze wyemitowac "completed" wielokrotnie zanim
    // nowe zrodlo sie zaladuje - nie odpalaj auto-next rownolegle.
    if (_autoAdvancing) return;
    _autoAdvancing = true;
    try {
      await nextTrack();
    } catch (e) {
      // Bez catcha jeden blad (rethrow z playTrack) zabijalby auto-next
      // na zawsze - wyjatek w listenerze streamu jest nieobslugiwany.
      debugPrint('Blad auto-next: $e');
    } finally {
      _autoAdvancing = false;
    }
  }

  void setCrossfade(bool enabled) {
    _crossfadeEnabled = enabled;
    onChanged?.call();
    unawaited(_persist((p) => p.setBool(_prefsCrossfadeEnabled, enabled)));
    if (!enabled) unawaited(_cancelCrossfade());
  }

  void setCrossfadeDuration(int seconds) {
    _crossfadeDuration = seconds.clamp(1, 10);
    onChanged?.call();
    unawaited(
        _persist((p) => p.setInt(_prefsCrossfadeDuration, _crossfadeDuration)));
  }

  Future<void> _persist(Future<void> Function(SharedPreferences) write) async {
    try {
      write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('Zapis ustawien odtwarzania nieudany: $e');
    }
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

  // Identyfikatory wezlow drzewa Android Auto.
  static const _tabAlbums = 'tab/albums';
  static const _tabRandom = 'tab/random';
  static const _tabArtists = 'tab/artists';
  static const _randomAlbumId = 'random';
  static const _randomArtistId = 'random/artist';

  // Wskazowki stylu z biblioteki androidx.media (1 = lista, 2 = siatka).
  static const _browsableHint =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const _playableHint = 'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const _styleList = 1;
  static const _styleGrid = 2;

  static int _byArtistThenTitle(Album a, Album b) {
    final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    return byArtist != 0
        ? byArtist
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  MediaItem _albumItem(Album a) => MediaItem(
        id: 'album/${a.id}',
        title: a.title,
        artist: a.artist,
        artUri: _albumArtUri(a),
        playable: false,
      );

  /// Wykonawcy z kolekcji (bez rozrozniania wielkosci liter) -> ich albumy.
  Map<String, List<Album>> _albumsByArtist() {
    final map = <String, List<Album>>{};
    for (final a in _browsableAlbums()) {
      final name = a.artist.trim();
      if (name.isEmpty) continue;
      map.putIfAbsent(name.toLowerCase(), () => []).add(a);
    }
    return map;
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    // Root = zakladki. Android Auto NIE pokazuje odtwarzalnych pozycji
    // w korzeniu (dopuszcza tylko katalogi), dlatego dawna pozycja "Losowo"
    // obok siatki albumow byla w aucie niewidoczna.
    if (parentMediaId == AudioService.browsableRootId) {
      if (_browsableAlbums().isEmpty) return [];
      return [
        MediaItem(
          id: _tabAlbums,
          title: autoAlbumsLabel,
          playable: false,
          extras: const {_browsableHint: _styleGrid},
        ),
        MediaItem(
          id: _tabRandom,
          title: randomAlbumLabel,
          playable: false,
          extras: const {_browsableHint: _styleGrid, _playableHint: _styleList},
        ),
        MediaItem(
          id: _tabArtists,
          title: autoArtistsLabel,
          playable: false,
          extras: const {_browsableHint: _styleList},
        ),
      ];
    }

    // "Ostatnio grane" — o to pyta system (wznawianie multimediow w Androidzie
    // 11+ i karta odtwarzacza): jeden utwor, od ktorego wznowic.
    if (parentMediaId == AudioService.recentRootId) {
      final current = _currentAlbum;
      if (current != null && _currentTrackIndex < current.tracks.length) {
        return [_trackToMediaItem(current, _currentTrackIndex)];
      }
      _prefs ??= await SharedPreferences.getInstance();
      final saved = _savedSession();
      final album = saved == null ? null : _findAlbum(saved.albumId);
      if (saved == null || album == null) return [];
      if (saved.index >= 0 &&
          saved.index < album.tracks.length &&
          album.tracks[saved.index].hasFile) {
        return [_trackToMediaItem(album, saved.index)];
      }
      return [];
    }

    if (parentMediaId == _tabAlbums) {
      final albums = _browsableAlbums()..sort(_byArtistThenTitle);
      return [for (final a in albums) _albumItem(a)];
    }

    if (parentMediaId == _tabRandom) {
      final albums = _browsableAlbums()..shuffle(_random);
      return [
        MediaItem(
          id: _randomAlbumId,
          title: autoPlayRandomAlbumLabel,
          playable: true,
        ),
        MediaItem(
          id: _randomArtistId,
          title: autoPlayRandomArtistLabel,
          playable: true,
        ),
        // Propozycje do wejscia — przy kazdym otwarciu inne.
        for (final a in albums.take(12)) _albumItem(a),
      ];
    }

    if (parentMediaId == _tabArtists) {
      final byArtist = _albumsByArtist();
      final keys = byArtist.keys.toList()..sort();
      return [
        for (final k in keys)
          MediaItem(
            id: 'artist/${Uri.encodeComponent(k)}',
            title: byArtist[k]!.first.artist.trim(),
            artUri: _albumArtUri(byArtist[k]!.first),
            playable: false,
            extras: const {_browsableHint: _styleGrid},
          ),
      ];
    }

    if (parentMediaId.startsWith('artist/')) {
      final key =
          Uri.decodeComponent(parentMediaId.substring('artist/'.length));
      final albums = (_albumsByArtist()[key] ?? [])..sort(_byArtistThenTitle);
      return [for (final a in albums) _albumItem(a)];
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

  // ----- Wyszukiwanie (Android Auto: pole szukania i komendy glosowe) -----

  /// Polskie/niemieckie znaki diakrytyczne -> podstawowe, zeby "zaba"
  /// znajdowalo "Żaba", a "rozni" — "Różni".
  static const _diacritics = <String, String>{
    'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o',
    'ś': 's', 'ź': 'z', 'ż': 'z',
    'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
    'á': 'a', 'é': 'e', 'í': 'i', 'ú': 'u', 'à': 'a', 'è': 'e',
    'ì': 'i', 'ò': 'o', 'ù': 'u', 'â': 'a', 'ê': 'e', 'î': 'i',
    'ô': 'o', 'û': 'u', 'ç': 'c', 'ñ': 'n',
  };

  static String _fold(String s) {
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      buf.write(_diacritics[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Albumy nadajace sie do odtwarzania (bez listy zyczen, z plikami).
  List<Album> _browsableAlbums() {
    if (!Hive.isBoxOpen('albums')) return [];
    return Hive.box<Album>('albums')
        .values
        .where((a) => !a.isWishlist && a.tracks.any((t) => t.hasFile))
        .toList();
  }

  /// Wlacza losowy album z kolekcji (uzywane przez Android Auto i UI).
  Future<void> playRandomAlbum() async {
    final albums = _browsableAlbums();
    if (albums.isEmpty) return;
    await playAlbum(albums[_random.nextInt(albums.length)]);
  }

  /// Losowy wykonawca, a z jego dyskografii losowy album. Inny rozklad niz
  /// [playRandomAlbum]: wykonawca z jednym albumem ma te same szanse co ten
  /// z dwudziestoma.
  Future<void> playRandomArtist() async {
    final byArtist = _albumsByArtist().values.toList();
    if (byArtist.isEmpty) return;
    final albums = byArtist[_random.nextInt(byArtist.length)];
    await playAlbum(albums[_random.nextInt(albums.length)]);
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final q = _fold(query.trim());
    // Puste zapytanie (np. "wlacz muzyke") — pokaz cala kolekcje.
    if (q.isEmpty) return getChildren(_tabAlbums);

    final albums = _browsableAlbums();
    final albumHits = <Album>[];
    final trackHits = <MediaItem>[];

    for (final a in albums) {
      final artistMatch = _fold(a.artist).contains(q);
      if (artistMatch || _fold(a.title).contains(q)) {
        albumHits.add(a);
      }

      if (trackHits.length < 80) {
        for (int i = 0; i < a.tracks.length; i++) {
          final t = a.tracks[i];
          if (!t.hasFile) continue;
          if (_fold(t.title).contains(q)) {
            trackHits.add(_trackToMediaItem(a, i));
            if (trackHits.length >= 80) break;
          }
        }
      }
    }

    albumHits.sort(_byArtistThenTitle);

    return [
      // Najpierw albumy/wykonawcy (do wejscia), potem konkretne utwory.
      for (final a in albumHits.take(40)) _albumItem(a),
      ...trackHits,
    ];
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final results = await search(query, extras);
    if (results.isEmpty) return;

    // Preferuj konkretny utwor (zagra od razu); inaczej pierwszy album.
    final track = results.where((m) => m.playable == true);
    final chosen = track.isNotEmpty ? track.first : results.first;
    await playFromMediaId(chosen.id, extras);
  }

  @override
  Future<void> prepareFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) =>
      playFromSearch(query, extras);

  // ----- Overrides sesji medialnej (przyciski w aucie / na ekranie blokady) -----

  /// "Graj" z auta / sluchawek / ekranu blokady. Gdy nic nie jest
  /// zaladowane (np. swiezy start z Android Auto) — wznow ostatnie miejsce,
  /// a jesli nie ma czego wznowic, zagraj losowy album.
  @override
  Future<void> play() async {
    if (_currentAlbum == null) {
      if (await _restoreSession(autoplay: true)) return;
      await playRandomAlbum();
      return;
    }
    unawaited(_player.play());
  }

  /// Android Auto / system przygotowuje odtwarzanie (bez startu).
  @override
  Future<void> prepare() async {
    await _restoreSession(autoplay: false);
  }

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
    if (mediaId == _randomAlbumId) {
      await playRandomAlbum();
      return;
    }
    if (mediaId == _randomArtistId) {
      await playRandomArtist();
      return;
    }
    final parsed = _parseTrackId(mediaId);
    if (parsed != null) {
      final album = _findAlbum(parsed.albumId);
      if (album == null) return;
      // Utwor z "ostatnio grane" — wznow od zapamietanego miejsca.
      final saved = _savedSession();
      final resume = saved != null &&
          saved.albumId == parsed.albumId &&
          saved.index == parsed.index;
      await playTrack(album, parsed.index,
          startAt: resume ? saved.position : null);
      return;
    }
    if (mediaId.startsWith('album/')) {
      final album = _findAlbum(mediaId.substring('album/'.length));
      if (album != null) await playAlbum(album);
    }
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    await _playerA.dispose();
    await _playerB.dispose();
  }
}
