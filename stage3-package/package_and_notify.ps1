$ErrorActionPreference = "Stop"

# --- Environment Variables ---
$slackToken = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL
$workingDir = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFilePath = Join-Path $workingDir "dummy.txt"
$zipFilePath = Join-Path $workingDir "vpn_package.zip"

# --- Print Available Environment Variables ---
Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env: | Where-Object { $_.Name -like "SLACK*" } | ForEach-Object {
    Write-Host "[DEBUG] $($_.Name) = $($_.Value)"
}

# --- Validate Token ---
if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is null in script"
    exit 1
}
Write-Host "[DEBUG] Slack token starts with: $($slackToken.Substring(0, 10))..."

# --- Create ZIP File ---
Write-Host "[INFO] Creating dummy.txt…"
Set-Content -Path $dummyFilePath -Value "This is a dummy file for Slack upload test."
Write-Host "[INFO] Compressing to ZIP…"
Compress-Archive -Path $dummyFilePath -DestinationPath $zipFilePath -Force

# --- Step 1: Get Upload URL ---
$length = (Get-Item $zipFilePath).Length
$uploadRequest = @{
    filename = "vpn_package.zip"
    length   = [int64]$length
    alt_text = "Test ZIP"
}
Write-Host "[DEBUG] JSON body for getUploadURLExternal:"
$uploadRequest | ConvertTo-Json -Depth 10 | Write-Host

Write-Host "[DEBUG] Sending headers:"
Write-Host "Authorization: Bearer ***"
Write-Host "Content-Type: application/json; charset=utf-8"

$uploadUrlResp = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body ($uploadRequest | ConvertTo-Json -Depth 10)

Write-Host "[DEBUG] Response:"
$uploadUrlResp | ConvertTo-Json -Depth 10 | Write-Host

$uploadUrl = $uploadUrlResp.upload_url
$fileId = $uploadUrlResp.file_id

if ([string]::IsNullOrEmpty($uploadUrl) -or [string]::IsNullOrEmpty($fileId)) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($uploadUrlResp.error)"
    exit 1
}

Write-Host "[INFO] Upload URL: $uploadUrl"
Write-Host "[INFO] File ID: $fileId"

# --- Step 2: PUT Upload ---
Write-Host "[INFO] Uploading ZIP via PUT..."
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFilePath -ContentType "application/zip"
Write-Host "[INFO] Upload completed."

# --- Step 3: Complete Upload ---
$completeReq = @{
    files = @(@{
        id       = $fileId
        title    = "VPN ZIP"
        alt_text = "VPN Test ZIP file"
    })
}
$response = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body ($completeReq | ConvertTo-Json -Depth 10)

Write-Host "[DEBUG] completeUploadExternal response:"
$response | ConvertTo-Json -Depth 10 | Write-Host

# --- Step 4: Open DM Channel ---
Write-Host "[INFO] Looking up user: $slackUserEmail"
$userInfo = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/users.lookupByEmail" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ email = $slackUserEmail }

$userId = $userInfo.user.id
Write-Host "[INFO] Found user ID: $userId"

$channelResp = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ users = $userId }

$channelId = $channelResp.channel.id
Write-Host "[INFO] DM channel ID: $channelId"

# --- Step 5: Send Message with File Link ---
$messageReq = @{
    channel = $channelId
    text    = "🔔 VPN ZIP file uploaded."
    attachments = @(
        @{
            fallback    = "vpn_package.zip"
            title       = "VPN ZIP"
            title_link  = "https://files.slack.com/files-pri/$fileId"
        }
    )
}
$result = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/chat.postMessage" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body ($messageReq | ConvertTo-Json -Depth 10)

Write-Host "[DEBUG] chat.postMessage response:"
$result | ConvertTo-Json -Depth 10 | Write-Host

Write-Host "[✅ SUCCESS] Slack message sent!"
