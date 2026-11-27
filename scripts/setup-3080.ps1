<#
  vi-3080 first-time setup, run from the repository's folder after cloning it:

      powershell -ExecutionPolicy Bypass -File scripts\setup-3080.ps1 -GameDir 'D:\XboxGames\GameFiles'

  -GameDir is the folder of YOUR OWN dump of the title's Xbox Series build v1.0.2.1 (it is searched for
  game_scarlett_master.exe, subfolders included). Run it from a normal PowerShell window, not as administrator.

  What it does, each step skipped if already done (safe to run again):
    1. checks the PC and finds game_scarlett_master.exe;
    2. installs Git, Rust (rustup) and the Visual Studio C++ Build Tools with winget if they are missing;
    3. writes victory.toml (git-ignored): your game folder, and a cache and saves folder outside the repository
       (-DataRoot, default %USERPROFILE%\vi-3080-data); an existing victory.toml is kept unless -Force;
    4. downloads NVIDIA's DLSS files from NVIDIA's own GitHub into nvidia-sdk\ (git-ignored, about 70 MB), plus
       the DLSS SDK's nvngx_dlssd.dll, which avoids an NGX crash at start on RTX 30 cards (-NoDlssdFix: not),
       and AMD's FidelityFX SDK 2.4 for frame generation into -FfxRoot (default C:\FidelityFX-SDK; -NoFrameGen: not);
    5. builds the layer (target\release\victory.exe, 5-15 minutes the first time);
    6. starts the game with scripts\play-3080.ps1 if -Play is given.
#>
param(
    [Parameter(Mandatory)][string]$GameDir,
    [string]$DataRoot = "$HOME\vi-3080-data",
    [switch]$Force,
    [switch]$NoDlssdFix,
    [switch]$NoFrameGen,
    [string]$FfxRoot = 'C:\FidelityFX-SDK',
    [switch]$Play
)
$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; exit codes are checked instead
$repo = Split-Path $PSScriptRoot -Parent
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  OK  $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!  $t" -ForegroundColor Yellow }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User') + ";$HOME\.cargo\bin"
}

Step '1. Checking the PC and the game files'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) { Warn 'This window runs as administrator. Use a normal PowerShell window: the NVIDIA driver keeps its shader cache per user.' }
$exe = Get-ChildItem -Path $GameDir -Recurse -Filter 'game_scarlett_master.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { throw "game_scarlett_master.exe not found under ${GameDir}. -GameDir must be the folder of your own dump." }
Ok "game: $($exe.FullName)"
$repoFull = (Resolve-Path $repo).Path
if ($exe.DirectoryName.StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The game files are inside this repository. Keep them outside it (nothing from the game may ever be committed).'
}
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
if ($ramGB -lt 31) { Warn "RAM: $ramGB GB (32 GB or more is needed)" } else { Ok "RAM: $ramGB GB" }
Get-CimInstance Win32_VideoController | ForEach-Object { Ok "GPU: $($_.Name), driver $($_.DriverVersion)" }

