# Shared helper: builds the --dart-define argument list from tool/.env.web.
# Usage: . "$PSScriptRoot/_firebase_defines.ps1"; flutter run @firebaseDefines
# The script emits $firebaseDefines (string[]) and warns when the file is missing.
$firebaseEnvFile = Join-Path $PSScriptRoot ".env.web"
$firebaseDefines = @()

if (-not (Test-Path -LiteralPath $firebaseEnvFile)) {
  Write-Warning "tool/.env.web not found. Web will run in local-only mode (no Firebase). Copy tool/env.web.example to tool/.env.web and fill it in."
  return
}

foreach ($line in Get-Content -LiteralPath $firebaseEnvFile) {
  $trimmed = $line.Trim()
  if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
  $eq = $trimmed.IndexOf('=')
  if ($eq -le 0) { continue }
  $key = $trimmed.Substring(0, $eq).Trim()
  $value = $trimmed.Substring($eq + 1).Trim()
  if ($key -eq '' -or $value -eq '') { continue }
  $firebaseDefines += "--dart-define=$key=$value"
}

if ($firebaseDefines.Count -eq 0) {
  Write-Warning "tool/.env.web has no non-empty KEY=VALUE entries. Web will run in local-only mode (no Firebase)."
}