$ErrorActionPreference = "Stop"

# === 環境変数の確認 ===
Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $($_.Name) = $($_.Value)" }

$token = $env:SLACK_BOT_TOKEN
$email = $env:SLACK_USER_EMAIL

if (-not $token) { Write-Error "SLACK_BOT_TOKEN is null"; exit 1 }
if (-not $email) { Write-Error "SLACK_USER_EMAIL is null"; exit 1 }
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
$userResp = Invoke-RestMethod -Uri "https://slack.com/api/users.lookupByEmail" `
  -Headers @{ Authorization = "Bearer $token" } `
  -Method Get `
  -Body @{ email = $email }

if (-not $userResp.ok) { Write-Error "users.lookupByEmail failed: $($userResp.error)"; exit 1 }

$userId = $userResp.user.id
Write-Host "[INFO] Slack user ID: $userId"

# === DMチャンネルIDの取得 ===
$chanResp = Invoke-RestMethod -Uri "https://slack.com/api/conversations.open" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Method Post `
  -Body (@{ users = $userId } | ConvertTo-Json)

if (-not $chanResp.ok) { Write-Error "conversations.open failed: $($chanResp.error)"; exit 1 }

$channel_id = $chanResp.channel.id
Write-Host "[INFO] DM channel ID: $channel_id"

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
    Write-Error "getUploadURLExternal failed: $($resp.error)"
    exit 1
}

$uploadUrl = $resp.upload_url
$fileId = $resp.file_id
Write-Host "[INFO] Upload URL: $uploadUrl"
Write-Host "[INFO] File ID: $fileId"

# === アップロード（PUT）
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zip -ContentType "application/octet-stream"
Write-Host "[INFO] File upload (PUT) completed"

# === 完了通知
$completeBody = @{
  files           = @(@{ id = $fileId })
  channel_id      = $channel_id
  initial_comment = "VPN ZIP uploaded"
}
$completeJson = $completeBody | ConvertTo-Json -Depth 5
Write-Host "[DEBUG] completeUploadExternal payload:"
Write-Host $completeJson

$compResp = Invoke-RestMethod -Method Post `
  -Uri "https://slack.com/api/files.completeUploadExternal" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body $completeJson

Write-Host "[DEBUG] completeUploadExternal response:"
Write-Host (ConvertTo-Json $compResp -Depth 5)

if (-not $compResp.ok) {
    Write-Error "completeUploadExternal failed: $($compResp.error)"
    exit 1
}

Write-Host "[✅ SUCCESS] Upload workflow completed!"
