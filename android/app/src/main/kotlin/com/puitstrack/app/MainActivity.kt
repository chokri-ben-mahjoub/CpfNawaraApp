package com.puitstrack.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (et non FlutterActivity) est requis par `local_auth`
// pour afficher la boîte de dialogue d'authentification biométrique Android.
//
// Le canal "puitstrack/downloads" enregistre les exports (Excel/CSV) et les
// sauvegardes directement dans le dossier public Téléchargements/PuitsTrack,
// sans passer par le volet de partage — voir
// `lib/core/export/download_saver.dart`. Il gère aussi le mode "écran
// protégé" (FLAG_SECURE) des Réglages.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "puitstrack/downloads"
    private val rootFolder = "PuitsTrack"
    private val legacyPermissionRequest = 4201

    /// Enregistrement en attente de la permission de stockage (Android 9 et
    /// moins uniquement — inutile à partir d'Android 10 grâce à MediaStore).
    private var pendingSave: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> saveToDownloads(call, result)
                "openFile" -> openFile(call, result)
                "setSecure" -> {
                    val secure = call.argument<Boolean>("secure") ?: false
                    if (secure) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val bytes = call.argument<ByteArray>("bytes")
        if (name == null || bytes == null) {
            result.error("bad_args", "name and bytes are required", null)
            return
        }
        // Sous-dossier optionnel (ex: "Sauvegardes") sous Téléchargements/PuitsTrack.
        val sub = call.argument<String>("subFolder")
        val folder = if (sub.isNullOrEmpty()) rootFolder else "$rootFolder/$sub"
        // overwrite : remplace un fichier du même nom créé par l'app
        // (sauvegardes automatiques en rotation) au lieu d'en créer un "(1)".
        val overwrite = call.argument<Boolean>("overwrite") ?: false
        val askPermission = call.argument<Boolean>("requestPermission") ?: true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val resolver = contentResolver
                val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$folder"
                var uri: Uri? = null
                if (overwrite) {
                    resolver.query(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        arrayOf(MediaStore.MediaColumns._ID),
                        "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                        arrayOf(name, "$relativePath/"),
                        null,
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            uri = android.content.ContentUris.withAppendedId(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                cursor.getLong(0),
                            )
                        }
                    }
                }
                val target = uri
                if (target != null) {
                    resolver.openOutputStream(target, "wt")?.use { it.write(bytes) }
                        ?: throw IllegalStateException("Cannot open output stream")
                    result.success(mapOf("uri" to target.toString(), "folder" to relativePath))
                    return
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val created = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                resolver.openOutputStream(created)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Cannot open output stream")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(created, values, null, null)
                result.success(mapOf("uri" to created.toString(), "folder" to relativePath))
            } catch (e: Exception) {
                result.error("save_failed", e.message, null)
            }
            return
        }

        val save = { saveLegacy(name, mime, bytes, folder, result) }
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            save()
        } else if (!askPermission) {
            // Sauvegarde automatique au démarrage : on ne surprend pas
            // l'utilisateur avec une demande de permission.
            result.error("permission_denied", "Storage permission not granted", null)
        } else {
            pendingSave = save
            pendingResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                legacyPermissionRequest,
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(name: String, mime: String, bytes: ByteArray, folder: String, result: MethodChannel.Result) {
        try {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folder)
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, name)
            file.writeBytes(bytes)
            val main = Handler(Looper.getMainLooper())
            // Le scan rend le fichier visible dans l'app Fichiers/Téléchargements
            // et fournit une URI content:// ouvrable par une autre application.
            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime)) { _, uri ->
                main.post {
                    result.success(
                        mapOf(
                            "uri" to (uri ?: Uri.fromFile(file)).toString(),
                            "folder" to "${Environment.DIRECTORY_DOWNLOADS}/$folder",
                        ),
                    )
                }
            }
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != legacyPermissionRequest) return
        val save = pendingSave
        val result = pendingResult
        pendingSave = null
        pendingResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            save?.invoke()
        } else {
            result?.error("permission_denied", "Storage permission denied", null)
        }
    }

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val mime = call.argument<String>("mime") ?: "*/*"
        if (uriString == null) {
            result.error("bad_args", "uri is required", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uriString), mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.success(false)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
