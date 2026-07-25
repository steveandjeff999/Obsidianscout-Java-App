# ==============================================================================
# ObsidianScout - Automated Multi-Platform Release & Auto-Versioning Script
# ==============================================================================
# Usage:
#   .\build_releases.ps1                  (Auto-increments patch version & builds)
#   .\build_releases.ps1 -Version "1.1.0" (Sets specific version & builds)
# ==============================================================================

param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$appDir = $PSScriptRoot
Set-Location $appDir

$pubspecPath = Join-Path $appDir "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
    Write-Error "pubspec.yaml not found at $pubspecPath"
    exit 1
}

# 1. Read & Parse Current Version from pubspec.yaml
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match 'version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)') {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
    $buildNum = [int]$Matches[4]
} else {
    $major = 1; $minor = 0; $patch = 0; $buildNum = 1
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $patch += 1
    $buildNum += 1
    $newVersionStr = "$major.$minor.$patch+$buildNum"
} else {
    if ($Version -contains "+") {
        $newVersionStr = $Version
    } else {
        $buildNum += 1
        $newVersionStr = "$Version+$buildNum"
    }
}

$displayVersion = ($newVersionStr -split '\+')[0]

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "Starting Release Build for ObsidianScout v$displayVersion ($newVersionStr)" -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Cyan

# 2. Update pubspec.yaml with New Version
$updatedPubspec = $pubspecContent -replace 'version:\s*[^\r\n]+', "version: $newVersionStr"
Set-Content -Path $pubspecPath -Value $updatedPubspec -NoNewline
Write-Host "Updated pubspec.yaml version to $newVersionStr" -ForegroundColor Yellow

# 3. Locate Flutter Executable & Stop Daemons
$flutterCmd = "flutter"
if (Test-Path "C:\src\flutter\bin\flutter.bat") {
    $flutterCmd = "C:\src\flutter\bin\flutter.bat"
}

Write-Host "`nCleaning workspace and stopping background Gradle daemons..." -ForegroundColor Cyan
if (Test-Path "$appDir\android\gradlew.bat") {
    try {
        Push-Location "$appDir\android"
        & ".\gradlew.bat" --stop | Out-Null
    } catch {} finally {
        Pop-Location
    }
}

& $flutterCmd clean
& $flutterCmd pub get

# 4. Prepare Staging & Release Folders
$releaseBaseDir = Join-Path $appDir "releases"
$stagingDir = Join-Path $releaseBaseDir "ObsidianScout-v$displayVersion"

if (Test-Path $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

# 5. Build Android Release APK
Write-Host "`nBuilding Android Release APK..." -ForegroundColor Cyan
try {
    & $flutterCmd build apk --release
} catch {
    Write-Host "Android build encountered a Gradle daemon issue, retrying..." -ForegroundColor Yellow
    & $flutterCmd build apk --release
}

$apkSource = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkSource) {
    $apkTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Android.apk"
    Copy-Item -Path $apkSource -Destination $apkTarget -Force
    Write-Host "Android APK created: $(Split-Path $apkTarget -Leaf)" -ForegroundColor Green
} else {
    Write-Host "Android APK build output missing!" -ForegroundColor Red
}

# 6. Build Windows Desktop Release Executable & MSIX Installer
Write-Host "`nBuilding Windows Desktop Release App..." -ForegroundColor Cyan
& $flutterCmd build windows --release

$winSourceDir = Join-Path $appDir "build\windows\x64\runner\Release"
$winExePath = Join-Path $winSourceDir "obsidianscout_app.exe"

