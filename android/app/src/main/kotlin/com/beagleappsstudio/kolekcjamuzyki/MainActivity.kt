package com.beagleappsstudio.kolekcjamuzyki

import android.app.Activity
import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.speech.RecognizerIntent
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : AudioServiceActivity() {

    private val channelName = "kolekcja/mediastore"
    private val voiceChannelName = "kolekcja/voice"
    private val tag = "MediaStoreResolver"

    private val speechRequestCode = 7341
    private var speechResult: MethodChannel.Result? = null

    /** Zapytanie z komendy Asystenta ("zagraj X"), odbierane przez Fluttera. */
    private var pendingSearchQuery: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        capturePlayFromSearch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        capturePlayFromSearch(intent)
    }

    /** Wyluskuje fraze z intencji MEDIA_PLAY_FROM_SEARCH (Asystent Google). */
    private fun capturePlayFromSearch(intent: Intent?) {
        if (intent?.action != MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH) return
        val query = intent.getStringExtra(SearchManager.QUERY)
        // Pusta fraza = "wlacz muzyke" — obsluzone po stronie Dart.
        pendingSearchQuery = query ?: ""
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "uriForPath" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(null)
                        } else {
                            result.success(uriForPath(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dyktowanie przez aplikacje systemowa — NIE wymaga
                    // uprawnienia RECORD_AUDIO, bo nagrywa system.
                    "recognizeSpeech" ->
                        startSpeechRecognition(call.argument<String>("locale"), result)
                    "isSpeechAvailable" -> result.success(isSpeechAvailable())
                    // Fraza z komendy Asystenta (odbierana raz).
                    "consumePendingSearch" -> {
                        val q = pendingSearchQuery
                        pendingSearchQuery = null
                        result.success(q)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isSpeechAvailable(): Boolean = try {
        packageManager.queryIntentActivities(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH), 0
        ).isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun startSpeechRecognition(locale: String?, result: MethodChannel.Result) {
        if (speechResult != null) {
            // Dyktowanie juz trwa — nie otwieraj drugiego okna.
            result.success(null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale ?: Locale.getDefault().toString())
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            speechResult = result
            startActivityForResult(intent, speechRequestCode)
        } catch (e: ActivityNotFoundException) {
            speechResult = null
            Log.w(tag, "Brak aplikacji rozpoznawania mowy: ${e.message}")
            result.success(null)
        }
    }

    @Deprecated("startActivityForResult — wystarczajace dla pojedynczego dyktowania")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == speechRequestCode) {
            val pending = speechResult
            speechResult = null
            if (resultCode == Activity.RESULT_OK) {
                val matches =
                    data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                pending?.success(matches?.firstOrNull())
            } else {
                // Anulowane przez uzytkownika.
                pending?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * Zamienia surowa sciezke pliku na content:// URI z MediaStore.
     * Na Androidzie 10+ zapytanie po kolumnie _data bywa zawodne, wiec
     * probujemy kolejno: _data, potem display_name + relative_path,
     * a na koniec samo display_name.
     */
    private fun uriForPath(path: String): String? {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

        // Strategia 1: dokladna sciezka (_data)
        queryId(collection, "${MediaStore.Audio.Media.DATA}=?", arrayOf(path))?.let {
            return contentUri(collection, it)
        }

        val fileName = path.substringAfterLast('/')

        // Strategia 2: display_name + relative_path (niezawodne na Androidzie 10+)
        // relative_path = sciezka po "/storage/emulated/0/" do katalogu, z "/"
        val afterRoot = path.substringAfter("/0/", "")
        if (afterRoot.isNotEmpty() && afterRoot.contains('/')) {
            val relPath = afterRoot.substringBeforeLast('/') + "/"
            queryId(
                collection,
                "${MediaStore.Audio.Media.DISPLAY_NAME}=? AND ${MediaStore.Audio.Media.RELATIVE_PATH}=?",
                arrayOf(fileName, relPath)
            )?.let {
                return contentUri(collection, it)
            }
        }

        // Strategia 3: samo display_name (gdy unikalne)
        queryId(
            collection,
            "${MediaStore.Audio.Media.DISPLAY_NAME}=?",
            arrayOf(fileName)
        )?.let {
            return contentUri(collection, it)
        }

        Log.w(tag, "BRAK trafienia w MediaStore dla $path")
        return null
    }

    private fun queryId(collection: Uri, selection: String, args: Array<String>): Long? {
        return try {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.Audio.Media._ID),
                selection,
                args,
                null
            )?.use { c ->
                if (c.moveToFirst()) c.getLong(0) else null
            }
        } catch (e: Exception) {
            Log.e(tag, "query blad ($selection): ${e.message}")
            null
        }
    }

    private fun contentUri(collection: Uri, id: Long): String =
        ContentUris.withAppendedId(collection, id).toString()
}
