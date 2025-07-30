$ErrorActionPreference = "Stop"

# 環境変数取得
$slackToken     = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL

Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env: | Where-Object { $_.Name -like "SLACK*" } | ForEach-Object {
    Write-Host "[DEBUG] $_"
}

if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is null"
    exit 1
} else {
    Write-Host "[DEBUG] Slack token starts with: $($slackToken.Substring(0,10))..."
}

$workingDir  = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyPath   = "$workingDir\dummy.txt"
$zipPath     = "$workingDir\vpn_package.zip"

Write-Host "[INFO] Creating dummy.txt…"
Set-Content -Path $dummyPath -Value "This is a dummy file for Slack upload test."

Write-Host "[INFO] Compressing to ZIP…"
Compress-Archive -Path $dummyPath -DestinationPath $zipPath -Force

# Step 1: getUploadURLExternal
$uploadRequest = [PSCustomObject]@{
    filename = "vpn_package.zip"
    length   = [int64](Get-Item $zipPath).Length
    alt_text = "Test ZIP"
}

Write-Host "[DEBUG] JSON body for getUploadURLExternal:"
$uploadRequest | ConvertTo-Json -Depth 10 -Compress | Write-Host

Write-Host "[DEBUG] Sending headers:"
Write-Host "Authorization: Bearer $slackToken"
Write-Host "Content-Type: application/json; charset=utf-8"

$uploadUrlResp = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body ($uploadRequest | ConvertTo-Json -Depth 10 -Compress)

Write-Host "[DEBUG] Response:"
$uploadUrlResp | ConvertTo-Json -Depth 10 | Write-Host

if (-not $uploadUrlResp.ok) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($uploadUrlResp.error)"
    exit 1
}

$uploadUrl = $uploadUrlResp.upload_url
$fileId    = $uploadUrlResp.file_id
Write-Host "[INFO] upload_url & file_id received."

# Step 2: Upload via PUT
Write-Host "[INFO] Uploading via PUT..."
Invoke-RestMethod -Method PUT -Uri $uploadUrl -InFile $zipPath -ContentType "application/octet-stream"
Write-Host "[INFO] Upload done."

# Step 3: completeUploadExternal
$completeReq = [PSCustomObject]@{ files = @(@{ id = $fileId }) }
Write-Host "[DEBUG] JSON body for completeUploadExternal:"
$completeReq | ConvertTo-Json -Depth 10 -Compress | Write-Host

Write-Host "[INFO] Sending completeUploadExternal..."
$completeResp = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body ($completeReq | ConvertTo-Json -Depth 10 -Compress)

Write-Host "[DEBUG] completeUploadExternal response:"
$completeResp | ConvertTo-Json -Depth 10 | Write-Host

if (-not $completeResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($completeResp.error)"
    exit 1
}

# Step 4: Lookup user DM channel
Write-Host "[INFO] Looking up user by email: $slackUserEmail"
$userInfo = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/users.lookupByEmail" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ email = $slackUserEmail }

$userId = $userInfo.user.id
Write-Host "[INFO] User ID: $userId"

$channelInfo = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ users = $userId }

$channelId = $channelInfo.channel.id
Write-Host "[INFO] DM Channel ID: $channelId"

# Step 5: Send message
$messageReq = [PSCustomObject]@{
    channel     = $channelId
    text        = "🔔 VPN test ZIP uploaded."
    attachments = @(@{
        fallback   = "vpn_package.zip"
        title      = "VPN ZIP File"
        title_link = "https://files.slack.com/files-pri/$fileId"
    })
}

Write-Host "[DEBUG] JSON body for chat.postMessage:"
$messageReq | ConvertTo-Json -Depth 10 -Compress | Write-Host

Write-Host "[INFO] Sending Slack message..."
$messageResp = Invoke-RestMethod -Method POST `
    -Uri "https://slack.com/api/chat.postMessage" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json; charset=utf-8" `
    -Body ($messageReq | ConvertTo-Json -Depth 10 -Compress)

Write-Host "[DEBUG] chat.postMessage response:"
$messageResp | ConvertTo-Json -Depth 10 | Write-Host

if ($messageResp.ok) {
    Write-Host "[✅ SUCCESS] Slack message sent!"
} else {
    Write-Error "[ERROR] chat.postMessage failed: $($messageResp.error)"
    exit 1
}
