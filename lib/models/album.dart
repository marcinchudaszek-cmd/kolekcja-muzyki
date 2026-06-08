import 'package:hive/hive.dart';

part 'album.g.dart';

@HiveType(typeId: 0)
class Album extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String artist;

  @HiveField(2)
  String title;

  @HiveField(3)
  int? year;

  @HiveField(4)
  String genre;

  @HiveField(5)
  String format; // cd, vinyl, digital, cassette

  @HiveField(6)
  int rating; // 1-5

  @HiveField(7)
  String? coverUrl;

  @HiveField(8)
  String? coverPath; // lokalna sciezka do okladki

  @HiveField(9)
  List<Track> tracks;

  @HiveField(10)
  String? notes;

  @HiveField(11)
  bool isFavorite;

  @HiveField(12)
  bool isWishlist;

  @HiveField(13)
  DateTime createdAt;

  Album({
    required this.id,
    required this.artist,
    required this.title,
    this.year,
    this.genre = 'other',
    this.format = 'digital',
    this.rating = 3,
    this.coverUrl,
    this.coverPath,
    List<Track>? tracks,
    this.notes,
    this.isFavorite = false,
    this.isWishlist = false,
    DateTime? createdAt,
  })  : tracks = tracks ?? [],
        createdAt = createdAt ?? DateTime.now();

  // Pobierz okladke (lokalna lub z sieci)
  String? get cover => coverPath ?? coverUrl;

  // Calkowity czas trwania albumu
  Duration get totalDuration {
    int totalSeconds = 0;
    for (var track in tracks) {
      totalSeconds += track.durationSeconds ?? 0;
    }
    return Duration(seconds: totalSeconds);
  }

  // Formatowany czas trwania
  String get formattedDuration {
    final d = totalDuration;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}min';
    }
    return '${d.inMinutes}min';
  }

  // Kopia albumu z nowymi wartosciami
  Album copyWith({
    String? id,
    String? artist,
    String? title,
    int? year,
    String? genre,
    String? format,
    int? rating,
    String? coverUrl,
    String? coverPath,
    List<Track>? tracks,
    String? notes,
    bool? isFavorite,
    bool? isWishlist,
  }) {
    return Album(
      id: id ?? this.id,
      artist: artist ?? this.artist,
      title: title ?? this.title,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      format: format ?? this.format,
      rating: rating ?? this.rating,
      coverUrl: coverUrl ?? this.coverUrl,
      coverPath: coverPath ?? this.coverPath,
      tracks: tracks ?? this.tracks,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
      isWishlist: isWishlist ?? this.isWishlist,
      createdAt: createdAt,
    );
  }
}

@HiveType(typeId: 1)
class Track extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  String? filePath; // SCIEZKA DO PLIKU NA TELEFONIE!

  @HiveField(2)
  int? durationSeconds;

  @HiveField(3)
  int trackNumber;

  Track({
    required this.title,
    this.filePath,
    this.durationSeconds,
    this.trackNumber = 0,
  });

  // Formatowany czas trwania
  String get formattedDuration {
    if (durationSeconds == null) return '';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // Czy utwor ma plik do odtworzenia
  bool get hasFile => filePath != null && filePath!.isNotEmpty;
}

// Mapowanie gatunkow
String mapGenre(String? genre) {
  if (genre == null) return 'other';
  final g = genre.toLowerCase();
  if (g.contains('rock')) return 'rock';
  if (g.contains('pop')) return 'pop';
  if (g.contains('metal')) return 'metal';
  if (g.contains('jazz')) return 'jazz';
  if (g.contains('classical') || g.contains('klasycz')) return 'classical';
  if (g.contains('electronic') || g.contains('elektro')) return 'electronic';
  if (g.contains('hip') || g.contains('rap')) return 'hip-hop';
  if (g.contains('blues')) return 'blues';
  if (g.contains('country')) return 'country';
  if (g.contains('reggae')) return 'reggae';
  if (g.contains('soul') || g.contains('r&b')) return 'soul';
  if (g.contains('punk')) return 'punk';
  if (g.contains('folk')) return 'folk';
  if (g.contains('disco')) return 'disco';
  return 'other';
}

// Emoji dla gatunkow
String genreEmoji(String genre) {
  switch (genre) {
    case 'rock': return '🎸';
    case 'pop': return '🎤';
    case 'metal': return '🤘';
    case 'jazz': return '🎷';
    case 'classical': return '🎻';
    case 'electronic': return '🎹';
    case 'hip-hop': return '🎧';
    case 'blues': return '🎺';
    case 'country': return '🤠';
    case 'reggae': return '🌴';
    case 'soul': return '💜';
    case 'punk': return '⚡';
    case 'folk': return '🪕';
    case 'disco': return '🪩';
    default: return '🎵';
  }
}

// Nazwa gatunku po polsku
String genreName(String genre) {
  switch (genre) {
    case 'rock': return 'Rock';
    case 'pop': return 'Pop';
    case 'metal': return 'Metal';
    case 'jazz': return 'Jazz';
    case 'classical': return 'Klasyczna';
    case 'electronic': return 'Elektroniczna';
    case 'hip-hop': return 'Hip-Hop';
    case 'blues': return 'Blues';
    case 'country': return 'Country';
    case 'reggae': return 'Reggae';
    case 'soul': return 'Soul/R&B';
    case 'punk': return 'Punk';
    case 'folk': return 'Folk';
    case 'disco': return 'Disco';
    default: return 'Inne';
  }
}