if ((Test-Path $winSourceDir) -and (Test-Path $winExePath)) {
    $winZipTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Windows.zip"
    Compress-Archive -Path "$winSourceDir\*" -DestinationPath $winZipTarget -Force
    Write-Host "Windows Bundle Zipped: $(Split-Path $winZipTarget -Leaf)" -ForegroundColor Green

    Write-Host "`nGenerating Windows MSIX Installer..." -ForegroundColor Cyan
    try {
        & $flutterCmd pub run msix:create -v $displayVersion
        $msixSource = Get-ChildItem -Path $winSourceDir -Filter "*.msix" | Select-Object -First 1
        if ($msixSource) {
            $msixTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Windows-Installer.msix"
            Copy-Item -Path $msixSource.FullName -Destination $msixTarget -Force
            Write-Host "Windows MSIX Installer created: $(Split-Path $msixTarget -Leaf)" -ForegroundColor Green

            # Extract Public Certificate (.cer) from the signed MSIX package
            try {
                $sig = Get-AuthenticodeSignature -FilePath $msixTarget
                if ($sig -and $sig.SignerCertificate) {
                    $cerTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Windows-Certificate.cer"
                    [void](Export-Certificate -Cert $sig.SignerCertificate -FilePath $cerTarget -Type CERT)
                    Write-Host "Windows Certificate extracted: $(Split-Path $cerTarget -Leaf)" -ForegroundColor Green

                    # Generate Install-Certificate.bat helper script
                    $batTarget = Join-Path $stagingDir "Install-Certificate.bat"
                    $batContent = @"
@echo off
echo Installing ObsidianScout Security Certificate into Trusted People store...
certutil -addstore "TrustedPeople" "%~dp0ObsidianScout-v$displayVersion-Windows-Certificate.cer"
if %errorlevel% equ 0 (
    echo.
    echo Certificate successfully installed! You can now double-click the .msix file to install ObsidianScout.
) else (
    echo.
    echo Certificate installation failed. Please right-click this script and select 'Run as administrator'.
)
pause
"@
                    Set-Content -Path $batTarget -Value $batContent -Encoding ASCII
                    Write-Host "Install-Certificate.bat helper created!" -ForegroundColor Green
                }
            } catch {
                Write-Host "Could not extract certificate file." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "MSIX creation skipped." -ForegroundColor Yellow
    }
} else {
    Write-Host "Windows build output missing!" -ForegroundColor Red
}

# 7. Build Linux Desktop Release App & .deb Installer (via WSL if on Windows Host)
Write-Host "`nBuilding Linux Desktop Release App & .deb Installer..." -ForegroundColor Cyan
if (Get-Command "wsl" -ErrorAction SilentlyContinue) {
    Write-Host "Attempting Linux build via WSL environment..." -ForegroundColor Yellow
    $wslPath = $appDir.Replace('\', '/').Replace('C:', '/mnt/c').Replace('c:', '/mnt/c')
    
    $wslFlutterCmd = "flutter"
    $checkRes = (wsl bash -c "test -f /home/steve/flutter/bin/flutter && echo 'FOUND'") 2>$null
    if ($checkRes -and $checkRes.Trim() -eq "FOUND") {
        $wslFlutterCmd = "/home/steve/flutter/bin/flutter"
    }

    try {
        $wslRunCmd = "cd '$wslPath' && $wslFlutterCmd pub get && $wslFlutterCmd build linux --release"
        wsl bash -c $wslRunCmd

        # Build native .deb installer package in WSL
        $debCmd = 'DEB_DIR=/tmp/obsidianscout_deb; rm -rf "$DEB_DIR"; mkdir -p "$DEB_DIR/DEBIAN" "$DEB_DIR/usr/lib/obsidianscout" "$DEB_DIR/usr/bin" "$DEB_DIR/usr/share/applications" "$DEB_DIR/usr/share/pixmaps"; cp -r "' + $wslPath + '/build/linux/x64/release/bundle/"* "$DEB_DIR/usr/lib/obsidianscout/"; ln -sf /usr/lib/obsidianscout/obsidianscout_app "$DEB_DIR/usr/bin/obsidianscout"; cp "' + $wslPath + '/assets/images/obsidian-512.png" "$DEB_DIR/usr/share/pixmaps/obsidianscout.png"; printf "Package: obsidianscout\nVersion: ' + $displayVersion + '\nArchitecture: amd64\nMaintainer: ObsidianScout Team\nDescription: ObsidianScout Scouting App\n" > "$DEB_DIR/DEBIAN/control"; printf "[Desktop Entry]\nName=ObsidianScout\nComment=ObsidianScout Scouting App\nExec=/usr/bin/obsidianscout\nIcon=obsidianscout\nTerminal=false\nType=Application\nCategories=Utility;Sports;\n" > "$DEB_DIR/usr/share/applications/obsidianscout.desktop"; dpkg-deb --build "$DEB_DIR" "' + $wslPath + '/build/linux/x64/release/obsidianscout.deb"'
        wsl bash -c $debCmd
    } catch {
        Write-Host "WSL Linux build process exited." -ForegroundColor Yellow
    }
}

$linuxBundleDir = Join-Path $appDir "build\linux\x64\release\bundle"
if (Test-Path $linuxBundleDir) {
    $linuxTarTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Linux.tar.gz"
    if (Get-Command "tar" -ErrorAction SilentlyContinue) {
        tar -czf $linuxTarTarget -C $linuxBundleDir .
    } else {
        $linuxZipTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Linux.zip"
        Compress-Archive -Path "$linuxBundleDir\*" -DestinationPath $linuxZipTarget -Force
    }
    Write-Host "Linux Release Package created: $(Split-Path $linuxTarTarget -Leaf)" -ForegroundColor Green
}

$wslDebPath = Join-Path $appDir "build\linux\x64\release\obsidianscout.deb"
if (Test-Path $wslDebPath) {
    $debTarget = Join-Path $stagingDir "ObsidianScout-v$displayVersion-Linux.deb"
    Copy-Item -Path $wslDebPath -Destination $debTarget -Force
    Write-Host "Linux .deb Installer created: $(Split-Path $debTarget -Leaf)" -ForegroundColor Green
} else {
    Write-Host "Note: Skipping Linux .deb packaging." -ForegroundColor Yellow
}

# 8. Generate SHA-256 Checksums
Write-Host "`nGenerating SHA-256 Checksums..." -ForegroundColor Cyan
$checksumFile = Join-Path $stagingDir "checksums.txt"
$filesToHash = Get-ChildItem -Path $stagingDir -File | Where-Object { $_.Name -ne "checksums.txt" }

$hashLines = foreach ($f in $filesToHash) {
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    "$hash  $($f.Name)"
}
Set-Content -Path $checksumFile -Value $hashLines
Write-Host "checksums.txt generated" -ForegroundColor Green

# 9. Create Master Release Bundle Zip
$masterZipTarget = Join-Path $releaseBaseDir "ObsidianScout-v$displayVersion-AllInstallers.zip"
if (Test-Path $masterZipTarget) {
    Remove-Item -Path $masterZipTarget -Force
}

Write-Host "`nPackaging Master Installer Bundle..." -ForegroundColor Cyan
Compress-Archive -Path "$stagingDir\*" -DestinationPath $masterZipTarget -Force

Write-Host "`n===========================================================" -ForegroundColor Cyan
Write-Host "RELEASE BUILD COMPLETE!" -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "Master Zip Bundle: $masterZipTarget" -ForegroundColor Yellow
Write-Host "Artifacts Staging Directory: $stagingDir" -ForegroundColor Yellow
Write-Host "`nContents of Release:" -ForegroundColor White
Get-ChildItem -Path $stagingDir | Format-Table Name, Length -AutoSize
