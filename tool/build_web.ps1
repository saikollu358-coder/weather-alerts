# Builds the web app with Firebase web config loaded from tool/.env.web.
. "$PSScriptRoot/_firebase_defines.ps1"

flutter build web @firebaseDefines