#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version,
    [string]$LocalPath,
    [string]$InstallDir,
    [switch]$NoPath,
    [switch]$ContextMenu,
    [switch]$RemoveContextMenu
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$script:RepoOwner = 'f97214'
$script:RepoName = 'mypi'
$script:DefaultInstallDir = Join-Path $env:LOCALAPPDATA 'Programs\pi'
$script:PathEnvName = 'Path'
$script:PathScope = 'User'
$script:BuildCommandHint = 'scripts/build-binaries.sh --platform windows-x64'
if ($PSCommandPath) { $script:InstallerDir = Split-Path -Parent $PSCommandPath } else { $script:InstallerDir = '' }
$script:MenuClassesRoot = if ($env:PI_INSTALLER_MENU_ROOT) { $env:PI_INSTALLER_MENU_ROOT } else { 'HKCU:\Software\Classes' }

function Get-TargetArch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { throw "Unsupported CPU architecture: $env:PROCESSOR_ARCHITECTURE (supported: AMD64, ARM64)" }
    }
}

function Resolve-LatestVersion {
    param(
        [string]$ApiUrl,
        [string]$Json
    )
    if ($Json) {
        $response = $Json | ConvertFrom-Json
    } else {
        $response = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'pi-installer' } -UseBasicParsing
    }
    return $response.tag_name -replace '^v', ''
}

function Get-ReleaseAssetUrls {
    param(
        [string]$Version,
        [string]$Arch
    )
    $base = "https://github.com/$($script:RepoOwner)/$($script:RepoName)/releases/download/v$Version"
    return [PSCustomObject]@{
        ZipUrl  = "$base/pi-windows-$Arch.zip"
        SumsUrl = "$base/SHA256SUMS"
    }
}

function Test-AssetHash {
    param(
        [string]$ZipPath,
        [string]$SumsPath,
        [string]$Arch
    )
    if (-not (Test-Path -LiteralPath $SumsPath)) { return $false }
    $expectedLine = Select-String -LiteralPath $SumsPath -Pattern ([regex]::Escape("pi-windows-$Arch.zip")) | Select-Object -First 1
    if (-not $expectedLine) { return $false }
    $expected = ($expectedLine.Line.Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLower()
    return $actual -eq $expected
}

function Merge-UserPathValue {
    param(
        [string]$Existing,
        [string]$InstallDir
    )
    $normalized = $InstallDir.TrimEnd('\')
    $entries = @($Existing -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ })
    foreach ($entry in $entries) {
        if ($entry -ieq $normalized) { return $null }
    }
    if ([string]::IsNullOrWhiteSpace($Existing)) { return $normalized }
    return $Existing + ';' + $normalized
}

function Set-UserPathEntry {
    param(
        [string]$InstallDir,
        [string]$EnvVarName = 'Path',
        [string]$Scope = 'User'
    )
    $existing = [Environment]::GetEnvironmentVariable($EnvVarName, $Scope)
    $merged = Merge-UserPathValue -Existing $existing -InstallDir $InstallDir
    if ($null -eq $merged) {
        Write-Host "PATH 已包含 $InstallDir，不重複加入"
        return
    }
    [Environment]::SetEnvironmentVariable($EnvVarName, $merged, $Scope)
    Write-Host "已將 $InstallDir 加入 $Scope 範圍的 $EnvVarName（新開的殼層才會生效）"
}

function Resolve-MenuShellPath {
    param([string]$PwshCommand = 'pwsh')
    $candidate = Get-Command $PwshCommand -ErrorAction SilentlyContinue
    if ($candidate) { return $candidate.Source }
    return Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

function Set-ContextMenu {
    param(
        [string]$PiExePath,
        [string]$ShellPath,
        [string]$ClassesRoot = $script:MenuClassesRoot
    )
    if (-not $ShellPath) { $ShellPath = Resolve-MenuShellPath }
    $entries = @(
        @{ RelativePath = 'Directory\shell\mypi'; Target = '%1' },
        @{ RelativePath = 'Directory\Background\shell\mypi'; Target = '%V' }
    )
    foreach ($entry in $entries) {
        $key = Join-Path $ClassesRoot $entry.RelativePath
        $commandKey = Join-Path $key 'command'
        New-Item -Path $key -Force | Out-Null
        Set-Item -Path $key -Value '用 MYPI 開啟'
        Set-ItemProperty -Path $key -Name 'Icon' -Value $PiExePath
        New-Item -Path $commandKey -Force | Out-Null
        $command = '"{0}" -NoLogo -NoExit -Command "Set-Location -LiteralPath \"{1}\"; & ''{2}''"' -f $ShellPath, $entry.Target, $PiExePath
        Set-Item -Path $commandKey -Value $command
    }
}

function Remove-ContextMenu {
    param([string]$ClassesRoot = $script:MenuClassesRoot)
    foreach ($relativePath in @('Directory\shell\mypi', 'Directory\Background\shell\mypi')) {
        Remove-Item -LiteralPath (Join-Path $ClassesRoot $relativePath) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$Default = ''
    )
    if ([Console]::IsInputRedirected) {
        Write-Host $Prompt
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { throw "標準輸入已結束，無法取得輸入" }
        $line = $line.Trim()
    } else {
        $line = (Read-Host -Prompt $Prompt).Trim()
    }
    if ([string]::IsNullOrEmpty($line)) { return $Default }
    return $line
}

function Get-ValidatedLocalSource {
    param(
        [string]$Kind,
        [string]$Suggested
    )
    while ($true) {
        $path = Get-UserInput -Prompt "輸入本機 $Kind 路徑" -Default $Suggested
        if ($Kind -eq 'zip') {
            if ((Test-Path -LiteralPath $path -PathType Leaf) -and $path -like '*.zip') { return $path }
            Write-Host "找不到 zip 檔：$path（需為存在的 .zip 檔，例如 $script:BuildCommandHint 的產物）" -ForegroundColor Yellow
        } else {
            if ((Test-Path -LiteralPath $path -PathType Container) -and (Test-Path -LiteralPath (Join-Path $path 'pi.exe'))) { return $path }
            Write-Host "目錄不存在或缺少 pi.exe：$path（請先執行 $script:BuildCommandHint）" -ForegroundColor Yellow
        }
    }
}

function Test-RepoRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'package.json') -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'packages\coding-agent') -PathType Container)) { return $false }
    return $true
}

