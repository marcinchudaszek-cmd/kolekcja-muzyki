import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  static const _shazamPkg = 'com.shazam.android';
  static const _soundHoundPkg = 'com.melodis.midomiMusicIdentifier.freemium';

  bool _shazamInstalled = false;
  bool _soundHoundInstalled = false;

  @override
  void initState() {
    super.initState();
    _checkInstalledApps();
  }

  Future<void> _checkInstalledApps() async {
    if (kIsWeb) return;
    // Wymaga <queries><package/></queries> w AndroidManifest (Android 11+).
    try {
      final shazam = await LaunchApp.isAppInstalled(androidPackageName: _shazamPkg);
      final soundHound =
          await LaunchApp.isAppInstalled(androidPackageName: _soundHoundPkg);
      if (mounted) {
        setState(() {
          _shazamInstalled = shazam == true;
          _soundHoundInstalled = soundHound == true;
        });
      }
    } catch (_) {
      // Brak detekcji — zostana etykiety "Pobierz".
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.recognizeSong),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: const Icon(Icons.mic, size: 70, color: Colors.black),
              ),
              const SizedBox(height: 32),
              Text(l.recognizeWith, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 24),

              _buildAppCard(
                l: l,
                name: 'Shazam',
                installed: _shazamInstalled,
                color: const Color(0xFF0088FF),
                packageName: _shazamPkg,
              ),

              const SizedBox(height: 12),

              _buildAppCard(
                l: l,
                name: 'SoundHound',
                installed: _soundHoundInstalled,
                color: const Color(0xFFFF6600),
                packageName: _soundHoundPkg,
              ),

              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: () => _openUrl(
                    'https://www.google.com/search?q=what+song+is+this+lyrics'),
                icon: const Icon(Icons.search),
                label: Text(l.searchLyricsGoogle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppCard({
    required L l,
    required String name,
    required bool installed,
    required Color color,
    required String packageName,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              installed ? l.appInstalled : l.getFromPlayStore,
              style: TextStyle(color: installed ? Colors.green : Colors.grey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openApp(packageName),
                icon: Icon(installed ? Icons.launch : Icons.download,
                    size: 18, color: Colors.white),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(12)),
                label: Text(installed ? l.openApp(name) : l.getApp(name)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openApp(String packageName) async {
    if (kIsWeb) {
      await _openUrl(
          'https://play.google.com/store/apps/details?id=$packageName');
      return;
    }
    try {
      // Otwiera aplikacje; gdy nie jest zainstalowana, otwiera Sklep Play.
      await LaunchApp.openApp(
        androidPackageName: packageName,
        openStore: true,
      );
    } catch (_) {
      await _openUrl(
          'https://play.google.com/store/apps/details?id=$packageName');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
