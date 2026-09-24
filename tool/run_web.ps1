# Runs the web app in Chrome with Firebase web config loaded from tool/.env.web.
param(
  [string]$Device = "chrome"
)

. "$PSScriptRoot/_firebase_defines.ps1"

flutter run -d $Device @firebaseDefines