import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../l10n/app_localizations.dart';
import '../services/database_service.dart';
import '../services/cover_service.dart';
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
    final l = L.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settings),
      ),
      body: ListView(
        children: [
          // Sekcja: Wyglad / Jezyk
          _buildSectionHeader(context, l.sectionAppearance),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.language),
            subtitle: Text(l.languageSubtitle),
            trailing: DropdownButton<AppLang>(
              value: localeProvider.lang,
              underline: const SizedBox.shrink(),
              onChanged: (lang) {
                if (lang != null) localeProvider.setLang(lang);
              },
              items: [
                for (final lang in AppLang.values)
                  DropdownMenuItem(value: lang, child: Text(lang.label)),
              ],
            ),
          ),

          // Sekcja: Okladki
          _buildSectionHeader(context, l.sectionCovers),
          ListTile(
            leading: _isDownloadingCovers
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image),
            title: Text(_isDownloadingCovers
                ? l.downloadingCovers(_downloadProgress, _downloadTotal)
                : l.downloadCovers),
            subtitle: Text(l.downloadCoversSubtitle),
            onTap: _isDownloadingCovers ? null : () => _downloadAllCovers(context),
          ),

          // Sekcja: Odtwarzacz
          _buildSectionHeader(context, l.sectionPlayer),
          ListTile(
            leading: const Icon(Icons.equalizer),
            title: Text(l.audioSettings),
            subtitle: Text(l.audioSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AudioSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l.listeningHistory),
            subtitle: Text(l.listeningHistorySubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mic),
            title: Text(l.recognizeSong),
            subtitle: Text(l.recognizeSongSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecognizeScreen()),
            ),
          ),

          // Sekcja: Dane
          _buildSectionHeader(context, l.sectionData),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text(l.exportCollection),
            subtitle: Text(l.exportCollectionSubtitle),
            onTap: () => _exportData(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: Text(l.importCollection),
            subtitle: Text(l.importCollectionSubtitle),
            onTap: () => _importData(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(l.clearCollection, style: const TextStyle(color: Colors.red)),
            subtitle: Text(l.clearCollectionSubtitle),
            onTap: () => _clearData(context),
          ),

          // Sekcja: Informacje
          _buildSectionHeader(context, l.sectionAbout),
          ListTile(
            leading: const Icon(Icons.info),
            title: Text(l.about),
            subtitle: Text('${l.appTitle} v1.4'),
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
    final l = L.read(context);
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
            title: Text(l.coversTitle),
            content: Text(l.allHaveCovers),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.ok),
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
        SnackBar(content: Text(l.coversDownloaded(_downloadProgress))),
      );
    }
  }

  Future<void> _exportData(BuildContext context) async {
    final l = L.read(context);
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
          SnackBar(content: Text(l.savedTo(file.path))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.exportError(e))),
        );
      }
    }
  }

  Future<void> _importData(BuildContext context) async {
    final l = L.read(context);
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
            SnackBar(content: Text(l.importedAlbums(imported))),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.importError(e))),
        );
      }
    }
  }

  Future<void> _clearData(BuildContext context) async {
    final l = L.read(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.clearCollection),
        content: Text(l.clearCollectionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = Provider.of<DatabaseService>(context, listen: false);
      for (var album in db.albums.toList()) { db.deleteAlbum(album.id); }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.collectionCleared)),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    final l = L.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.appTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.version('1.4.2')),
            const SizedBox(height: 16),
            Text(l.aboutDescription),
            const SizedBox(height: 8),
            const Text('Beagle Apps Studio'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }
}