Step '2. Git, Rust and the C++ build tools'
Refresh-Path
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}
if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    winget install --id Rustlang.Rustup -e --source winget --accept-package-agreements --accept-source-agreements
}
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$haveVC = (Test-Path $vswhere) -and (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
if (-not $haveVC) {
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget --accept-package-agreements --accept-source-agreements `
        --override '--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
}
Refresh-Path
foreach ($c in 'git', 'rustup', 'cargo') {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "$c not found. Open a new PowerShell window and run this again." }
}
Ok 'tools ready'

Step '3. victory.toml (your paths, kept out of git)'
$toml = Join-Path $repo 'victory.toml'
if ((Test-Path $toml) -and -not $Force) {
    Ok "kept the existing $toml (-Force writes a new one)"
} else {
    $cacheDir = Join-Path $DataRoot 'cache'
    $dataDir = Join-Path $DataRoot 'data'
    New-Item -ItemType Directory -Force -Path $cacheDir, $dataDir | Out-Null
    @"
# Written by scripts\setup-3080.ps1. Every path stays outside the repository.
[paths]
game_dir  = '$($exe.DirectoryName)'
cache_dir = '$cacheDir'
data_dir  = '$dataDir'
test_titles = []
"@ | Set-Content -Path $toml -Encoding ASCII
    Ok "game $($exe.DirectoryName); cache $cacheDir; saves $dataDir"
}

Step "4. NVIDIA's DLSS files (from NVIDIA's GitHub, about 70 MB)"
$sl = Join-Path $repo 'nvidia-sdk\Streamline\bin\x64'
if (-not (Test-Path (Join-Path $sl 'sl.interposer.dll'))) {
    try { & (Join-Path $repo 'scripts\get-nvidia-sdks.ps1') }
    catch { Warn "getting NVIDIA's files failed: $($_.Exception.Message)" }
}
if (-not (Test-Path (Join-Path $sl 'sl.interposer.dll'))) {
    Warn 'No Streamline files: the game runs with its own upscaling (no DLSS). Run Get-NVIDIA-DLSS.cmd later to add them.'
} else {
    Ok "Streamline: $sl"
    $dlssd = Join-Path $sl 'nvngx_dlssd.dll'
    if (-not $NoDlssdFix -and -not (Test-Path $dlssd)) {
        # On an RTX 3080 the driver's own nvngx_dlssd (310.9.0) crashed NGX at start (0xC0000005); the DLSS SDK's
        # copy beside Streamline's files is loaded instead.
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest 'https://github.com/NVIDIA/DLSS/raw/main/lib/Windows_x86_64/rel/nvngx_dlssd.dll' -OutFile $dlssd -UseBasicParsing -ErrorAction Stop
        } catch { Warn "nvngx_dlssd.dll not downloaded: $($_.Exception.Message)" }
    }
    if (Test-Path $dlssd) {
        $signer = (Get-AuthenticodeSignature $dlssd).SignerCertificate.Subject
        if ($signer -notmatch 'NVIDIA') { Warn "nvngx_dlssd.dll is not signed by NVIDIA ($signer): deleted."; Remove-Item $dlssd -Force }
        else { Ok 'nvngx_dlssd.dll from the DLSS SDK (signed by NVIDIA)' }
    }
}

if (-not $NoFrameGen) {
    Step "4b. AMD's FidelityFX SDK 2.4 (frame generation, from AMD's GitHub)"
    $find = {
        Get-ChildItem -Path $FfxRoot -Recurse -Filter 'amd_fidelityfx_framegeneration_dx12.dll' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.DirectoryName 'amd_fidelityfx_loader_dx12.dll') } | Select-Object -First 1
    }
    $fg = & $find
    if (-not $fg) {
        try {
            $releases = Invoke-RestMethod 'https://api.github.com/repos/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/releases' -Headers @{ 'User-Agent' = 'vi-3080' } -ErrorAction Stop
            $release = $releases | Where-Object { $_.tag_name -match '2\.4\.0' } | Select-Object -First 1
            $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Sort-Object size -Descending | Select-Object -First 1
            $url = if ($asset) { $asset.browser_download_url } else { $release.zipball_url }
            $zip = Join-Path $env:TEMP 'FidelityFX-SDK-2.4.0.zip'
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest $url -OutFile $zip -UseBasicParsing -ErrorAction Stop
            New-Item -ItemType Directory -Force -Path $FfxRoot | Out-Null
            Expand-Archive $zip -DestinationPath $FfxRoot -Force
            Remove-Item $zip -ErrorAction SilentlyContinue
            $fg = & $find
        } catch { Warn "the FidelityFX SDK was not downloaded: $($_.Exception.Message)" }
    }
    if ($fg) { Ok "frame generation DLLs in $($fg.DirectoryName)" }
    else { Warn "No FidelityFX SDK under ${FfxRoot}: the game runs without frame generation (unzip AMD's SDK 2.4.0 there by hand to add it)." }
}

Step '5. Building (5-15 minutes the first time)'
Set-Location $repo
rustup toolchain install
if ($LASTEXITCODE -ne 0) { rustup toolchain install 1.98.1 --target x86_64-pc-windows-msvc --profile minimal }
cargo build --release --locked -p victory
if ($LASTEXITCODE -ne 0) { throw 'The build failed: the first "error[...]" block above says why.' }
Ok "built $(Join-Path $repo 'target\release\victory.exe')"

Write-Host ''
Write-Host 'Ready. To play (from this folder, in a normal PowerShell window):' -ForegroundColor Cyan
Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\play-3080.ps1'
Write-Host 'Next: start the game once to record its shaders, then build them all ahead (README: Building the shaders before you play).'
if ($Play) {
    Step '6. Starting the game'
    & (Join-Path $repo 'scripts\play-3080.ps1')
}
