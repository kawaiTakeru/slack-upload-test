$ErrorActionPreference = "Stop"

# 環境変数取得
$slackToken     = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL

# --- トークン確認 ---
if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is null"
    exit 1
} else {
    Write-Host "[DEBUG] Slack token starts with: $($slackToken.Substring(0,10))..."
}

# --- ファイル準備 ---
$workingDir     = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFilePath  = "$workingDir\dummy.txt"
$zipFilePath    = "$workingDir\vpn_package.zip"

Write-Host "[INFO] Creating dummy.txt..."
Set-Content -Path $dummyFilePath -Value "This is a dummy file for Slack upload test."

Write-Host "[INFO] Compressing to ZIP..."
Compress-Archive -Path $dummyFilePath -DestinationPath $zipFilePath -Force

$length = (Get-Item $zipFilePath).Length
Write-Host "[DEBUG] Zip file size (bytes): $length"

# --- Step 1: getUploadURLExternal ---
$uploadRequest = @{
    filename = "vpn_package.zip"
    length   = $length
    alt_text = "Test ZIP"
}
$bodyJson = $uploadRequest | ConvertTo-Json -Depth 5
Write-Host "[DEBUG] JSON body for getUploadURLExternal:`n$bodyJson"

Write-Host "[INFO] Requesting upload URL..."
$response = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken"; "Content-Type" = "application/json; charset=utf-8" } `
    -Body $bodyJson `
    -ResponseHeadersVariable respHdr `
    -ErrorAction Stop

Write-Host "[DEBUG] HTTP status code: $($respHdr.StatusCode.Value__)"
Write-Host "[DEBUG] Response JSON:`n$( $response | ConvertTo-Json -Depth 5 )"

if (-not $response.ok -or -not $response.upload_url -or -not $response.file_id) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($response.error)"
    exit 1
}
$uploadUrl = $response.upload_url
$fileId    = $response.file_id
Write-Host "[INFO] Upload URL received."
Write-Host "[INFO] File ID: $fileId"

# --- Step 2: Upload (PUT or multipart POST) ---
Write-Host "[INFO] Uploading file via POST to upload_url..."
# Slack docs allows raw bytes or multipart form:
$resultUpload = Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFilePath -ContentType "application/zip" -ErrorAction Stop
Write-Host "[DEBUG] Upload return: $resultUpload"

# --- Step 3: completeUploadExternal ---
$completeReq = @{
    files = @(@{
        id       = $fileId
        title    = "Test VPN ZIP"
        alt_text = "Test ZIP uploaded"
    })
}
$completeJson = $completeReq | ConvertTo-Json -Depth 5
Write-Host "[DEBUG] JSON body for completeUploadExternal:`n$completeJson"

$response2 = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken"; "Content-Type" = "application/json; charset=utf-8" } `
    -Body $completeJson -ErrorAction Stop

Write-Host "[DEBUG] completeUpload response:`n$($response2 | ConvertTo-Json -Depth 5)"
if (-not $response2.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($response2.error)"
    exit 1
}

# --- Step 4: DM ワークフロー ---
Write-Host "[INFO] Looking up user by email: $slackUserEmail"
$userInfo = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/users.lookupByEmail" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{ email = $slackUserEmail }

$userId = $userInfo.user.id
Write-Host "[INFO] User ID: $userId"

$channelResp = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{ users = $userId }

$channelId = $channelResp.channel.id
Write-Host "[INFO] Opened DM channel ID: $channelId"

# --- Step 5: 発言投稿 ---
$messageReq = @{
    channel     = $channelId
    text        = "🔔 VPN test ZIP file has been uploaded."
    attachments = @(
        @{
            fallback   = "vpn_package.zip"
            title      = "VPN ZIP File"
            title_link = "https://files.slack.com/files-pri/$fileId"
        }
    )
}
$messageJson = $messageReq | ConvertTo-Json -Depth 5
Write-Host "[DEBUG] JSON body for chat.postMessage:`n$messageJson"

$response3 = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/chat.postMessage" `
    -Headers @{ Authorization = "Bearer $slackToken"; "Content-Type" = "application/json; charset=utf-8" } `
    -Body $messageJson -ErrorAction Stop

Write-Host "[DEBUG] chat.postMessage response:`n$($response3 | ConvertTo-Json -Depth 5)"
if (-not $response3.ok) {
    Write-Error "[ERROR] chat.postMessage failed: $($response3.error)"
    exit 1
}

Write-Host "[✅ SUCCESS] Slack message sent!"
