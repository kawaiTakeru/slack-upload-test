# 環境変数からWebhookやユーザー情報などを取得
$slackToken = $env:SLACK_BOT_TOKEN
$slackUserEmail = $env:SLACK_USER_EMAIL
$workingDir = "$(System.DefaultWorkingDirectory)/stage3-package"
$dummyFilePath = "$workingDir/dummy.txt"
$zipFilePath = "$workingDir/vpn_package.zip"

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
$uploadUrlResp = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/files.getUploadURLExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body (ConvertTo-Json $uploadRequest)

$uploadUrl = $uploadUrlResp.upload_url
$fileId = $uploadUrlResp.file_id

# ② ファイルをPUTアップロード
Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $zipFilePath -ContentType "application/zip"

# ③ アップロード完了通知
$completeReq = @{
    files = @(@{
        id        = $fileId
        title     = "Test VPN ZIP"
        alt_text  = "Test ZIP uploaded"
    })
}
Invoke-RestMethod -Method POST -Uri "https://slack.com/api/files.completeUploadExternal" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body (ConvertTo-Json $completeReq)

# ④ ユーザーDMチャンネルを開く
$userInfo = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/users.lookupByEmail" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ email = $slackUserEmail }

$userId = $userInfo.user.id
$channelResp = Invoke-RestMethod -Method POST -Uri "https://slack.com/api/conversations.open" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -Body @{ users = $userId }

$channelId = $channelResp.channel.id

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
Invoke-RestMethod -Method POST -Uri "https://slack.com/api/chat.postMessage" `
    -Headers @{ Authorization = "Bearer $slackToken" } `
    -ContentType "application/json" `
    -Body (ConvertTo-Json $messageReq)
