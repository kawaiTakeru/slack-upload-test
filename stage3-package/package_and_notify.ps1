$ErrorActionPreference = "Stop"

Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $($_.Name) = $($_.Value)" }

$token = $env:SLACK_BOT_TOKEN
if (-not $token) {
    Write-Error "SLACK_BOT_TOKEN is null"
    exit 1
}
Write-Host "[DEBUG] Slack token starts with: $($token.Substring(0,10))..."

$dummy = Join-Path $PSScriptRoot "dummy.txt"
Set-Content -Path $dummy -Value "dummy"

$zip = Join-Path $PSScriptRoot "vpn_package.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $dummy -DestinationPath $zip -Force

$size = (Get-Item $zip).Length
Write-Host "[DEBUG] ZIP size: $size bytes"

$body = @{
    filename = [IO.Path]::GetFileName($zip)
    length   = $size
    alt_text = "Test ZIP file"
}

Write-Host "[DEBUG] Payload for getUploadURLExternal:`n$(ConvertTo-Json $body)"

# Form-urlencode payload
$form = "filename=$([Uri]::EscapeDataString($body.filename))&length=$([Uri]::EscapeDataString($body.length.ToString()))"
Write-Host "[DEBUG] Form-body: $form"

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
Write-Host "[INFO] Upload URL and File ID received: $fileId"

# Upload file
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zip -ContentType "application/octet-stream"
Write-Host "[INFO] File upload (PUT) completed"

$completeBody = @{
    files            = @(@{ id = $fileId })
    initial_comment  = "VPN ZIP uploaded"
}

$completeJson = $completeBody | ConvertTo-Json -Depth 5
Write-Host "[DEBUG] Payload for completeUploadExternal:`n$completeJson"

$compResp = Invoke-RestMethod -Method Post `
    -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
    -Body $completeJson

Write-Host "[DEBUG] Response from completeUploadExternal:"
Write-Host (ConvertTo-Json $compResp -Depth 5)

if (-not $compResp.ok) {
    Write-Error "completeUploadExternal failed: $($compResp.error)"
    exit 1
}

Write-Host "[✅ SUCCESS] Upload workflow completed!"
