
$ErrorActionPreference = "Stop"
Write-Host "[DEBUG] SLACK env vars:"
Get-ChildItem Env:SLACK* | ForEach-Object { Write-Host "[DEBUG] $_" }

$token = $env:SLACK_BOT_TOKEN
if (-not $token) { Write-Error "SLACK_BOT_TOKEN is null"; exit 1 }
Write-Host "[DEBUG] Slack token starts with: $($token.Substring(0,10))..."

$dummy = Join-Path $PSScriptRoot "dummy.txt"; Set-Content -Path $dummy "dummy"
$zip = Join-Path $PSScriptRoot "vpn_package.zip"; Compress-Archive -Path $dummy -DestinationPath $zip -Force
$size = (Get-Item $zip).Length
Write-Host "[DEBUG] ZIP size: $size bytes"

$body = @{
  filename = [IO.Path]::GetFileName($zip)
  length   = $size
  alt_txt  = "Test ZIP file"
}
$json = $body | ConvertTo-Json
Write-Host "[DEBUG] Payload for getUploadURLExternal:`n$json"

$resp = Invoke-RestMethod -Method Post -Uri "https://slack.com/api/files.getUploadURLExternal" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/x-www-form-urlencoded; charset=utf-8" } `
  -Body ("filename={0}&length={1}" -f [Uri]::EscapeDataString($body.filename), $body.length)

Write-Host "[DEBUG] Response from getUploadURLExternal:"
Write-Host ($resp | ConvertTo-Json)

if (-not $resp.ok) { Write-Error "getUploadURLExternal failed: $($resp.error)"; exit 1 }

$uploadUrl = $resp.upload_url; $fileId = $resp.file_id
Write-Host "[INFO] Upload URL received. File ID: $fileId"

Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zip -ContentType "application/octet-stream"
Write-Host "[INFO] File upload PUT complete"

$complete = @{
  files = @(@{ id = $fileId })
  channel_id = $null
  initial_comment = "VPN ZIP uploaded"
} | ConvertTo-Json

Write-Host "[DEBUG] Payload for completeUploadExternal:`n$complete"
$compResp = Invoke-RestMethod -Method Post -Uri "https://slack.com/api/files.completeUploadExternal" `
  -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
  -Body $complete

Write-Host "[DEBUG] completeUploadExternal response:"
Write-Host ($compResp | ConvertTo-Json)
if (-not $compResp.ok) { Write-Error "completeUploadExternal failed: $($compResp.error)"; exit 1 }

Write-Host "[✅ SUCCESS] Upload workflow completed!"
