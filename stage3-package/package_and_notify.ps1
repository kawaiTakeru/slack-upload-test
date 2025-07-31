$ErrorActionPreference = "Stop"

# === 環境変数の確認 ===
Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $($_.Name) = $($_.Value)" }

$token = $env:SLACK_BOT_TOKEN
$channelId = "C097YJV3UH2"  # ← 投稿先チャンネルIDを直接指定

if (-not $token) { Write-Error "[ERROR] SLACK_BOT_TOKEN is null"; exit 1 }
Write-Host "[DEBUG] Slack token starts with: $($token.Substring(0,10))..."
Write-Host "[DEBUG] Slack channel ID: $channelId"

# === ダミーファイルを複数生成してZIPに含める
$dummyFiles = @()
for ($i = 1; $i -le 3; $i++) {
    $f = Join-Path $PSScriptRoot "dummy$i.txt"
    Set-Content -Path $f -Value "dummy content $i"
    $dummyFiles += $f
}

$zip = Join-Path $PSScriptRoot "vpn_package.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $dummyFiles -DestinationPath $zip -Force

$size = (Get-Item $zip).Length
Write-Host "[DEBUG] ZIP size: $size bytes"

Write-Host "[DEBUG] Included files in ZIP:"
$dummyFiles | ForEach-Object { Write-Host " - $_ = $(Get-Content $_)" }

Write-Host "[DEBUG] ZIP MD5: $(Get-FileHash -Algorithm MD5 $zip).Hash"

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

# === アップロード（PUT）
Write-Host "[INFO] Uploading file via PUT..."
$response = Invoke-WebRequest -Method Put `
  -Uri $uploadUrl `
  -InFile $zip `
  -ContentType "application/zip" `
  -UseBasicParsing
Write-Host "[DEBUG] PUT Upload StatusCode: $($response.StatusCode)"
$response.Headers.GetEnumerator() | ForEach-Object { Write-Host "[DEBUG] Header] $($_.Name): $($_.Value)" }

Write-Host "[INFO] File upload completed"

# === 完了通知
$completeJson = @"
{
  "files": [
    {
      "id": "$fileId",
      "title": "vpn_package.zip",
      "mimetype": "application/zip",
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

Write-Host "[DEBUG] completeUploadExternal full response:"
Write-Host (ConvertTo-Json $compResp -Depth 10)

if (-not $compResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($compResp.error)"
    exit 1
}

# === 1. URL付きメッセージ送信
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

# === 2. 添付ファイル付きメッセージ送信
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

Write-Host "[✅ SUCCESS] Upload and full file-shared message sent to channel!"
