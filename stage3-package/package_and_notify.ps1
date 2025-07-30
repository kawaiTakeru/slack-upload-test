
$ErrorActionPreference = "Stop"
Write-Host "[DEBUG] Start upload script."

# 環境変数確認
Write-Host "[DEBUG] Available SLACK env vars:"
Get-ChildItem Env: | Where-Object { $_.Name -like "SLACK*" } | ForEach-Object { Write-Host "[DEBUG] $($_.Name) = $($_.Value)" }

$slackToken = $env:SLACK_BOT_TOKEN
if ([string]::IsNullOrEmpty($slackToken)) {
    Write-Error "[ERROR] SLACK_BOT_TOKEN is not set"
    exit 1
}
Write-Host "[DEBUG] Slack token starts with: $($slackToken.Substring(0,10))..."

$workingDir = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFile = Join-Path $workingDir "dummy.txt"
$zipFile = Join-Path $workingDir "vpn_package.zip"

Write-Host "[INFO] Creating dummy file..."
Set-Content -Path $dummyFile -Value "dummy"
Write-Host "[INFO] Compressing to ZIP..."
Compress-Archive -Path $dummyFile -DestinationPath $zipFile -Force

$size = (Get-Item $zipFile).Length
Write-Host "[DEBUG] ZIP file size (bytes): $size"

$uploadBody = @{
    filename = [System.IO.Path]::GetFileName($zipFile)
    length = $size
    alt_text = "Test ZIP file"
}
$uploadBodyJson = $uploadBody | ConvertTo-Json -Depth 10
Write-Host "[DEBUG] JSON body for files.getUploadURLExternal:`n$uploadBodyJson"

try {
    Write-Host "[INFO] Calling files.getUploadURLExternal..."
    $uploadResp = Invoke-RestMethod -Method Post `
        -Uri "https://slack.com/api/files.getUploadURLExternal" `
        -Headers @{ Authorization = "Bearer $slackToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body $uploadBodyJson
}
catch {
    Write-Error "[ERROR] API call failed: $_"
    exit 1
}
Write-Host "[DEBUG] Response from getUploadURLExternal:`n$($uploadResp | ConvertTo-Json -Depth 10)"

if (-not $uploadResp.ok -or -not $uploadResp.upload_url -or -not $uploadResp.file_id) {
    Write-Error "[ERROR] getUploadURLExternal failed: $($uploadResp.error)"
    exit 1
}

$uploadUrl = $uploadResp.upload_url
$fileId = $uploadResp.file_id
Write-Host "[INFO] upload_url: $uploadUrl"
Write-Host "[INFO] file_id: $fileId"

try {
    Write-Host "[INFO] Sending file via HTTP PUT..."
    $putResp = Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFile -ContentType "application/octet-stream"
    Write-Host "[INFO] HTTP PUT succeeded."
}
catch {
    Write-Error "[ERROR] File upload (PUT) failed: $_"
    exit 1
}

$completeReq = @{
    files = @(@{ id = $fileId })
    channel_id = $null  # channel_id を通知先があれば設定
    initial_comment = "VPN ZIP uploaded"
}
$completeJson = $completeReq | ConvertTo-Json -Depth 10
Write-Host "[DEBUG] JSON body for files.completeUploadExternal:`n$completeJson"

try {
    Write-Host "[INFO] Calling files.completeUploadExternal..."
    $completeResp = Invoke-RestMethod -Method Post `
        -Uri "https://slack.com/api/files.completeUploadExternal" `
        -Headers @{ Authorization = "Bearer $slackToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body $completeJson
}
catch {
    Write-Error "[ERROR] completeUploadExternal call failed: $_"
    exit 1
}
Write-Host "[DEBUG] Response from completeUploadExternal:`n$($completeResp | ConvertTo-Json -Depth 10)"

if (-not $completeResp.ok) {
    Write-Error "[ERROR] completeUploadExternal failed: $($completeResp.error)"
    exit 1
}

Write-Host "[✅ SUCCESS] File upload flow completed!"
