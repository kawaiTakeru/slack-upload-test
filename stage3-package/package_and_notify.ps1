
$ErrorActionPreference = "Stop"

# === Debug: 環境変数表示 ===
Write-Host "[DEBUG] Available SLACK env vars:"
Get-ChildItem Env: | Where-Object { $_.Name -like "SLACK*" } | ForEach-Object {
    Write-Host "[DEBUG] $($_.Name) = $($_.Value)"
}

# 環境変数取得
$slackToken = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL

if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is null"
    exit 1
}
Write-Host "[DEBUG] Slack token starts with: $($slackToken.Substring(0,10))..."

$workingDir = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFile = Join-Path $workingDir "dummy.txt"
$zipFile = Join-Path $workingDir "vpn_package.zip"

# ファイル生成と ZIP 化
Write-Host "[INFO] Creating dummy file..."
Set-Content -Path $dummyFile -Value "dummy"
Write-Host "[INFO] Compressing to ZIP..."
Compress-Archive -Path $dummyFile -DestinationPath $zipFile -Force

# ファイルサイズ取得
$size = (Get-Item $zipFile).Length
Write-Host "[DEBUG] ZIP file size (bytes): $size"

# JSON 本文作成
$uploadBody = @{
    filename = [System.IO.Path]::GetFileName($zipFile)
    length = $size
    alt_text = "Test ZIP file"
}
$uploadBodyJson = $uploadBody | ConvertTo-Json -Depth 10
Write-Host "[DEBUG] JSON body for getUploadURLExternal:"
Write-Host $uploadBodyJson

# API コール：upload URL 取得
Write-Host "[INFO] Requesting upload URL..."
$uploadResp = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken"; "Content-Type" = "application/json; charset=utf-8" } `
    -Body $uploadBodyJson

Write-Host "[DEBUG] files.getUploadURLExternal response:"
$uploadResp | ConvertTo-Json -Depth 10 | Write-Host

if (-not $uploadResp.ok -or -not $uploadResp.upload_url -or -not $uploadResp.file_id) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($uploadResp.error)"
    exit 1
}

$uploadUrl = $uploadResp.upload_url
$fileId = $uploadResp.file_id
Write-Host "[INFO] Upload URL: $uploadUrl"
Write-Host "[INFO] File ID: $fileId"

# ファイルアップロード（内容を PUT）
Write-Host "[INFO] Uploading file..."
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFile -ContentType "application/octet-stream"
Write-Host "[INFO] Upload complete (HTTP PUT)."

# アップロード完了通知
$completeReq = @{
    files = @(@{ id = $fileId })
    channel_id = $null  # 必要に応じて設定
    initial_comment = "VPN ZIP uploaded"
}
$completeJson = $completeReq | ConvertTo-Json -Depth 10
Write-Host "[INFO] Completing upload..."
$completeResp = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken"; "Content-Type" = "application/json; charset=utf-8" } `
    -Body $completeJson

Write-Host "[DEBUG] files.completeUploadExternal response:"
$completeResp | ConvertTo-Json -Depth 10 | Write-Host

if (-not $completeResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($completeResp.error)"
    exit 1
}
Write-Host "[✅ SUCCESS] File upload flow completed!"
