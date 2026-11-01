package com.obsidianscout.obsidianscout_app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import java.io.File
import java.io.IOException

/** Saves files to the phone's shared Downloads folder (lib/services/file_download_io.dart). */
object DownloadsSaver {
    /** Thrown below Android 10 until the user grants storage access; the app asks and tries again. */
    class NeedsPermission : Exception("Storage permission is required")

    /** Writes [bytes] to Downloads and returns where the user will find them, e.g. "Downloads/report (1).csv". */
    fun save(context: Context, filename: String, mimeType: String, bytes: ByteArray): String {
        // Android appends an extension when the type disagrees with the name, so trust the name first.
        val extension = filename.substringAfterLast('.', "").lowercase()
        val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: mimeType.substringBefore(';').trim().ifEmpty { "application/octet-stream" }
        val savedName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(context, filename, type, bytes)
        } else {
            saveToPublicFolder(context, filename, type, bytes)
        }
        return "${Environment.DIRECTORY_DOWNLOADS}/$savedName"
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveWithMediaStore(context: Context, filename: String, type: String, bytes: ByteArray): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, type)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not create $filename in Downloads")
        try {
            val output = resolver.openOutputStream(uri) ?: throw IOException("Could not open $filename in Downloads")
            output.use { it.write(bytes) }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // MediaStore renames the file when the name is taken.
        return resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: filename
    }

    @Suppress("DEPRECATION")
    private fun saveToPublicFolder(context: Context, filename: String, type: String, bytes: ByteArray): String {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE)
        if (granted != PackageManager.PERMISSION_GRANTED) throw NeedsPermission()
        val folder = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        folder.mkdirs()
        var file = File(folder, filename)
        var copy = 1
        while (file.exists()) {
            val extension = file.extension.let { if (it.isEmpty()) "" else ".$it" }
            file = File(folder, "${filename.removeSuffix(extension)} (${copy++})$extension")
        }
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(context, arrayOf(file.path), arrayOf(type), null)
        return file.name
    }
}
