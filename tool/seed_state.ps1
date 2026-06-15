# Dev helper: seed Wayfarer's persisted state on a connected device/emulator
# (debug build only — uses run-as). Usage:
#   .\tool\seed_state.ps1 -Json '{"schemaVersion":1,"state":{...}}'
# Writes the shared_preferences XML and restarts the app.
param(
    [Parameter(Mandatory = $true)][string]$Json
)

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$pkg = "com.wayfarer.app"

# XML-escape the JSON payload (& < > only; quotes are fine in text nodes).
$escaped = $Json.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')

$xml = @"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="flutter.wayfarer.state">$escaped</string>
</map>
"@

$tmp = Join-Path $env:TEMP "wayfarer_seed.xml"
Set-Content -Path $tmp -Value $xml -Encoding utf8 -NoNewline

& $adb shell am force-stop $pkg
& $adb push $tmp /data/local/tmp/wayfarer_seed.xml | Out-Null
& $adb shell "run-as $pkg mkdir -p shared_prefs"
& $adb shell "run-as $pkg cp /data/local/tmp/wayfarer_seed.xml shared_prefs/FlutterSharedPreferences.xml"
& $adb shell rm /data/local/tmp/wayfarer_seed.xml
& $adb shell am start -n "$pkg/com.wayfarer.wayfarer.MainActivity" | Out-Null
Write-Output "seeded and relaunched"
