$ErrorActionPreference = "Stop"

# === 環境変数の確認 ===
Write-Host '[DEBUG] SLACK env vars:'
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $($_.Name) = $($_.Value)" }

$token = $env:SLACK_BOT_TOKEN
$email = $env:SLACK_USER_EMAIL

if (-not $token) { Write-Error '[ERROR] SLACK_BOT_TOKEN is null'; exit 1 }
if (-not $email) { Write-Error '[ERROR] SLACK_USER_EMAIL is null'; exit 1 }
Write-Host "[DEBUG] Slack token starts with: $($token.Substring(0,10))..."
Write-Host "[DEBUG] Slack user email: $email"

# === ファイル準備 ===
$dummy = Join-Path $PSScriptRoot "dummy.txt"
Set-Content -Path $dummy -Value "dummy"
$zip = Join-Path $PSScriptRoot "vpn_package.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $dummy -DestinationPath $zip -Force
$size = (Get-Item $zip).Length
Write-Host "[DEBUG] ZIP size: $size bytes"

# === ユーザーID取得 ===
Write-Host '[INFO] Getting Slack user ID from email...'
try {
  $userResp = Invoke-RestMethod -Method Get `
    -Uri "https://slack.com/api/users.lookupByEmail?email=$($email)" `
    -Headers @{ Authorization = "Bearer $token" }
  Write-Host "[DEBUG] users.lookupByEmail response:"
  Write-Host (ConvertTo-Json $userResp -Depth 10)
  if (-not $userResp.ok) { throw "users.lookupByEmail failed: $($userResp.error)" }
  $userId = $userResp.user.id
  Write-Host "[INFO] Slack user ID: $userId"
} catch {
  Write-Error "[ERROR] Failed to get user ID: $($_.Exception.Message)"
  exit 1
}

# === DM チャネル作成 ===
Write-Host '[INFO] Opening DM channel...'
try {
  $dmResp = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
    -Body (@{ users = $userId } | ConvertTo-Json)
  Write-Host "[DEBUG] conversations.open response:"
  Write-Host (ConvertTo-Json $dmResp -Depth 10)
  if (-not $dmResp.ok) { throw "conversations.open failed: $($dmResp.error)" }
  $channelId = $dmResp.channel.id
  Write-Host "[INFO] DM Channel ID: $channelId"
} catch {
  Write-Error "[ERROR] Failed to open DM channel: $($_.Exception.Message)"
  exit 1
}

# === Upload URL 取得 ===
$form = "filename=$([Uri]::EscapeDataString($($zip | Split-Path -Leaf)))&length=$size"
Write-Host "[DEBUG] Form-body for getUploadURLExternal: $form"
try {
  $resp = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/x-www-form-urlencoded" } `
    -Body $form
  Write-Host "[DEBUG] getUploadURLExternal response:"
  Write-Host (ConvertTo-Json $resp -Depth 10)
  if (-not $resp.ok) { throw "getUploadURLExternal failed: $($resp.error)" }
  $uploadUrl = $resp.upload_url
  $fileId = $resp.file_id
  Write-Host "[INFO] Upload URL: $uploadUrl"
  Write-Host "[INFO] File ID: $fileId"
} catch {
  Write-Error "[ERROR] Failed to get upload URL: $($_.Exception.Message)"
  exit 1
}

# === PUT アップロード ===
Write-Host '[INFO] Uploading file via PUT...'
try {
  Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zip -ContentType "application/octet-stream"
  Write-Host '[INFO] File upload (PUT) completed'
} catch {
  Write-Error "[ERROR] PUT upload failed: $($_.Exception.Message)"
  exit 1
}

# === ファイル完了通知と共有 ===
$completeBody = @{
  files           = @(@{ id = $fileId; title = "vpn_package.zip" })
  channel_id      = $channelId
  initial_comment = "VPN パッケージをこちらからダウンロードできます。"
}
$completeJson = $completeBody | ConvertTo-Json -Depth 5
Write-Host '[DEBUG] completeUploadExternal payload:'
Write-Host $completeJson

try {
  $compResp = Invoke-RestMethod -Method Post `
    -Uri 'https://slack.com/api/files.completeUploadExternal' `
    -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
    -Body $completeJson
  Write-Host '[DEBUG] completeUploadExternal response:'
  Write-Host (ConvertTo-Json $compResp -Depth 10)
  if (-not $compResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($compResp.error)"
    exit 1
  }
} catch {
  Write-Error "[ERROR] completeUploadExternal exception: $($_.Exception.Message)"
  exit 1
}

Write-Host '[SUCCESS] File shared in DM channel.'
