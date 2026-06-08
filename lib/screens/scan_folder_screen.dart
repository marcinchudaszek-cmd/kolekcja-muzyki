import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/album.dart';
import '../services/database_service.dart';
import '../services/cover_service.dart';

class ScanFolderScreen extends StatefulWidget {
  const ScanFolderScreen({super.key});

  @override
  State<ScanFolderScreen> createState() => _ScanFolderScreenState();
}

class _ScanFolderScreenState extends State<ScanFolderScreen> {
  bool _isScanning = false;
  String _status = 'Wybierz folder z muzyka';
  List<Map<String, dynamic>> _foundAlbums = [];
  Set<int> _selectedIndexes = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skanuj folder'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _selectFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Wybierz folder'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_status, textAlign: TextAlign.center),
              ],
            ),
          ),
          
          if (_isScanning)
            const LinearProgressIndicator(),
          
          if (_foundAlbums.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Znaleziono: ${_foundAlbums.length} albumow'),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedIndexes.length == _foundAlbums.length) {
                          _selectedIndexes.clear();
                        } else {
                          _selectedIndexes = Set.from(List.generate(_foundAlbums.length, (i) => i));
                        }
                      });
                    },
                    child: Text(_selectedIndexes.length == _foundAlbums.length ? 'Odznacz wszystko' : 'Zaznacz wszystko'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _foundAlbums.length,
                itemBuilder: (context, index) {
                  final album = _foundAlbums[index];
                  final isSelected = _selectedIndexes.contains(index);
                  final trackCount = (album['tracks'] as List?)?.length ?? 0;
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIndexes.add(index);
                        } else {
                          _selectedIndexes.remove(index);
                        }
                      });
                    },
                    title: Text(album['title'] ?? 'Nieznany album'),
                    subtitle: Text('${album['artist'] ?? 'Nieznany'} - $trackCount utworow'),
                    secondary: const Icon(Icons.album),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _selectedIndexes.isEmpty ? null : _importSelected,
                icon: const Icon(Icons.download),
                label: Text('Importuj (${_selectedIndexes.length})'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      
      if (result == null) return;
      
      setState(() {
        _isScanning = true;
        _status = 'Skanuje folder...';
        _foundAlbums = [];
        _selectedIndexes = {};
      });
      
      await _scanDirectory(result);
      
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = 'Blad: $e';
      });
    }
  }

  Future<void> _scanDirectory(String path) async {
    final dir = Directory(path);
    final albums = <String, Map<String, dynamic>>{};
    
    try {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = entity.path.toLowerCase();
          if (ext.endsWith('.mp3') || ext.endsWith('.flac') || ext.endsWith('.m4a') || ext.endsWith('.wav') || ext.endsWith('.ogg')) {
            final file = entity;
            final parentDir = file.parent.path;
            final parentName = file.parent.path.split(Platform.pathSeparator).last;
            
            if (!albums.containsKey(parentDir)) {
              final parts = parentName.split(' - ');
              String artist = 'Nieznany';
              String title = parentName;
              
              if (parts.length >= 2) {
                artist = parts[0].trim();
                title = parts.sublist(1).join(' - ').trim();
              }
              
              albums[parentDir] = {
                'artist': artist,
                'title': title,
                'path': parentDir,
                'tracks': <Map<String, String>>[],
              };
            }
            
            final fileName = file.path.split(Platform.pathSeparator).last;
            final trackName = fileName.replaceAll(RegExp(r'\.(mp3|flac|m4a|wav|ogg)$', caseSensitive: false), '');
            
            (albums[parentDir]!['tracks'] as List).add({
              'title': trackName,
              'path': file.path,
            });
          }
        }
      }
      
      for (var album in albums.values) {
        (album['tracks'] as List).sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
      }
      
      setState(() {
        _isScanning = false;
        _foundAlbums = albums.values.toList();
        _selectedIndexes = Set.from(List.generate(_foundAlbums.length, (i) => i));
        if (_foundAlbums.isEmpty) {
          _status = 'Nie znaleziono albumow w tym folderze';
        } else {
          _status = 'Znaleziono ${_foundAlbums.length} albumow';
        }
      });
      
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = 'Blad skanowania: $e';
      });
    }
  }

  Future<void> _importSelected() async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    
    setState(() {
      _isScanning = true;
      _status = 'Importuje...';
    });
    
    int imported = 0;
    int skipped = 0;
    final total = _selectedIndexes.length;
    
    for (var index in _selectedIndexes) {
      final albumData = _foundAlbums[index];
      final artist = albumData['artist'] as String;
      final title = albumData['title'] as String;
      
      if (db.isDuplicate(artist, title)) {
        skipped++;
        continue;
      }
      
      final tracks = (albumData['tracks'] as List).map((t) => Track(
        title: t['title'] as String,
        filePath: t['path'] as String,
        durationSeconds: 0,
        trackNumber: 0,
      )).toList();
      
      String? coverUrl;
      try {
        coverUrl = await CoverService.fetchCover(artist, title);
      } catch (_) {}
      
      final album = Album(
        id: 'folder_${DateTime.now().millisecondsSinceEpoch}_$index',
        artist: artist,
        title: title,
        genre: 'other',
        format: 'digital',
        rating: 3,
        tracks: tracks,
        coverUrl: coverUrl,
      );
      
      await db.addAlbum(album);
      imported++;
      
      setState(() {
        _status = 'Importuje... $imported/$total';
      });
    }
    
    String finalStatus = 'Zaimportowano $imported albumow';
    if (skipped > 0) {
      finalStatus += ' ($skipped pominietych)';
    }
    
    setState(() {
      _isScanning = false;
      _status = finalStatus;
      _foundAlbums = [];
      _selectedIndexes = {};
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zaimportowano $imported albumow'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
