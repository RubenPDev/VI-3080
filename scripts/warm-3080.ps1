# vi-3080: builds the game's shader pipelines ahead of play (see README, "Building the shaders before you play").
#   .\scripts\warm-3080.ps1                  the translations play-3080.ps1 uses (fast shaders, the default since update 17)
#   .\scripts\warm-3080.ps1 -NoFastShaders   those play-3080.ps1 -NoFastShaders uses
#   .\scripts\warm-3080.ps1 -Again           all of them again, even those already built
# It takes a long time; stopped (Ctrl+C), the same command carries on where it left off.
param([switch]$NoFastShaders, [switch]$Again, [ValidateSet('release', 'diag')][string]$Build = 'release',
    # Accepted for older command lines: the default now.
    [switch]$FastShaders)
$repo = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $repo "target\$Build\victory.exe"
if (-not (Test-Path $exe)) { Write-Host "No $exe yet: build first (cargo build --release -p victory)."; return }
$env:VICTORY_HOST_WAVE = '32'
# The game starts with VICTORY_EARLY_DEPTH=1 (play-foxhound.ps1), which is part of every translation's key and
# changes the pixel shaders that test depth early: without it here, the game used none of these translations
# (it made its own while you played) and compiled those pixel shaders' pipelines again (vi-3080 update 16).
$env:VICTORY_EARLY_DEPTH = '1'
foreach ($k in 'VICTORY_FAST_FLOAT', 'VICTORY_RDNA_FLOAT', 'VICTORY_SHADER_OPT') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
if (-not $NoFastShaders) {
    foreach ($k in (& (Join-Path $PSScriptRoot 'fast-shaders.ps1')).GetEnumerator()) { Set-Item "Env:$($k.Key)" $k.Value }
}
Push-Location $repo
try {
    if ($Again) { & $exe warm --again } else { & $exe warm }
} finally { Pop-Location }
