$ErrorActionPreference = "Stop"

# === 環境変数の確認 ===
Write-Host "DEBUG - SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "DEBUG - $($_.Name) = $($_.Value)" }

$token = $env:SLACK_BOT_TOKEN
$email = $env:SLACK_USER_EMAIL

if (-not $token) { Write-Error "ERROR - SLACK_BOT_TOKEN is null"; exit 1 }
if (-not $email) { Write-Error "ERROR - SLACK_USER_EMAIL is null"; exit 1 }
Write-Host "DEBUG - Slack token starts with: $($token.Substring(0,10))..."
Write-Host "DEBUG - Slack user email: $email"

# === ファイル準備 ===
$dummy = Join-Path $PSScriptRoot "dummy.txt"
Set-Content -Path $dummy -Value "dummy"

$zip = Join-Path $PSScriptRoot "vpn_package.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $dummy -DestinationPath $zip -Force
$size = (Get-Item $zip).Length
Write-Host "DEBUG - ZIP size: $size bytes"

# === ユーザーIDの取得 ===
Write-Host "INFO - Getting Slack user ID from email..."
$userResp = Invoke-RestMethod -Method Get `
  -Uri "https://slack.com/api/users.lookupByEmail?email=$($email)" `
  -Headers @{ Authorization = "Bearer $token" }

if (-not $userResp.ok) {
  Write-Error "ERROR - users.lookupByEmail failed: $($userResp.error)"
  exit 1
}
$userId = $userResp.user.id
Write-Host "INFO - Slack user ID: $userId"

# === DM チャンネルを開く ===
Write-Host "INFO - Opening DM channel..."
$dmResp = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/conversations.open" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body (@{ users = $userId } | ConvertTo-Json)

if (-not $dmResp.ok) {
  Write-Error "ERROR - conversations.open failed: $($dmResp.error)"
  exit 1
}
$channelId = $dmResp.channel.id
Write-Host "INFO - DM Channel ID: $channelId"

# === ファイルをアップロード（files.upload） ===
Write-Host "INFO - Uploading file via files.upload..."

$response = Invoke-RestMethod -Uri "https://slack.com/api/files.upload" `
  -Method Post `
  -Headers @{ Authorization = "Bearer $token" } `
  -Form @{
      channels        = $channelId
      file            = Get-Item -Path $zip
      filename        = "vpn_package.zip"
      title           = "VPN ZIP Package"
      initial_comment = "VPNパッケージをこちらからダウンロードできます。"
  }

Write-Host "DEBUG - files.upload response:"
Write-Host (ConvertTo-Json $response -Depth 5)

if (-not $response.ok) {
  Write-Error "ERROR - files.upload failed: $($response.error)"
  exit 1
}

Write-Host "SUCCESS - File uploaded and shared in DM channel!"
