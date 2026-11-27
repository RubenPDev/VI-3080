# vi-3080: VIctory-NVIDIA tuned for an RTX 3080 10 GB (Ampere: DLSS yes, DLSS frame generation no),
# an 8-core Ryzen 7 9800X3D and 32 GB of RAM. Everything goes on to play-foxhound.ps1 (its options are at its top).
#
#   .\scripts\play-3080.ps1                       Series X, 2560x1440 output, DLSS Balanced, no frame rate cap
#   .\scripts\play-3080.ps1 -Dlss quality         sharper, slower (also: performance, dlaa, off)
#   .\scripts\play-3080.ps1 -SeriesS              the Series S profile (1280x720 inside): fastest
#   .\scripts\play-3080.ps1 -More @{VICTORY_THIN='0'}   override any switch (several: @{A='1'; B='0'})
#   .\scripts\play-3080.ps1 -FrameGenOff         AMD frame generation loaded but off at the start (F6 turns it on)
#   .\scripts\play-3080.ps1 -NoFrameGen          no AMD frame generation at all
#   .\scripts\play-3080.ps1 -NoFastShaders       the shaders translated the long way, as before update 15 (on by default since update 17)
#   .\scripts\play-3080.ps1 -NoBarWindows        no game memory written through the resizable BAR (on by default since update 17)
#   .\scripts\play-3080.ps1 -RoomForGeometry     the game's vertex, index and constant memory gets card room before textures
#   .\scripts\play-3080.ps1 -PipelineWait 500    how long a frame may wait for new pipelines, in ms (default 100)
#   .\scripts\play-3080.ps1 -NoAutoWarm          don't build the pipelines a session met for the first time after it ends
#
# In the game, F6 switches AMD's frame generation (FSR 3.1, one generated frame between two rendered ones) off and
# on, and F7 where it runs: async (on the card's compute queue, beside the next frame; the default) or in line
# (after each frame). The window's caption and the F3 panel say which. The F1 menu's frame generation item
# switches AMD's too, at once; what it saves decides whether it starts on next time.
# F1's settings marked LIVE apply at once; the others at the next start: "SAVE AND RESTART NOW" in the menu saves
# them, closes the game and starts this launcher again with them.
#
# What it changes over play-foxhound.ps1's defaults, and why:
# - NVIDIA's frame generation is never made ready: the RTX 30 series has none. AMD's (FSR 3.1, the FidelityFX
#   SDK 2.4 found under -FfxRoot) takes its place, after DLSS on the same frame (framegen.rs, vi-3080, after
#   Vice-Tay); it leaves the textures 86 % of the card's budget instead of 90.
# - VICTORY_THIN_THREADS=12: the lists of a frame waited ~11 ms on average for one of 8 translating threads
#   (vi-3080 update 6); the 9800X3D has 16.
# - VICTORY_CARD_WINDOWS_MB=1024: the title's allocator reads (vertices, indices, constants) from the card's
#   memory instead of over PCIe. The default on a 10 GB card is 9 % of its budget (~765 MB); 1024 is what moved
#   an RTX 4070 SUPER's gameplay from 3 to 21-25 fps (shadow.rs). Windows still only go to the card while a
#   fifth of its budget is free, so textures keep their room.
# - VICTORY_DSTORAGE_IO=direct: game files are read past Windows' file cache, which otherwise holds gigabytes of
#   a 32 GB PC's RAM (Vice-Tay's 16 GB preset; less paging, fewer hitches).
# - VICTORY_FILL_TITLE=1: the title's small writes of constants into its heap no longer wait for every flight's
#   copy-back (host.rs: ~30 ms of a 130 ms frame there). Measured here: 41 -> 28 ms a frame waiting for the GPU,
#   about 12 -> 15-20 fps.
# - -TextureCap 2048 (VICTORY_TEXTURE_MAX_DIM, vi-3080 on the held-levels base, after Evan-Lowry's cap in
#   klbf-lab): a full card turned new textures away ~54,000 times in a few minutes of driving (black textures,
#   pop-in, U-turn stalls). World textures over 2048 start one level down; menus and screen images stay whole.
# - VICTORY_COPIES_IN_PLACE=0: the title's buffer copies go at submission again, where the card steps can do
#   them behind the flights; in place, a read of their destination waited for every flight (10-25 ms a frame
#   here, all of the "title memory read" settles). Measured: 28-48 -> 2-4 ms a frame waiting for the GPU.
# - The ray-tracing-only skinning passes are left out in the layer itself (pipeline/make.rs, vi-3080):
#   VICTORY_RT_SKIN=1 runs them again; VICTORY_SKIP_RT_HAIR=1 also leaves out the ray-tracing hair geometry.
# - A barrier on every shader write that would follow the last one with nothing recorded between them is left
#   out in the layer itself (list.rs, vi-3080: it orders nothing more); VICTORY_BARRIER_ELIDE=0 records them all.
# - Fast shaders (vi-3080 update 15; the default since update 17, -NoFastShaders turns them off): VICTORY_FAST_FLOAT=1 with VICTORY_RDNA_FLOAT=7 writes the console's
#   0-times-anything-is-0 multiply (most multiplies of the title's shaders), its min/max and its clamp the short way
#   (exact but for the sign of a zero), and VICTORY_SHADER_OPT=127 reads the dwords of one console load with one
#   call for every four. Translations of their own: warm-3080.ps1 builds them (-NoFastShaders: the others).
# - -RoomForGeometry (vi-3080 update 14's test): windows of title memory may take up to 2 GB of the card, up to 92 %
#   of its budget, and textures stop at 80 % instead of 86 %. Update 14 (2.5 GB, 90 %, textures at 74 %) was steadier
#   and faster but visibly softer; this is the middle.
# - BAR windows (vi-3080 update 16; the default since update 17, -NoBarWindows turns them off): VICTORY_WINDOWS_BAR_MB=1024 puts the windows that went to the card (1 GB, as
#   VICTORY_CARD_WINDOWS_MB) in card memory the CPU writes through the resizable BAR instead: no copy of them in the
#   PC's memory, nothing to send up before each submission (shadow.rs: a captured frame's lists 29 -> 26 ms, the
#   frame 36 -> 32). Needs Resizable BAR on; windows go there while the card is under 80 % of its budget, as before.
#   Measured here (update 16, 1440p DLSS Quality): steadier and faster than without, 13-28 fps.
# - -PipelineWait 100 (VICTORY_PIPELINE_WAIT_MS, vi-3080 update 17): a frame waited up to 500 ms for pipelines it met
#   for the first time (pipeline/make.rs), which were most of the big drops (lists of 0.4-0.6 s at each drop in update
#   16). At 100 a new object may show up a few frames late instead. Passes over the whole screen still wait (10 s).
# - After a session the pipelines it met for the first time (the launcher writes them down) are built
#   (warm-3080.ps1, only the new ones: usually seconds to a few minutes), so they don't stall the next session.
#   Skipped when the game was restarted from the F1 menu; -NoAutoWarm skips it always.
param(
    [ValidateSet('off', 'dlaa', 'quality', 'balanced', 'performance')][string]$Dlss = 'balanced',
    [ValidateSet('1440', '1080to1440', '4k')][string]$Res = '1440',
    [switch]$SeriesS,
    [ValidateRange(1, 1000)][int]$Fps = 1000,
    [ValidateSet('release', 'diag')][string]$Build = 'release',
    # Largest side of a block-compressed world texture on the card (0: no cap). 2048 keeps them sharp at 1440p and
    # cuts a 4096x4096 one to a quarter of its memory; 1024 for even more room.
    [ValidateSet(0, 1024, 2048, 4096)][int]$TextureCap = 2048,
    [string]$Exe = '',
    [switch]$NoFrameGen,
    [switch]$FrameGenOff,
    [string]$FfxRoot = 'C:\FidelityFX-SDK',
    [switch]$NoFastShaders,
    [switch]$NoBarWindows,
    [switch]$RoomForGeometry,
    [ValidateRange(0, 10000)][int]$PipelineWait = 100,
    [switch]$NoAutoWarm,
    # Accepted for older command lines: both are the default now.
    [switch]$FastShaders,
    [switch]$BarWindows,
    [hashtable]$More = @{}
)
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Exe) {
    # The title's executable in game_dir of victory.toml.
    $toml = Join-Path $repo 'victory.toml'
    $line = if (Test-Path $toml) { Get-Content $toml | Where-Object { $_ -match "^\s*game_dir\s*=\s*'(.+)'\s*$" } | Select-Object -First 1 }
    if (-not $line) { Write-Host "No game_dir in ${toml}: pass -Exe <path of game_scarlett_master.exe>."; return }
    $null = $line -match "^\s*game_dir\s*=\s*'(.+)'\s*$"
    $Exe = Join-Path $Matches[1] 'game_scarlett_master.exe'
}
$settings = @{
    VICTORY_CARD_WINDOWS_MB = '1024'
    VICTORY_DSTORAGE_IO = 'direct'
    VICTORY_FILL_TITLE = '1'
    VICTORY_COPIES_IN_PLACE = '0'
    VICTORY_THIN_THREADS = '12'
}
if ($TextureCap -gt 0) { $settings.VICTORY_TEXTURE_MAX_DIM = [string]$TextureCap }
# The F1 menu's "SAVE AND RESTART NOW" starts this launcher again (not play-foxhound.ps1), so the settings here
# stay. The menu's own choices (DLSS, frame rate cap, console, picture) come from victory-settings.txt, which
# play-foxhound.ps1 applies at every start; -More switches are not carried over a restart.
$settings.VICTORY_MENU_PLAY = $MyInvocation.MyCommand.Path
$settings.VICTORY_MENU_ARGS = "-Exe '$($Exe -replace "'", "''")' -Build $Build -TextureCap $TextureCap" +
    $(if ($NoFrameGen) { ' -NoFrameGen' }) + $(if ($FrameGenOff) { ' -FrameGenOff' }) +
    $(if ($NoFastShaders) { ' -NoFastShaders' }) + $(if ($NoBarWindows) { ' -NoBarWindows' }) +
    $(if ($RoomForGeometry) { ' -RoomForGeometry' }) + " -PipelineWait $PipelineWait" + $(if ($NoAutoWarm) { ' -NoAutoWarm' })
