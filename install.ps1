param(
    [Parameter(Position=0)]
    [string]$Target = ""
)

<#
.SYNOPSIS
    Claude Code 鍥藉唴鐩磋繛鍗囩骇瀹㈡埛绔?
.DESCRIPTION
    闇€閰嶅悎涓撴湁 CDK 婵€娲荤爜浣跨敤銆?
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# === 銆愰厤缃尯銆慉PI 璇锋眰缃戝叧鍦板潃 ===
$API_URL = "https://claude-api.lmin.site/"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "鉁?娆㈣繋浣跨敤 Claude Code 鍥藉唴鐩磋繛鍗囩骇鍔╂墜 (Windows鐗? 鉁? -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

# 1. 鐜妫€娴?
$Arch = $env:PROCESSOR_ARCHITECTURE
$PlatformArch = ""

if ($Arch -match "ARM64") {
    $PlatformArch = "arm64"
} elseif ($Arch -eq "AMD64") {
    $PlatformArch = "x64"
} else {
    Write-Host "鉂?涓嶆敮鎸佺殑鏋舵瀯: $Arch. 鐩墠瀹樻柟浠呮敮鎸?Windows x64 鎴?arm64 浜岃繘鍒躲€? -ForegroundColor Red
    Return
}

Write-Host "鉁?鐜妫€娴嬮€氳繃: win32-$PlatformArch" -ForegroundColor Green

# 2. 韬唤楠岃瘉
Write-Host ""
$ConfirmKey = Read-Host "馃攽 璇疯緭鍏ユ偍鐨勬巿鏉冩縺娲荤爜 (CDK) 骞舵寜鍥炶溅"
if (-not $ConfirmKey) {
    Write-Host "鉂?婵€娲荤爜涓嶈兘涓虹┖锛屽凡鍙栨秷瀹夎銆? -ForegroundColor Red
    Return
}

# 3. 纭畾鐩爣璺緞
$ExistingClaude = Get-Command claude.exe -ErrorAction SilentlyContinue
if ($ExistingClaude -and $ExistingClaude.Source) {
    $TargetPath = $ExistingClaude.Source
    $TargetDir = Split-Path $TargetPath -Parent
    Write-Host "`n馃幆 渚︽祴鍒板凡瀛樺湪 Claude 鐜锛屽噯澶囨墽琛屽崌绾т笌瑕嗙洊..." -ForegroundColor Yellow
} else {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\claude"
    $TargetPath = Join-Path $TargetDir "claude.exe"
    Write-Host "`n馃幆 鍑嗗鎵ц鍏ㄦ柊瀹夎锛岀洰鏍囪矾寰? $TargetPath" -ForegroundColor Yellow
}

# 4. 鎻愬彇璁惧鍞竴鏍囪瘑绗?(Machine ID)
$MachineId = ""
try {
    $MachineId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop).MachineGuid
} catch {
    $MachineId = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID
}
if (-not $MachineId) {
    $MachineId = $env:COMPUTERNAME
}

# 5. 鎺堟潈楠岃瘉涓庨厤缃尮閰?
Write-Host "馃攳 姝ｅ湪杩炴帴浜戠鏈嶅姟鍣ㄩ獙璇佹巿鏉冨苟鍖归厤鍔犻€熻妭鐐?.." -ForegroundColor Yellow
$RequestUrl = "$API_URL/?key=$ConfirmKey&os=win32&arch=$PlatformArch&machine_id=$MachineId"
if ($Target) {
    $RequestUrl += "&target=$Target"
}

try {
    $ApiResponse = Invoke-RestMethod -Uri $RequestUrl -UseBasicParsing
} catch {
    Write-Host "鉂?杩炴帴浜戠澶辫触鎴栨縺娲荤爜鏃犳晥: $($_.Exception.Message)" -ForegroundColor Red
    Return
}

if (-not $ApiResponse.success) {
    Write-Host $ApiResponse.message -ForegroundColor Red
    Return
}

Write-Host $ApiResponse.message -ForegroundColor Green
$TarballUrl = $ApiResponse.tarball
$RemoteVersion = $ApiResponse.version
Write-Host "鉁?浜戠鍒嗛厤鏈€鏂扮増鏈负 v$RemoteVersion" -ForegroundColor Green

