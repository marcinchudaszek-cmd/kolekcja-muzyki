import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/cover_service.dart';
import '../services/backup_service.dart';
import 'audio_settings_screen.dart';
import 'history_screen.dart';
import 'recognize_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDownloadingCovers = false;
  int _downloadProgress = 0;
  int _downloadTotal = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
      ),
      body: ListView(
        children: [
          // Sekcja: Okladki
          _buildSectionHeader(context, 'Okladki'),
          ListTile(
            leading: _isDownloadingCovers
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image),
            title: Text(_isDownloadingCovers
                ? 'Pobieranie... $_downloadProgress/$_downloadTotal'
                : 'Pobierz brakujace okladki'),
            subtitle: const Text('Pobierz okladki dla wszystkich albumow'),
            onTap: _isDownloadingCovers ? null : () => _downloadAllCovers(context),
          ),

          // Sekcja: Odtwarzacz
          _buildSectionHeader(context, 'Odtwarzacz'),
          ListTile(
            leading: const Icon(Icons.equalizer),
            title: const Text('Ustawienia dzwieku'),
            subtitle: const Text('Equalizer, crossfade'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AudioSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Historia sluchania'),
            subtitle: const Text('Ostatnio odtwarzane, statystyki'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Rozpoznaj utwor'),
            subtitle: const Text('Znajdz piosenke po dzwieku'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecognizeScreen()),
            ),
          ),

          // Sekcja: Dane
          _buildSectionHeader(context, 'Dane'),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Eksportuj kolekcje'),
            subtitle: const Text('Zapisz kopie zapasowa jako JSON'),
            onTap: () => _exportData(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Importuj kolekcje'),
            subtitle: const Text('Wczytaj z pliku JSON'),
            onTap: () => _importData(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Wyczysc kolekcje', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Usun wszystkie albumy'),
            onTap: () => _clearData(context),
          ),

          // Sekcja: Informacje
          _buildSectionHeader(context, 'Informacje'),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('O aplikacji'),
            subtitle: const Text('Kolekcja Muzyki v1.3'),
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _downloadAllCovers(BuildContext context) async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final albumsWithoutCovers = db.albums.where((a) => 
      (a.coverUrl == null || a.coverUrl!.isEmpty) && 
      (a.coverPath == null || a.coverPath!.isEmpty)
    ).toList();

    if (albumsWithoutCovers.isEmpty) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Okladki'),
            content: const Text('Wszystkie albumy maja juz okladki!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() {
      _isDownloadingCovers = true;
      _downloadProgress = 0;
      _downloadTotal = albumsWithoutCovers.length;
    });

    for (var album in albumsWithoutCovers) {
      try {
        final coverUrl = await CoverService.fetchCover(album.artist, album.title);
        if (coverUrl != null && coverUrl.isNotEmpty) {
          db.updateCover(album.id, coverUrl);
        }
      } catch (e) {
        // Ignoruj bledy
      }
      setState(() {
        _downloadProgress++;
      });
    }

    setState(() {
      _isDownloadingCovers = false;
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pobrano okladki dla $_downloadProgress albumow')),
      );
    }
  }

  Future<void> _exportData(BuildContext context) async {
    final db = Provider.of<DatabaseService>(context, listen: false);

    try {
      final data = db.exportToJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      // Zapisz do pliku w Downloads
      final directory = Directory('/storage/emulated/0/Download');
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('${directory.path}/kolekcja_$timestamp.json');
      await file.writeAsString(jsonString);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zapisano: ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Blad eksportu: $e')),
        );
      }
    }
  }

  Future<void> _importData(BuildContext context) async {
    final db = Provider.of<DatabaseService>(context, listen: false);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final data = json.decode(jsonString) as List;
        final imported = await db.importFromJson(data);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zaimportowano $imported albumow')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Blad importu: $e')),
        );
      }
    }
  }

  Future<void> _clearData(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wyczysc kolekcje?'),
        content: const Text('Ta operacja usunie wszystkie albumy. Czy na pewno chcesz kontynuowac?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usun', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = Provider.of<DatabaseService>(context, listen: false);
      for (var album in db.albums.toList()) { db.deleteAlbum(album.id); }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kolekcja wyczyszczona')),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kolekcja Muzyki'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wersja 1.3.0'),
            SizedBox(height: 16),
            Text('Aplikacja do zarzadzania kolekcja muzyczna.'),
            SizedBox(height: 8),
            Text('Beagle Apps Studio'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