function Assert-BuildTool {
    param(
        [string]$ToolName,
        [string]$Hint
    )
    if (-not (Get-Command $ToolName -ErrorAction SilentlyContinue)) {
        throw "缺少建置工具：$ToolName（安裝方式：$Hint）"
    }
}

function Invoke-BuildStep {
    param(
        [string]$WorkingDirectory,
        [string]$FileName,
        [string[]]$Arguments
    )
    $candidates = @(Get-Command $FileName -All -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 0) { throw "找不到指令：$FileName" }
    $native = $candidates | Where-Object { $_.Source -like '*.cmd' -or $_.Source -like '*.exe' } | Select-Object -First 1
    if ($native) {
        $proc = Start-Process -FilePath $native.Source -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "建置步驟失敗：$FileName $($Arguments -join ' ')（退出碼 $($proc.ExitCode)）"
        }
        return
    }
    $ps1 = $candidates | Select-Object -First 1
    Push-Location $WorkingDirectory
    try {
        & $ps1.Source @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
        if ($LASTEXITCODE -ne 0) {
            throw "建置步驟失敗：$FileName $($Arguments -join ' ')（退出碼 $LASTEXITCODE）"
        }
    } finally {
        Pop-Location
    }
}

function Copy-StagedAssets {
    param(
        [string]$RepoRoot,
        [string]$Arch,
        [string]$OutDir
    )
    $ca = Join-Path $RepoRoot 'packages\coding-agent'
    if (Test-Path -LiteralPath $OutDir) {
        Get-ChildItem -LiteralPath $OutDir -Force | Where-Object { $_.Name -ne 'pi.exe' } | Remove-Item -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    foreach ($f in @('package.json', 'README.md', 'CHANGELOG.md')) {
        Copy-Item -LiteralPath (Join-Path $ca $f) -Destination $OutDir
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'node_modules\@silvia-odwyer\photon-node\photon_rs_bg.wasm') -Destination $OutDir
    New-Item -ItemType Directory -Path (Join-Path $OutDir 'theme') -Force | Out-Null
    Copy-Item -Path (Join-Path $ca 'dist\modes\interactive\theme\*.json') -Destination (Join-Path $OutDir 'theme')
    New-Item -ItemType Directory -Path (Join-Path $OutDir 'assets') -Force | Out-Null
    Copy-Item -Path (Join-Path $ca 'dist\modes\interactive\assets\*') -Destination (Join-Path $OutDir 'assets')
    Copy-Item -LiteralPath (Join-Path $ca 'dist\core\export-html') -Destination $OutDir -Recurse
    Copy-Item -LiteralPath (Join-Path $ca 'docs') -Destination $OutDir -Recurse
    Copy-Item -LiteralPath (Join-Path $ca 'examples') -Destination $OutDir -Recurse
    $clipDir = Join-Path $OutDir 'node_modules\@mariozechner\clipboard'
    New-Item -ItemType Directory -Path $clipDir -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot 'node_modules\@mariozechner\clipboard\*') -Destination $clipDir -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot "node_modules\@mariozechner\clipboard-win32-$arch-msvc\clipboard.win32-$arch-msvc.node") -Destination $clipDir
    $prebuildDir = Join-Path $OutDir "native\win32\prebuilds\win32-$arch"
    New-Item -ItemType Directory -Path $prebuildDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot "packages\tui\native\win32\prebuilds\win32-$arch\win32-console-mode.node") -Destination $prebuildDir
}

