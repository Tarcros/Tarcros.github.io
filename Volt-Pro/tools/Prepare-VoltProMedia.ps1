[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $InputPath,

    [string] $OutputDirectory = (Join-Path (Get-Location) 'VoltPro_Proxies'),

    [ValidateSet(1080, 2160)]
    [int] $MaxHeight = 2160,

    [ValidateRange(24, 60)]
    [int] $MaxFps = 60,

    [ValidateSet('Auto', 'SonySLog3Cine', 'SonySLog3', 'Rec709')]
    [string] $Profile = 'Auto',

    [switch] $Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RequiredTool([string] $Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Outil introuvable : $Name. Installe FFmpeg puis relance." }
    return $command.Source
}

function Get-InputFiles([string[]] $Paths) {
    $extensions = @('.mp4', '.mov', '.m4v', '.mxf', '.r3d', '.nev')
    foreach ($item in $Paths) {
        $resolved = Resolve-Path -LiteralPath $item -ErrorAction Stop
        if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
            Get-ChildItem -LiteralPath $resolved -Recurse -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
        } else {
            Get-Item -LiteralPath $resolved
        }
    }
}

function Get-FrameRate([string] $Probe, [string] $Path) {
    $rate = (& $Probe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nokey=1:noprint_wrappers=1 -- $Path | Select-Object -First 1)
    if (-not $rate) { return 30.0 }
    $parts = $rate.Trim().Split('/')
    if ($parts.Count -eq 2 -and [double]$parts[1] -ne 0) { return [double]$parts[0] / [double]$parts[1] }
    return [double]$rate
}

function Get-ProfileTag([string] $SelectedProfile, [string] $Name) {
    if ($SelectedProfile -eq 'SonySLog3Cine') { return 'camera=Sony; gamma=S-Log3; gamut=S-Gamut3.Cine' }
    if ($SelectedProfile -eq 'SonySLog3') { return 'camera=Sony; gamma=S-Log3; gamut=S-Gamut3' }
    if ($SelectedProfile -eq 'Rec709') { return 'gamma=Rec.709; gamut=Rec.709' }
    if ($Name -match '(?i)s[-_ ]?log3|slog3') { return 'camera=Sony; gamma=S-Log3; gamut=S-Gamut3.Cine; profile=confirm' }
    return 'profile=manual-confirmation-required'
}

$ffmpeg = Resolve-RequiredTool 'ffmpeg'
$ffprobe = Resolve-RequiredTool 'ffprobe'
$redlineCandidates = @(
    'C:\Program Files\REDCINE-X PRO 64-bit\REDline.exe',
    'C:\Program Files\REDCINE-X PRO\REDline.exe'
)
$redline = $redlineCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$files = @(Get-InputFiles $InputPath)
if (-not $files.Count) { throw 'Aucun media reconnu dans la selection.' }

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$maxWidth = if ($MaxHeight -eq 2160) { 3840 } else { 1920 }
$completed = 0
$failed = 0

foreach ($file in $files) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $output = Join-Path $OutputDirectory ($stem + '_VOLT_PROXY.mp4')
    if ((Test-Path -LiteralPath $output) -and -not $Overwrite) {
        Write-Host "DEJA PRET     $output" -ForegroundColor DarkYellow
        continue
    }

    try {
        $source = $file.FullName
        $profileTag = Get-ProfileTag $Profile $file.Name
        $intermediate = $null

        if ($file.Extension -ieq '.nev') {
            throw 'Nikon N-RAW (.NEV) ne possede pas de decodeur Windows/Safari utilisable ici. Convertis-le d abord dans DaVinci Resolve vers H.264 4:2:0 ou HEVC 4:2:0 sans LUT.'
        }

        if ($file.Extension -ieq '.r3d') {
            if (-not $redline) { throw 'REDCINE-X PRO officiel est requis pour decoder le R3D. Installe-le depuis red.com puis relance.' }
            $intermediateBase = Join-Path $OutputDirectory ($stem + '_RWG_LOG3G10_INTERMEDIATE')
            $intermediate = $intermediateBase + '.mov'
            Write-Host "R3D -> RWG/Log3G10  $($file.Name)" -ForegroundColor Cyan
            & $redline --i $source --o $intermediateBase --format 201 --PRcodec 3 --res 4 --resizeX $maxWidth --resizeY $MaxHeight --fit 1 --useMeta --primaryDev --gammaCurve 34 --colorSpace 25 --errorsOnly
            if (-not (Test-Path -LiteralPath $intermediate)) { throw 'REDline n a produit aucun intermediaire ProRes.' }
            $source = $intermediate
            $profileTag = 'camera=RED; gamma=Log3G10; gamut=REDWideGamutRGB'
        }

        $frameRate = Get-FrameRate $ffprobe $source
        $filters = @("scale='min(iw,$maxWidth)':'min(ih,$MaxHeight)':force_original_aspect_ratio=decrease:force_divisible_by=2")
        if ($frameRate -gt $MaxFps + 0.01) { $filters += "fps=$MaxFps" }
        $filters += 'format=yuv420p'
        $filter = $filters -join ','
        Write-Host "PROXY          $($file.Name) -> $([IO.Path]::GetFileName($output))" -ForegroundColor Green
        $overwriteFlag = if ($Overwrite) { '-y' } else { '-n' }
        & $ffmpeg $overwriteFlag -hide_banner -loglevel warning -i $source -map 0:v:0 -map '0:a:0?' -vf $filter -c:v libx264 -preset fast -crf 17 -profile:v high -level:v 5.2 -pix_fmt yuv420p -movflags '+faststart+use_metadata_tags' -c:a aac -b:a 256k -ar 48000 -metadata "comment=Volt Pro proxy; $profileTag" -metadata:s:v:0 "comment=Volt Pro proxy; $profileTag" $output
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw 'FFmpeg n a pas pu produire le proxy.' }
        if ($intermediate -and (Test-Path -LiteralPath $intermediate)) { Remove-Item -LiteralPath $intermediate -Force }
        $completed += 1
        Write-Host "OK             $output" -ForegroundColor Green
    } catch {
        $failed += 1
        Write-Host "ERREUR         $($file.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Volt Pro : $completed proxy(s) pret(s), $failed erreur(s)." -ForegroundColor $(if ($failed) { 'Yellow' } else { 'Green' })
Write-Host "Copie les MP4 du dossier suivant sur l iPhone puis importe-les dans Volt Pro :"
Write-Host (Resolve-Path -LiteralPath $OutputDirectory)
if ($failed) { exit 1 }