if (-not $NoFastShaders) {
    foreach ($k in (& (Join-Path $PSScriptRoot 'fast-shaders.ps1')).GetEnumerator()) { $settings[$k.Key] = $k.Value }
}
$settings.VICTORY_PIPELINE_WAIT_MS = [string]$PipelineWait
# NVIDIA's frame generation needs an RTX 40: never asked for, whatever the F1 menu saved for its item (which
# stands for AMD's here).
$settings.VICTORY_FRAMEGEN = ''
$settings.VICTORY_FRAMEGEN_X = ''
$menuFile = Join-Path $repo 'victory-settings.txt'
$menuFg = if (Test-Path -LiteralPath $menuFile) {
    Get-Content -LiteralPath $menuFile | Where-Object { $_ -match '^\s*VICTORY_MENU_FRAMEGEN\s*=' } | Select-Object -Last 1 |
        ForEach-Object { ($_ -split '=', 2)[1].Trim() }
}
if ($menuFg -eq '0') { $FrameGenOff = $true }
if (-not $NoFrameGen) {
    # AMD's signed DLLs: VICTORY_FFX_FG_DIR, else the FidelityFX SDK's folder that holds both.
    $ffx = $env:VICTORY_FFX_FG_DIR
    if (-not $ffx -and (Test-Path $FfxRoot)) {
        $ffx = Get-ChildItem -Path $FfxRoot -Recurse -Filter 'amd_fidelityfx_framegeneration_dx12.dll' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.DirectoryName 'amd_fidelityfx_loader_dx12.dll') } |
            Sort-Object { $_.DirectoryName -notlike '*signedbin*' } | Select-Object -First 1 -ExpandProperty DirectoryName
    }
    if ($ffx) {
        $settings.VICTORY_FSR_FRAMEGEN = '1'
        $settings.VICTORY_FFX_FG_DIR = $ffx
        $settings.VICTORY_TEXTURE_ROOM_PERCENT = '86'
        if ($FrameGenOff) { $settings.VICTORY_FSR_FRAMEGEN_START = '0' }
        Write-Host "AMD frame generation from $ffx ($(if ($FrameGenOff) { 'off' } else { 'on' }) at the start; F6 switches it)."
    } else {
        Write-Host "No AMD FidelityFX SDK under ${FfxRoot}: playing without frame generation (-FfxRoot names another folder)."
    }
}
if ($RoomForGeometry) {
    $settings.VICTORY_CARD_WINDOWS_MB = '2048'
    $settings.VICTORY_WINDOW_ROOM_PERCENT = '92'
    $settings.VICTORY_TEXTURE_ROOM_PERCENT = '80'
}
if (-not $NoBarWindows) { $settings.VICTORY_WINDOWS_BAR_MB = '1024' }
foreach ($k in $More.Keys) { $settings[$k] = $More[$k] }
$opts = @{ Exe = $Exe; Dlss = $Dlss; Res = $Res; Fps = $Fps; Build = $Build; NoFrameGenReady = $true; More = $settings }
if ($SeriesS) { $opts.SeriesS = $true }
& (Join-Path $PSScriptRoot 'play-foxhound.ps1') @opts
# The pipelines this session met for the first time, built now so the next one doesn't stall on them. Not when the
# game was started again from the F1 menu (it is running again), and not for the diagnostics build.
if (-not $NoAutoWarm -and $Build -eq 'release') { Start-Sleep -Seconds 8 }   # (a restart from the menu starts the game again)
if (-not $NoAutoWarm -and $Build -eq 'release' -and -not (Get-Process victory -ErrorAction SilentlyContinue)) {
    Write-Host "`nBuilding the pipelines this session met for the first time (Ctrl+C skips it; -NoAutoWarm turns it off) ..."
    $warmArgs = @{}
    if ($NoFastShaders) { $warmArgs.NoFastShaders = $true }
    & (Join-Path $PSScriptRoot 'warm-3080.ps1') @warmArgs
}