function Test-IsAscii {
    param([string]$Text)
    foreach ($ch in $Text.ToCharArray()) {
        if ([int]$ch -gt 127) { return $false }
    }
    return $true
}

function Get-FreeDriveLetter {
    $used = @(Get-PSDrive | ForEach-Object { $_.Name })
    foreach ($code in 68..90) {
        $name = [string][char]$code
        if ($used -notcontains $name) { return $name }
    }
    throw "找不到可用的磁碟機代號"
}

function Build-FromSource {
    param([string]$RepoRoot)
    if (-not (Test-RepoRoot -Path $RepoRoot)) {
        throw "無效的 repo 目錄（缺少 package.json 或 packages/coding-agent）：$RepoRoot"
    }
    Assert-BuildTool -ToolName 'node' -Hint 'https://nodejs.org'
    Assert-BuildTool -ToolName 'npm' -Hint 'https://nodejs.org'
    Assert-BuildTool -ToolName 'bun' -Hint 'https://bun.sh'
    $arch = Get-TargetArch
    $outDir = Join-Path $RepoRoot "packages\coding-agent\binaries\windows-$arch"
    Write-Host "開始從原始碼建置（需要數分鐘）：$RepoRoot"
    $buildRoot = $RepoRoot
    $substDrive = $null
    if (-not (Test-IsAscii -Text $RepoRoot)) {
        $substDrive = Get-FreeDriveLetter
        cmd /c "subst ${substDrive}: `"$RepoRoot`"" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "無法建立暫存磁碟機代號 ${substDrive}:（subst 失敗）" }
        $buildRoot = "${substDrive}:"
        Write-Host "repo 路徑含非 ASCII 字元，改以 ${substDrive}: 執行建置（bun cross-compile 在非 ASCII 路徑下會失敗）"
    }
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $buildRoot 'node_modules'))) {
            Invoke-BuildStep -WorkingDirectory $buildRoot -FileName 'npm' -Arguments @('ci', '--ignore-scripts')
        }
        Invoke-BuildStep -WorkingDirectory $buildRoot -FileName 'npm' -Arguments @('run', 'build:offline')
        $bunTarget = "bun-windows-$arch"
        if ($arch -eq 'x64') { $bunTarget = "$bunTarget-baseline" }
        Invoke-BuildStep -WorkingDirectory (Join-Path $buildRoot 'packages\coding-agent') -FileName 'bun' -Arguments @('build', '--compile', '--no-compile-autoload-bunfig', "--target=$bunTarget", './dist/bun/cli.js', './src/utils/image-resize-worker.ts', '--outfile', "binaries/windows-$arch/pi.exe")
    } finally {
        if ($substDrive) { cmd /c "subst ${substDrive}: /d" | Out-Null }
    }
    Copy-StagedAssets -RepoRoot $RepoRoot -Arch $arch -OutDir $outDir
    return $outDir
}

function Get-RepoRootInteractive {
    param([string]$Default)
    while ($true) {
        $path = Get-UserInput -Prompt "輸入 repo 根目錄路徑 [$Default]" -Default $Default
        if (Test-RepoRoot -Path $path) { return $path }
        Write-Host "目錄不是有效的 repo（缺少 package.json 或 packages/coding-agent）：$path" -ForegroundColor Yellow
    }
}

function Get-InstallPlanInteractive {
    param([string]$DefaultInstallDir)
    Write-Host ''
    Write-Host '== Pi 安裝器 =='
    Write-Host '  [1] 從 GitHub Releases 安裝最新版'
    Write-Host '  [2] 從 GitHub Releases 安裝指定版本'
    Write-Host '  [3] 從本機 zip 安裝'
    Write-Host '  [4] 從本機目錄安裝'
    Write-Host '  [5] 從本機原始碼建置並安裝'
    $choice = Get-UserInput -Prompt '選擇安裝來源 [1]' -Default '1'

    $plan = [PSCustomObject]@{ Source = ''; Version = ''; LocalPath = ''; InstallDir = '' }
    switch ($choice) {
        '2' {
            $plan.Source = 'remote'
            while ([string]::IsNullOrWhiteSpace($plan.Version)) {
                $plan.Version = (Get-UserInput -Prompt '輸入版本號（例如 0.84.3 或 v0.84.3）').TrimStart('v')
            }
        }
        '3' { $plan.Source = 'zip'; $plan.LocalPath = Get-ValidatedLocalSource -Kind 'zip' -Suggested (Join-Path (Get-Location) 'pi-windows-x64.zip') }
        '4' { $plan.Source = 'dir'; $plan.LocalPath = Get-ValidatedLocalSource -Kind '目錄' -Suggested (Join-Path (Get-Location) 'windows-x64') }
        '5' {
            $defaultRepo = ''
            if ($script:InstallerDir) {
                $candidate = Split-Path -Parent $script:InstallerDir
                if (Test-RepoRoot -Path $candidate) { $defaultRepo = $candidate }
            }
            $plan.Source = 'dir'
            $plan.LocalPath = Build-FromSource -RepoRoot (Get-RepoRootInteractive -Default $defaultRepo)
        }
        default { $plan.Source = 'remote'; $plan.Version = '' }
    }

    $plan.InstallDir = Get-UserInput -Prompt "安裝目錄 [$DefaultInstallDir]" -Default $DefaultInstallDir
    return $plan
}

function Copy-PayloadToInstallDir {
    param(
        [string]$StagingDir,
        [string]$TargetDir
    )
    if (-not (Test-Path -LiteralPath (Join-Path $StagingDir 'pi.exe'))) {
        throw "安裝內容缺少 pi.exe，請確認來源是 $script:BuildCommandHint 的產物"
    }
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $StagingDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $TargetDir -Recurse -Force
    }
}

function Install-FromZip {
    param(
        [string]$ZipPath,
        [string]$TargetDir
    )
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "找不到 zip 檔：$ZipPath"
    }
    $staging = Join-Path ([IO.Path]::GetTempPath()) ("pi-install-" + [Guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $staging -Force
        Copy-PayloadToInstallDir -StagingDir $staging -TargetDir $TargetDir
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
}

function Install-FromDirectory {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "找不到目錄：$SourceDir"
    }
    Copy-PayloadToInstallDir -StagingDir $SourceDir -TargetDir $TargetDir
}

function Write-PostInstallSummary {
    param(
        [string]$TargetDir
    )
    Write-Host ''
    Write-Host '== 安裝完成 ==' -ForegroundColor Green
    Write-Host "安裝目錄：$TargetDir"
    Write-Host '開始使用：cd 到你的專案目錄後執行 pi'
    Write-Host '認證方式：在 pi 內執行 /login，或先設定 API key 環境變數（例如 ANTHROPIC_API_KEY）'
}

function Main {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$LocalPath,
        [string]$InstallDir,
        [switch]$NoPath,
        [switch]$ContextMenu,
        [switch]$RemoveContextMenu
    )

    if ($Version -and $LocalPath) {
        Write-Host "參數互斥：-Version 與 -LocalPath 不能同時使用" -ForegroundColor Red
        return 2
    }
    if ($ContextMenu -and $RemoveContextMenu) {
        Write-Host "參數互斥：-ContextMenu 與 -RemoveContextMenu 不能同時使用" -ForegroundColor Red
        return 2
    }
    if ($RemoveContextMenu) {
        Remove-ContextMenu
        Write-Host '已移除「用 MYPI 開啟」右鍵選單'
        return 0
    }

    try {
        $target = if ($InstallDir) { $InstallDir } else { $script:DefaultInstallDir }
        $interactive = (-not $Version -and -not $LocalPath)

        if ($LocalPath) {
            if ($LocalPath -like '*.zip') {
                Install-FromZip -ZipPath $LocalPath -TargetDir $target
            } else {
                Install-FromDirectory -SourceDir $LocalPath -TargetDir $target
            }
        } elseif ($Version) {
            Install-FromRemote -Version $Version.TrimStart('v') -TargetDir $target
        } else {
            $plan = Get-InstallPlanInteractive -DefaultInstallDir $target
            $target = $plan.InstallDir
            if ($plan.Source -eq 'zip') {
                Install-FromZip -ZipPath $plan.LocalPath -TargetDir $target
            } elseif ($plan.Source -eq 'dir') {
                Install-FromDirectory -SourceDir $plan.LocalPath -TargetDir $target
            } else {
                $resolved = if ($plan.Version) { $plan.Version } else { Resolve-LatestVersion -ApiUrl "https://api.github.com/repos/$($script:RepoOwner)/$($script:RepoName)/releases/latest" }
                Install-FromRemote -Version $resolved -TargetDir $target
            }
        }

        if (-not $NoPath) {
            Set-UserPathEntry -InstallDir $target -EnvVarName $script:PathEnvName -Scope $script:PathScope
        }

        if ($ContextMenu) {
            Set-ContextMenu -PiExePath (Join-Path $target 'pi.exe')
            Write-Host '已註冊「用 MYPI 開啟」右鍵選單（Windows 11 請點「顯示更多選項」或按 Shift+F10）'
        } elseif ($interactive) {
            $register = Get-UserInput -Prompt '註冊「用 MYPI 開啟」右鍵選單？[Y/n]' -Default 'Y'
            if ($register -match '^(?i:y|yes)$') {
                Set-ContextMenu -PiExePath (Join-Path $target 'pi.exe')
                Write-Host '已註冊「用 MYPI 開啟」右鍵選單（Windows 11 請點「顯示更多選項」或按 Shift+F10）'
            }
        }

        Write-PostInstallSummary -TargetDir $target
        return 0
    } catch {
        Write-Host "安裝失敗：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host '替代方案：使用 npm 安裝（npm install -g --ignore-scripts @earendil-works/pi-coding-agent）或以 -LocalPath 從本機建置產物安裝' -ForegroundColor Red
        return 1
    }
}

function Install-FromRemote {
    param(
        [string]$Version,
        [string]$TargetDir
    )
    $arch = Get-TargetArch
    $urls = Get-ReleaseAssetUrls -Version $Version -Arch $arch
    $tmpZip = Join-Path ([IO.Path]::GetTempPath()) "pi-windows-$arch-$([Guid]::NewGuid().ToString('N')).zip"
    $tmpSums = Join-Path ([IO.Path]::GetTempPath()) "SHA256SUMS-$([Guid]::NewGuid().ToString('N'))"
    try {
        Write-Host "下載 $($urls.ZipUrl) ..."
        Invoke-WebRequest -Uri $urls.ZipUrl -OutFile $tmpZip -UseBasicParsing
        Write-Host "下載 $($urls.SumsUrl) ..."
        Invoke-WebRequest -Uri $urls.SumsUrl -OutFile $tmpSums -UseBasicParsing
        if (-not (Test-AssetHash -ZipPath $tmpZip -SumsPath $tmpSums -Arch $arch)) {
            throw "SHA256 驗證失敗，已取消安裝"
        }
        Install-FromZip -ZipPath $tmpZip -TargetDir $TargetDir
    } finally {
        Remove-Item -LiteralPath $tmpZip, $tmpSums -Force -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Main -Version $Version -LocalPath $LocalPath -InstallDir $InstallDir -NoPath:$NoPath -ContextMenu:$ContextMenu -RemoveContextMenu:$RemoveContextMenu)
}
