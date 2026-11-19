# ============================================================
# XRead WSL2 热点/LAN 访问 一键端口转发脚本
# 用法：Windows 开始菜单搜索 PowerShell -> 右键“以管理员身份运行”
#       把本文件内容粘贴执行，或 .\xread-wsl2-lan.ps1（若提示禁止脚本，
#       先执行 Set-ExecutionPolicy -Scope Process Bypass）
# 作用：把 Windows 的 7777 端口转发到 WSL2 里运行的 XRead。
#       这样连 PC 热点的设备可通过 http://<PC热点IP>:7777 访问。
# 注意：WSL 的 IP 每次 wsl --shutdown / 重启后会变，IP 变了就重新跑一次本脚本。
# ============================================================

$ErrorActionPreference = 'Stop'
$Port = 7777
$Distro = 'Ubuntu'

Write-Host "=== XRead WSL2 热点访问配置 ===" -ForegroundColor Cyan

# 1. 获取 WSL IP（用 -- 传递，取第一个地址）
$wslRaw = (& wsl.exe -d $Distro -- hostname -I 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($wslRaw)) {
    Write-Host "无法获取 WSL IP，请确认 Ubuntu 已启动、XRead 正在运行。" -ForegroundColor Red
    exit 1
}
$wslIp = ($wslRaw -split '\s+')[0]
Write-Host "WSL IP: $wslIp"

# 2. 删除旧规则（幂等，避免 IP 变化后残留失效规则）
& netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$Port 2>$null | Out-Null

# 3. 添加新规则：Windows 全网卡 7777 -> WSL 7777
& netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$Port connectaddress=$wslIp connectport=$Port
Write-Host "端口转发: 0.0.0.0:$($Port) -> $($wslIp):$($Port)" -ForegroundColor Green

# 4. 放行 Windows 防火墙入站
$ruleName = "XRead WSL $Port"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    Write-Host "已添加防火墙入站规则: $ruleName" -ForegroundColor Green
} else {
    Write-Host "防火墙规则已存在: $ruleName"
}

# 5. 显示当前转发规则
Write-Host "`n当前 portproxy 规则:" -ForegroundColor Cyan
& netsh interface portproxy show v4tov4

# 6. 列出热点网卡 IP（Windows 移动热点通常是 192.168.137.1）
Write-Host "`n检测热点网卡 IP (192.168.137.*):" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -like '192.168.137.*' } |
  ForEach-Object { Write-Host "  网卡 [$($_.InterfaceAlias)]  IP: $($_.IPAddress)" -ForegroundColor Yellow }

Write-Host "`n完成。请在设备浏览器访问: http://192.168.137.1:$($Port)" -ForegroundColor Green
Write-Host "若打不开：确认 XRead 在 WSL 中运行(.env 的 SERVER_HOST=0.0.0.0)、设备连的是本 PC 热点。" -ForegroundColor DarkYellow
