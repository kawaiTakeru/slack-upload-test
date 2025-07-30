$ErrorActionPreference = "Stop"

# Environment variables
$slackToken = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL

# === TOKEN DEBUG CHECK ===
Write-Host "[DEBUG] Available environment variables:"
Get-ChildItem Env: | Where-Object { $_.Name -like "SLACK*" } | ForEach-Object {
    Write-Host "[DEBUG] $($_.Name) = $($_.Value)"
}

if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is null in script"
    exit 1
} else {
    Write-Host "[DEBUG] SLACK_BOT_TOKEN starts with: $($slackToken.Substring(0, 10))..."
}

$workingDir = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFilePath = "$workingDir\dummy.txt"
$zipFilePath = "$workingDir\vpn_package.zip"

Write-Host "[INFO] Creating dummy.txt..."
Set-Content -Path $dummyFilePath -Value "This is a dummy file for Slack upload test."

Write-Host "[INFO] Creating ZIP file..."
Compress-Archive -Path $dummyFilePath -DestinationPath $zipFilePath -Force

# Step 1: Request upload URL with correct types
$uploadRequest = [PSCustomObject]@{
    filename = "vpn_package.zip"
    length   = [int64](Get-Item $zipFilePath).Length
    alt_text = "Test ZIP"
}
Write-Host "[INFO] Requesting upload URL from Slack..."
$uploadUrlResp = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body ($uploadRequest | ConvertTo-Json -Depth 10 -Compress)

Write-Host "[DEBUG] files.getUploadURLExternal response:"
$uploadUrlResp | ConvertTo-Json -Depth 10 | Write-Host

$uploadUrl = $uploadUrlResp.upload_url
$fileId = $uploadUrlResp.file_id

if ([string]::IsNullOrEmpty($uploadUrl) -or [string]::IsNullOrEmpty($fileId)) {
    Write-Error "[ERROR] Slack did not return upload_url or file_id. Aborting."
    exit 1
}

Write-Host "[INFO] Upload URL received: $uploadUrl"
Write-Host "[INFO] File ID received: $fileId"

# Step 2: PUT upload
Write-Host "[INFO] Uploading file via PUT..."
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFilePath -ContentType "application/octet-stream"
Write-Host "[INFO] File upload completed."

# Step 3: Complete upload
$completeReq = @{
    files = @(@{
        id       = $fileId
        title    = "Test VPN ZIP"
        alt_text = "Test ZIP uploaded"
    })
}
Write-Host "[INFO] Completing file upload in Slack..."
$response = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body (ConvertTo-Json $completeReq -Depth 10 -Compress)

Write-Host "[DEBUG] files.completeUploadExternal response:"
$response | ConvertTo-Json -Depth 10 | Write-Host

# Step 4: Open DM
Write-Host "[INFO] Looking up user by email: $slackUserEmail"
$userInfo = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/users.lookupByEmail" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ email = $slackUserEmail }

$userId = $userInfo.user.id
Write-Host "[INFO] User ID: $userId"

$channelResp = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ users = $userId }

$channelId = $channelResp.channel.id
Write-Host "[INFO] DM Channel ID: $channelId"

# Step 5: Send message
$messageReq = @{
    channel     = $channelId
    text        = "🔔 VPN test ZIP file has been uploaded."
    attachments = @(@{
        fallback    = "vpn_package.zip"
        title       = "VPN ZIP File"
        title_link  = "https://files.slack.com/files-pri/$fileId"
    })
}
Write-Host "[INFO] Sending Slack message..."
$result = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/chat.postMessage" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body (ConvertTo-Json $messageReq -Depth 10 -Compress)

Write-Host "[DEBUG] chat.postMessage response:"
$result | ConvertTo-Json -Depth 10 | Write-Host

Write-Host "[✅ SUCCESS] Slack message sent!"
