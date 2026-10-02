package com.beagleappsstudio.kolekcjamuzyki

import android.app.Activity
import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.provider.MediaStore
import android.speech.RecognizerIntent
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : AudioServiceActivity() {

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

        // Zamiana sciezka -> content:// URI zyje w pluginie mediastore_resolver
        // (packages/), bo musi dzialac takze bez Activity — Android Auto
        // uruchamia sam serwis audio.

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
}
