param(
    [Parameter(Position=0)]
    [string]$Target = ""
)

<#
.SYNOPSIS
    Claude Code 国内直连升级客户端
.DESCRIPTION
    需配合专有 CDK 激活码使用。
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# === 【配置区】API 请求网关地址 ===
$API_URL = "https://claude-api.lmin.site/"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "✨ 欢迎使用 Claude Code 国内直连升级助手 (Windows版) ✨" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

# 1. 环境检测
$Arch = $env:PROCESSOR_ARCHITECTURE
$PlatformArch = ""

if ($Arch -match "ARM64") {
    $PlatformArch = "arm64"
} elseif ($Arch -eq "AMD64") {
    $PlatformArch = "x64"
} else {
    Write-Host "❌ 不支持的架构: $Arch. 目前官方仅支持 Windows x64 或 arm64 二进制。" -ForegroundColor Red
    exit 1
}

Write-Host "✓ 环境检测通过: win32-$PlatformArch" -ForegroundColor Green

# 2. 身份验证
Write-Host ""
$ConfirmKey = Read-Host "🔑 请输入您的授权激活码 (CDK) 并按回车"
if (-not $ConfirmKey) {
    Write-Host "❌ 激活码不能为空，已取消安装。" -ForegroundColor Red
    exit 1
}

# 3. 确定目标路径
$ExistingClaude = Get-Command claude.exe -ErrorAction SilentlyContinue
if ($ExistingClaude -and $ExistingClaude.Source) {
    $TargetPath = $ExistingClaude.Source
    $TargetDir = Split-Path $TargetPath -Parent
    Write-Host "`n🎯 侦测到已存在 Claude 环境，准备执行升级与覆盖..." -ForegroundColor Yellow
} else {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\claude"
    $TargetPath = Join-Path $TargetDir "claude.exe"
    Write-Host "`n🎯 准备执行全新安装，目标路径: $TargetPath" -ForegroundColor Yellow
}

# 4. 提取设备唯一标识符 (Machine ID)
$MachineId = ""
try {
    $MachineId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop).MachineGuid
} catch {
    $MachineId = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID
}
if (-not $MachineId) {
    $MachineId = $env:COMPUTERNAME
}

# 5. 授权验证与配置匹配
Write-Host "🔍 正在连接云端服务器验证授权并匹配加速节点..." -ForegroundColor Yellow
$RequestUrl = "$API_URL/?key=$ConfirmKey&os=win32&arch=$PlatformArch&machine_id=$MachineId"
if ($Target) {
    $RequestUrl += "&target=$Target"
}

try {
    $ApiResponse = Invoke-RestMethod -Uri $RequestUrl -UseBasicParsing
} catch {
    Write-Host "❌ 连接云端失败或激活码无效: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $ApiResponse.success) {
    Write-Host $ApiResponse.message -ForegroundColor Red
    exit 1
}

Write-Host $ApiResponse.message -ForegroundColor Green
$TarballUrl = $ApiResponse.tarball
$RemoteVersion = $ApiResponse.version
Write-Host "✓ 云端分配最新版本为 v$RemoteVersion" -ForegroundColor Green

# 5. 本地版本比对
if (Test-Path $TargetPath) {
    $LocalVersionString = & $TargetPath --version 2>$null
    if ($LocalVersionString -match '(\d+\.\d+\.\d+)') {
        $LocalVersion = $matches[1]
        if ($LocalVersion -eq $RemoteVersion) {
            Write-Host "====================================================" -ForegroundColor Cyan
            Write-Host "✨ 检测到当前已是最新版本 v$LocalVersion，无需重复升级！" -ForegroundColor Green
            exit 0
        }
    }
}

# 6. 下载安装包
$TmpDir = Join-Path $env:TEMP "claude_updater_tmp_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
$TgzPath = Join-Path $TmpDir "payload.tgz"

Write-Host "📥 正在通过骨干网高速下载原生二进制包..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $TarballUrl -OutFile $TgzPath -UseBasicParsing

# 7. 解压缩包
Write-Host "📦 正在执行解压与二进制提取..." -ForegroundColor Yellow
Set-Location -Path $TmpDir
try {
    tar.exe -zxf payload.tgz
} catch {
    Write-Host "❌ 解压失败，请确保系统支持 tar 命令: $_" -ForegroundColor Red
    Remove-Item -Recurse -Force $TmpDir
    exit 1
}

$ExtractedExe = Join-Path $TmpDir "package\claude.exe"
if (-not (Test-Path $ExtractedExe)) {
    Write-Host "❌ 解压产物结构异常，未发现 package\claude.exe" -ForegroundColor Red
    Remove-Item -Recurse -Force $TmpDir
    exit 1
}

# 8. 核心安装逻辑
Write-Host "🚀 正在执行二进制文件安装与权限配置..." -ForegroundColor Yellow
try {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path $ExtractedExe -Destination $TargetPath -Force
    Write-Host "✓ 二进制文件已成功安装到: $TargetPath" -ForegroundColor Green

    # 9. 环境变量配置
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPath -split ';' -notcontains $TargetDir) {
        [Environment]::SetEnvironmentVariable("Path", $UserPath + ";" + $TargetDir, "User")
        Write-Host "⚠️ 已将 $TargetDir 添加到您的用户 PATH 环境变量中，请重启终端使其生效。" -ForegroundColor Yellow
    }

    # 10. 初始化配置
    Write-Host "🔄 正在调用官方内核进行终端集成与环境配置..." -ForegroundColor Yellow
    if ($Target) {
        & $TargetPath install $Target
    } else {
        & $TargetPath install
    }
    $installExitCode = $LASTEXITCODE
} finally {
    Set-Location -Path $env:USERPROFILE
    Start-Sleep -Seconds 2
    if (Test-Path $TmpDir) {
        Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
    }
}

if ($installExitCode -ne 0 -and $null -ne $installExitCode) {
    Write-Host "❌ 官方内核初始化异常 (Exit Code: $installExitCode)" -ForegroundColor Red
    exit $installExitCode
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "🎉 部署完成！国内直连体验已就绪。" -ForegroundColor Green
