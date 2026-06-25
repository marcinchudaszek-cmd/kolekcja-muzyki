import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/album.dart';
import 'models/listening_history.dart';
import 'services/audio_service.dart';
import 'services/audio_player_handler.dart';
import 'services/database_service.dart';
import 'services/history_service.dart';
import 'services/backup_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicjalizacja Hive (lokalna baza danych)
  await Hive.initFlutter();
  Hive.registerAdapter(AlbumAdapter());
  Hive.registerAdapter(TrackAdapter());
  Hive.registerAdapter(ListeningRecordAdapter());
  await Hive.openBox<Album>('albums');
  await Hive.openBox<ListeningRecord>('listening_history');

  // Sesja medialna: ekran blokady, powiadomienie i Android Auto.
  // Box 'albums' jest juz otwarty, wiec drzewo przegladania ma dostep do
  // kolekcji od razu po starcie.
  final audioHandler = await audio_service.AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const audio_service.AudioServiceConfig(
      androidNotificationChannelId: 'com.beagleappsstudio.kolekcjamuzyki.audio',
      androidNotificationChannelName: 'Odtwarzanie',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  // Ustaw orientacje na portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Ustaw kolor paska systemowego
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  
  runApp(MyApp(audioHandler: audioHandler));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.audioHandler});

  final AudioPlayerHandler audioHandler;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioService(audioHandler)),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
        ChangeNotifierProvider(create: (_) => HistoryService()),
        ChangeNotifierProvider(create: (_) => BackupService()),
      ],
      child: MaterialApp(
        title: 'Kolekcja Muzyki',
        debugShowCheckedModeBanner: false,
        // Na szerokich ekranach (web/desktop) ogranicz aplikację do
        // wycentrowanej kolumny o proporcjach telefonu.
        builder: (context, child) {
          final width = MediaQuery.of(context).size.width;
          if (width <= 600 || child == null) return child ?? const SizedBox();
          return ColoredBox(
            color: const Color(0xFF070710),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(480, MediaQuery.of(context).size.height),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFF4ade80),
            secondary: const Color(0xFF22d3ee),
            surface: const Color(0xFF1a1a2e),
            background: const Color(0xFF0f0f1a),
            error: const Color(0xFFef4444),
          ),
          scaffoldBackgroundColor: const Color(0xFF0f0f1a),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1a1a2e),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF1a1a2e),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          textTheme: GoogleFonts.interTextTheme(
            ThemeData.dark().textTheme,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF4ade80),
            foregroundColor: Colors.black,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

