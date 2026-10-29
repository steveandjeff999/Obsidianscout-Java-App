package com.obsidianscout.obsidianscout_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/** Shares downloaded update APKs with the system package installer. Its own class so the authority can't clash with a plugin's provider. */
class UpdateFileProvider : FileProvider()

/** Install source and APK install for GitHub self-updates (lib/services/app_update_io.dart). */
object AppUpdater {
    /** Package that installed this app, e.g. com.android.vending for Play; null when installed by adb or unknown. */
    fun installerPackage(context: Context): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstallerPackageName(context.packageName)
        }
    } catch (e: Exception) {
        null
    }

    /**
     * Opens the system installer for [path]. When the user hasn't yet let this app install apps, opens that
     * setting instead and returns "needs_permission" so the app can ask them to try again.
     */
    fun installApk(activity: Activity, path: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return "needs_permission"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updatefileprovider", File(path))
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
        return "started"
    }
}
