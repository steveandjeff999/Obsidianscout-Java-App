package com.obsidianscout.obsidianscout_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

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

    private fun getSigningDigests(packageInfo: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = packageInfo.signingInfo ?: return emptySet()
            signingInfo.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures
        } ?: return emptySet()

        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.mapTo(HashSet()) { sig ->
            digest.reset()
            digest.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }
    }

    private fun verifyApkSignature(activity: Activity, apkFile: File) {
        if (!apkFile.isFile) {
            throw SecurityException("Update APK file not found")
        }
        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

        val installedInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(activity.packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(activity.packageName, flags)
        }

        val archiveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageArchiveInfo(apkFile.absolutePath, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(apkFile.absolutePath, flags)
        } ?: throw SecurityException("Unable to inspect downloaded APK signing certificates")

        if (archiveInfo.packageName != activity.packageName) {
            throw SecurityException(
                "Downloaded APK package (${archiveInfo.packageName}) does not match installed app (${activity.packageName})"
            )
        }

        val installedDigests = getSigningDigests(installedInfo)
        val archiveDigests = getSigningDigests(archiveInfo)
        // Some OEM builds don't report certificates for archives. The system installer still refuses an update
        // signed by a different key, so only a positive mismatch is rejected here.
        if (installedDigests.isNotEmpty() && archiveDigests.isNotEmpty() && installedDigests != archiveDigests) {
            throw SecurityException("Downloaded APK signing certificate does not match installed application")
        }
    }

    /**
     * Opens the system installer for [path]. When the user hasn't yet let this app install apps, opens that
     * setting instead and returns "needs_permission" so the app can ask them to try again.
     */
    fun installApk(activity: Activity, path: String): String {
        val apkFile = File(path)
        verifyApkSignature(activity, apkFile)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return "needs_permission"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updatefileprovider", apkFile)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
        return "started"
    }
}
