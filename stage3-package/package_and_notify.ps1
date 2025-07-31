$ErrorActionPreference = "Stop"

# === 環境変数の確認 ===
Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $($_.Name) = $($_.Value)" }

$token = $env:SLACK_BOT_TOKEN
$email = $env:SLACK_USER_EMAIL

if (-not $token) { Write-Error "[ERROR] SLACK_BOT_TOKEN is null"; exit 1 }
if (-not $email) { Write-Error "[ERROR] SLACK_USER_EMAIL is null"; exit 1 }
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

# === ユーザーIDの取得 ===
Write-Host "[INFO] Getting Slack user ID from email..."
$userResp = Invoke-RestMethod -Method Get `
  -Uri "https://slack.com/api/users.lookupByEmail?email=$($email)" `
  -Headers @{ Authorization = "Bearer $token" }

if (-not $userResp.ok) { Write-Error "[ERROR] users.lookupByEmail failed: $($userResp.error)"; exit 1 }
$userId = $userResp.user.id
Write-Host "[INFO] Slack user ID: $userId"

# === DMチャンネルIDの取得 ===
Write-Host "[INFO] Opening DM channel..."
$dmResp = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/conversations.open" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body (@{ users = $userId } | ConvertTo-Json)

if (-not $dmResp.ok) { Write-Error "[ERROR] conversations.open failed: $($dmResp.error)"; exit 1 }
$channelId = $dmResp.channel.id
Write-Host "[INFO] DM Channel ID: $channelId"

# === Upload URLの取得 ===
$form = "filename=$([Uri]::EscapeDataString([IO.Path]::GetFileName($zip)))&length=$size"
Write-Host "[DEBUG] Form-body for getUploadURLExternal: $form"

$resp = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/files.getUploadURLExternal" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/x-www-form-urlencoded" } `
  -Body $form

Write-Host "[DEBUG] Response from getUploadURLExternal:"
Write-Host (ConvertTo-Json $resp -Depth 5)

if (-not $resp.ok) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($resp.error)"
    exit 1
}

$uploadUrl = $resp.upload_url
$fileId = $resp.file_id
Write-Host "[INFO] Upload URL: $uploadUrl"
Write-Host "[INFO] File ID: $fileId"

# === アップロード（PUT） ===
Write-Host "[INFO] Uploading file via PUT..."
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zip -ContentType "application/octet-stream"
Write-Host "[INFO] File upload (PUT) completed"

# === 完了通知（手書き JSON）
$completeJson = @"
{
  "files": [
    {
      "id": "$fileId",
      "title": "vpn_package.zip"
    }
  ],
  "channel_id": "$channelId",
  "initial_comment": "VPN ZIP uploaded"
}
"@

Write-Host "[DEBUG] completeUploadExternal payload:"
Write-Host $completeJson

$compResp = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/files.completeUploadExternal" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body $completeJson

Write-Host "[DEBUG] completeUploadExternal response:"
Write-Host (ConvertTo-Json $compResp -Depth 5)

if (-not $compResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($compResp.error)"
    exit 1
}

# === 1. permalink付きメッセージ
$permalink = $compResp.files[0].permalink
Write-Host "[INFO] Slack File Permalink: $permalink"

$msgBody1 = @{
  channel = $channelId
  text    = "VPN ZIP uploaded. Download: $permalink"
} | ConvertTo-Json -Depth 3

$msgResp1 = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/chat.postMessage" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body $msgBody1

if (-not $msgResp1.ok) {
    Write-Error "[ERROR] permalink chat.postMessage failed: $($msgResp1.error)"
    exit 1
}

# === 2. ファイル添付共有
$msgBody2 = @{
  channel  = $channelId
  text     = "VPN ZIP is ready. See attached file."
  file_ids = @($fileId)
} | ConvertTo-Json -Depth 3

$msgResp2 = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/chat.postMessage" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body $msgBody2

Write-Host "[DEBUG] chat.postMessage response with file_ids:"
Write-Host (ConvertTo-Json $msgResp2 -Depth 5)

if (-not $msgResp2.ok) {
    Write-Error "[ERROR] chat.postMessage (file_ids) failed: $($msgResp2.error)"
    exit 1
}

Write-Host "[✅ SUCCESS] Upload and full file-shared message sent via DM!"
