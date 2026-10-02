package com.beagleappsstudio.mediastore_resolver;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.database.Cursor;
import android.net.Uri;
import android.provider.MediaStore;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Zamienia surowa sciezke pliku na content:// URI z MediaStore.
 * Plugin (a nie kanal w MainActivity), zeby dzialal tez w silniku Fluttera
 * uruchomionym przez sam serwis audio — tak startuje aplikacja z Android Auto.
 */
public class MediastoreResolverPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String TAG = "MediaStoreResolver";
    private MethodChannel channel;
    private ContentResolver resolver;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        resolver = binding.getApplicationContext().getContentResolver();
        channel = new MethodChannel(binding.getBinaryMessenger(), "beagleapps/mediastore_resolver");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("uriForPath".equals(call.method)) {
            String path = call.argument("path");
            result.success(path == null || path.isEmpty() ? null : uriForPath(path));
        } else {
            result.notImplemented();
        }
    }

    /**
     * Na Androidzie 10+ zapytanie po kolumnie _data bywa zawodne, wiec
     * probujemy kolejno: _data, potem display_name + relative_path,
     * a na koniec samo display_name.
     */
    private String uriForPath(String path) {
        Uri collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;

        Long id = queryId(collection, MediaStore.Audio.Media.DATA + "=?", new String[]{path});
        if (id != null) return contentUri(collection, id);

        String fileName = path.substring(path.lastIndexOf('/') + 1);

        int rootIdx = path.indexOf("/0/");
        if (rootIdx >= 0) {
            String afterRoot = path.substring(rootIdx + 3);
            int lastSlash = afterRoot.lastIndexOf('/');
            if (lastSlash > 0) {
                String relPath = afterRoot.substring(0, lastSlash) + "/";
                id = queryId(collection,
                        MediaStore.Audio.Media.DISPLAY_NAME + "=? AND "
                                + MediaStore.Audio.Media.RELATIVE_PATH + "=?",
                        new String[]{fileName, relPath});
                if (id != null) return contentUri(collection, id);
            }
        }

        id = queryId(collection, MediaStore.Audio.Media.DISPLAY_NAME + "=?", new String[]{fileName});
        if (id != null) return contentUri(collection, id);

        Log.w(TAG, "BRAK trafienia w MediaStore dla " + path);
        return null;
    }

    private Long queryId(Uri collection, String selection, String[] args) {
        try (Cursor c = resolver.query(collection,
                new String[]{MediaStore.Audio.Media._ID}, selection, args, null)) {
            if (c != null && c.moveToFirst()) return c.getLong(0);
        } catch (Exception e) {
            Log.e(TAG, "query blad (" + selection + "): " + e.getMessage());
        }
        return null;
    }

    private static String contentUri(Uri collection, long id) {
        return ContentUris.withAppendedId(collection, id).toString();
    }
}
