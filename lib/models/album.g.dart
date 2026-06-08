// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AlbumAdapter extends TypeAdapter<Album> {
  @override
  final int typeId = 0;

  @override
  Album read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Album(
      id: fields[0] as String,
      artist: fields[1] as String,
      title: fields[2] as String,
      year: fields[3] as int?,
      genre: fields[4] as String,
      format: fields[5] as String,
      rating: fields[6] as int,
      coverUrl: fields[7] as String?,
      coverPath: fields[8] as String?,
      tracks: (fields[9] as List).cast<Track>(),
      notes: fields[10] as String?,
      isFavorite: fields[11] as bool,
      isWishlist: fields[12] as bool,
      createdAt: fields[13] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Album obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.artist)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.year)
      ..writeByte(4)
      ..write(obj.genre)
      ..writeByte(5)
      ..write(obj.format)
      ..writeByte(6)
      ..write(obj.rating)
      ..writeByte(7)
      ..write(obj.coverUrl)
      ..writeByte(8)
      ..write(obj.coverPath)
      ..writeByte(9)
      ..write(obj.tracks)
      ..writeByte(10)
      ..write(obj.notes)
      ..writeByte(11)
      ..write(obj.isFavorite)
      ..writeByte(12)
      ..write(obj.isWishlist)
      ..writeByte(13)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TrackAdapter extends TypeAdapter<Track> {
  @override
  final int typeId = 1;

  @override
  Track read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Track(
      title: fields[0] as String,
      filePath: fields[1] as String?,
      durationSeconds: fields[2] as int?,
      trackNumber: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Track obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.filePath)
      ..writeByte(2)
      ..write(obj.durationSeconds)
      ..writeByte(3)
      ..write(obj.trackNumber);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
