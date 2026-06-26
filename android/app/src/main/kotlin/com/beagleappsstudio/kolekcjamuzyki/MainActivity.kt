package com.beagleappsstudio.kolekcjamuzyki

import android.content.ContentUris
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private val channelName = "kolekcja/mediastore"
    private val tag = "MediaStoreResolver"

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