# 5. 鏈湴鐗堟湰姣斿
if (Test-Path $TargetPath) {
    $LocalVersionString = & $TargetPath --version 2>$null
    if ($LocalVersionString -match '(\d+\.\d+\.\d+)') {
        $LocalVersion = $matches[1]
        if ($LocalVersion -eq $RemoteVersion) {
            Write-Host "====================================================" -ForegroundColor Cyan
            Write-Host "鉁?妫€娴嬪埌褰撳墠宸叉槸鏈€鏂扮増鏈?v$LocalVersion锛屾棤闇€閲嶅鍗囩骇锛? -ForegroundColor Green
    Return
        }
    }
}

# 6. 涓嬭浇瀹夎鍖?
$TmpDir = Join-Path $env:TEMP "claude_updater_tmp_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
$TgzPath = Join-Path $TmpDir "payload.tgz"

Write-Host "馃摜 姝ｅ湪閫氳繃楠ㄥ共缃戦珮閫熶笅杞藉師鐢熶簩杩涘埗鍖?.." -ForegroundColor Yellow
Invoke-WebRequest -Uri $TarballUrl -OutFile $TgzPath -UseBasicParsing

# 7. 瑙ｅ帇缂╁寘
Write-Host "馃摝 姝ｅ湪鎵ц瑙ｅ帇涓庝簩杩涘埗鎻愬彇..." -ForegroundColor Yellow
Set-Location -Path $TmpDir
try {
    tar.exe -zxf payload.tgz
} catch {
    Write-Host "鉂?瑙ｅ帇澶辫触锛岃纭繚绯荤粺鏀寔 tar 鍛戒护: $_" -ForegroundColor Red
    Remove-Item -Recurse -Force $TmpDir
    Return
}

$ExtractedExe = Join-Path $TmpDir "package\claude.exe"
if (-not (Test-Path $ExtractedExe)) {
    Write-Host "鉂?瑙ｅ帇浜х墿缁撴瀯寮傚父锛屾湭鍙戠幇 package\claude.exe" -ForegroundColor Red
    Remove-Item -Recurse -Force $TmpDir
    Return
}

# 8. 鏍稿績瀹夎閫昏緫
Write-Host "馃殌 姝ｅ湪鎵ц浜岃繘鍒舵枃浠跺畨瑁呬笌鏉冮檺閰嶇疆..." -ForegroundColor Yellow
try {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path $ExtractedExe -Destination $TargetPath -Force
    Write-Host "鉁?浜岃繘鍒舵枃浠跺凡鎴愬姛瀹夎鍒? $TargetPath" -ForegroundColor Green

    # 9. 鐜鍙橀噺閰嶇疆
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPath -split ';' -notcontains $TargetDir) {
        [Environment]::SetEnvironmentVariable("Path", $UserPath + ";" + $TargetDir, "User")
        Write-Host "鈿狅笍 宸插皢 $TargetDir 娣诲姞鍒版偍鐨勭敤鎴?PATH 鐜鍙橀噺涓紝璇烽噸鍚粓绔娇鍏剁敓鏁堛€? -ForegroundColor Yellow
    }

    # 10. 鍒濆鍖栭厤缃?
    Write-Host "馃攧 姝ｅ湪閰嶇疆鏈湴鍐呮牳鐜 (缁曡繃瀹樻柟鏋佹參鐨勫畨瑁呰妭鐐?..." -ForegroundColor Yellow
    
    # 绂佺敤鑷甫鑷姩鏇存柊锛岄伩鍏嶅悗鍙伴潤榛樿繛鎺ュ畼鏂规湇鍔″櫒瀵艰嚧鎸傝捣
    & $TargetPath config set autoUpdater false 2>$null
    
    # 楠岃瘉瀹夎鏄惁鎴愬姛
    $installedVersion = & $TargetPath --version 2>$null
    if ($installedVersion) {
        Write-Host "鉁?鏈湴鍐呮牳宸插氨缁? $installedVersion" -ForegroundColor Green
        $installExitCode = 0
    } else {
        $installExitCode = 1
    }
} finally {
    Set-Location -Path $env:USERPROFILE
    Start-Sleep -Seconds 2
    if (Test-Path $TmpDir) {
        Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
    }
}

if ($installExitCode -ne 0 -and $null -ne $installExitCode) {
    Write-Host "鉂?瀹樻柟鍐呮牳鍒濆鍖栧紓甯?(Exit Code: $installExitCode)" -ForegroundColor Red
    exit $installExitCode
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "馃帀 閮ㄧ讲瀹屾垚锛佸浗鍐呯洿杩炰綋楠屽凡灏辩华銆? -ForegroundColor Green
