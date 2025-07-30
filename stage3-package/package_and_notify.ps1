# 環境変数からWebhookやユーザー情報などを取得
$slackToken = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL
$workingDir = "$env:BUILD_SOURCESDIRECTORY\stage3-package"
$dummyFilePath = "$workingDir\dummy.txt"
$zipFilePath = "$workingDir\vpn_package.zip"

# ダミーファイル作成
Set-Content -Path $dummyFilePath -Value "This is a dummy file for Slack upload test."

# ZIP作成
Compress-Archive -Path $dummyFilePath -DestinationPath $zipFilePath -Force

# ① アップロードURL取得
$uploadRequest = @{
    filename = "vpn_package.zip"
    length   = (Get-Item $zipFilePath).Length
    alt_text = "Test ZIP"
}
Write-Host "📤 files.getUploadURLExternal 送信中..."
$uploadUrlResp = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body (ConvertTo-Json $uploadRequest -Depth 10)

$uploadUrl = $uploadUrlResp.upload_url
$fileId = $uploadUrlResp.file_id
Write-Host "✅ upload_url: $uploadUrl"
Write-Host "✅ file_id: $fileId"

# ② ファイルをPUTアップロード
Write-Host "📦 PUTアップロード開始..."
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFilePath -ContentType "application/zip"
Write-Host "✅ アップロード完了"

# ③ アップロード完了通知
$completeReq = @{
    files = @(@{
        id        = $fileId
        title     = "Test VPN ZIP"
        alt_text  = "Test ZIP uploaded"
    })
}
Write-Host "📨 files.completeUploadExternal 実行中..."
Invoke-RestMethod -Method POST -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body (ConvertTo-Json $completeReq -Depth 10)
Write-Host "✅ アップロード完了通知 OK"

# ④ ユーザーDMチャンネルを開く
Write-Host "🔍 Slack ID lookup 開始..."
$userInfo = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/users.lookupByEmail" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ email = $slackUserEmail }

$userId = $userInfo.user.id
Write-Host "✅ Slack user ID: $userId"

$channelResp = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ users = $userId }

$channelId = $channelResp.channel.id
Write-Host "✅ DM channel ID: $channelId"

# ⑤ メッセージ送信
$messageReq = @{
    channel = $channelId
    text    = "🔔 VPNテストファイルをアップロードしました"
    attachments = @(
        @{
            fallback = "vpn_package.zip"
            title = "VPN ZIP File"
            title_link = "https://files.slack.com/files-pri/$fileId"
        }
    )
}
Write-Host "📩 メッセージ送信中..."
Invoke-RestMethod -Method POST -Uri "https://slack.com/api/chat.postMessage" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body (ConvertTo-Json $messageReq -Depth 10)
Write-Host "✅ メッセージ送信成功！"
