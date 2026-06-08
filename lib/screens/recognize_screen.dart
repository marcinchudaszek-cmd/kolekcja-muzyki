import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RecognizeScreen extends StatelessWidget {
  const RecognizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rozpoznaj utwor'),
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
              const Text('Rozpoznaj utwor za pomoca:', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Shazam', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Pobierz ze Sklepu Play', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _openApp('com.shazam.android'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0088FF), padding: const EdgeInsets.all(12)),
                          child: const Text('Pobierz Shazam'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('SoundHound', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Pobierz ze Sklepu Play', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _openApp('com.melodis.midomiMusicIdentifier.freemium'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6600), padding: const EdgeInsets.all(12)),
                          child: const Text('Pobierz SoundHound'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              OutlinedButton.icon(
                onPressed: () => _openUrl('https://www.google.com/search?q=what+song+is+this+lyrics'),
                icon: const Icon(Icons.search),
                label: const Text('Szukaj tekstu w Google'),
              ),
              
              const SizedBox(height: 24),
              
              Text(
                'Po zainstalowaniu Shazam lub SoundHound,\nuruchom je recznie z ekranu glownego.',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openApp(String packageName) async {
    final appUri = Uri.parse(packageName == 'com.shazam.android' ? 'market://launch?id=com.shazam.android' : 'soundhound://');
    final storeUri = Uri.parse('https://play.google.com/store/apps/details?id=' + packageName);
    try {
      await launchUrl(appUri);
    } catch (e) {
      await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  // unused
    void _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}








