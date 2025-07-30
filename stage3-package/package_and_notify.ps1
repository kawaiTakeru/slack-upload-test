$ErrorActionPreference = "Stop"

Write-Host "[DEBUG] Available SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $_" }

$slackToken = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL

if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is null in script"
    exit 1
} else {
    Write-Host "[DEBUG] Slack token starts with: $($slackToken.Substring(0,10))..."
}

$workingDir = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFile = "$workingDir\dummy.txt"
$zipFile = "$workingDir\vpn_package.zip"

Write-Host "[INFO] Creating dummy.txt..."
Set-Content -Path $dummyFile -Value "dummy"

Write-Host "[INFO] Compressing to ZIP..."
Compress-Archive -Path $dummyFile -DestinationPath $zipFile -Force

$size = (Get-Item $zipFile).Length
Write-Host "[DEBUG] Zip file size (bytes): $size"

$payload = @{
    filename = 'vpn_package.zip'
    length   = $size
    alt_txt   = 'Test ZIP'
}

Write-Host "[DEBUG] Requesting upload URL with form data:"
$payload | ConvertTo-Json | Write-Host

$uploadResp = Invoke-RestMethod -Method Post `
    -Uri https://slack.com/api/files.getUploadURLExternal `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body $payload

Write-Host "[DEBUG] getUploadURLExternal response:"
$uploadResp | ConvertTo-Json | Write-Host

if (-not $uploadResp.ok) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($uploadResp.error); metadata: $($uploadResp.response_metadata.messages -join ', ')"
    exit 1
}

$uploadUrl = $uploadResp.upload_url
$fileId    = $uploadResp.file_id
Write-Host "[INFO] Upload URL: $uploadUrl"
Write-Host "[INFO] File ID: $fileId"

Write-Host "[INFO] Uploading via POST to pre-signed URL..."
$upl = Invoke-RestMethod -Method Post `
    -Uri $uploadUrl `
    -InFile $zipFile `
    -ContentType 'application/octet-stream'

Write-Host "[INFO] Upload step returned (should be HTTP 200)."

$completeBody = @{
    files = @(@{ id = $fileId })
    # optional:
    # channel_id = $channelId
    # initial_comment = "Here is your ZIP"
}

Write-Host "[INFO] Completing upload externally..."
$completeResp = Invoke-RestMethod -Method Post `
    -Uri https://slack.com/api/files.completeUploadExternal `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType 'application/json; charset=utf‑8' `
    -Body (ConvertTo-Json $completeBody -Depth 10)

Write-Host "[DEBUG] completeUploadExternal response:"
$completeResp | ConvertTo-Json | Write-Host

if (-not $completeResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($completeResp.error)"
    exit 1
}

Write-Host "[✅ SUCCESS] File uploaded and completed, file_id: $fileId"

# 以下は DM 送信処理など続きます...
