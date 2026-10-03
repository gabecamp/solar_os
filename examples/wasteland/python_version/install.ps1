<#
Wasteland Survivor (pygame version) installer for Windows 10 and 11.

Clones the game, checks what it needs, installs anything missing, and makes
launchers (play.bat, a desktop shortcut and a Start menu entry). Safe to run
again: it updates the clone and skips what's done.

From PowerShell:
    irm https://raw.githubusercontent.com/gabecamp/solar_os/main/examples/wasteland/python_version/install.ps1 | iex
or, with a downloaded copy:
    powershell -ExecutionPolicy Bypass -File install.ps1 [-Dir DIR] [-Branch NAME] [-Repo URL] [-NoSystem] [-Yes]

    -Dir DIR      where to put the game (default: %USERPROFILE%\wasteland-survivor)
    -Branch NAME  which branch to get (default: main)
    -Repo URL     which repository (default: https://github.com/gabecamp/solar_os.git)
    -NoSystem     never install Git or Python; only report them
    -Yes          don't ask before installing Git or Python

It checks for and installs (with winget, built into Windows 10 and 11):
Git and Python 3.8+; then the DejaVu fonts (next to the game, no admin
needed) and pygame and lupa in a private virtual environment.
#>
param(
    [string]$Dir = (Join-Path $HOME "wasteland-survivor"),
    [string]$Branch = "main",
    [string]$Repo = "https://github.com/gabecamp/solar_os.git",
    [switch]$NoSystem,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$GamePath = "examples/wasteland"
$IsWin = ($env:OS -eq "Windows_NT")

function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor White }
function Ok($text)   { Write-Host "  ok    $text" -ForegroundColor Green }
function Warn($text) { Write-Host "  warn  $text" -ForegroundColor Yellow }
function Die($text)  {
    Write-Host "  error $text" -ForegroundColor Red
    # (a script piped into iex has no exit to return to, so throw instead)
    throw "install stopped: $text"
}
function Have($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Refresh-Path {
    # winget installs update the registry PATH, not this session's.
    if (-not $IsWin) { return }
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Install-WithWinget($id, $what) {
    if ($NoSystem) { Warn "skipping $what (-NoSystem)"; return $false }
    if (-not (Have "winget")) {
        Warn "winget isn't available; install $what yourself (see below)"
        return $false
    }
    if (-not $Yes) {
        $answer = Read-Host "  install $what with winget? [Y/n]"
        if ($answer -match "^[nN]") { return $false }
    }
    Write-Host "  installing $what (a window may ask for permission)"
    & winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements
    Refresh-Path
    return $true
}

# A working Python 3.8+ (not the Microsoft Store stub that only opens the Store).
function Find-Python {
    $candidates = @(@("py", "-3"), @("python"), @("python3"))
    foreach ($c in $candidates) {
        $exe = $c[0]
        if (-not (Have $exe)) { continue }
        $extra = @()
        if ($c.Length -gt 1) { $extra = $c[1..($c.Length - 1)] }
        try {
            $out = & $exe @extra -c "import sys, venv; print(sys.executable) if sys.version_info >= (3, 8) else print('')" 2>$null
        } catch { continue }
        if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path ([string]$out).Trim())) { return ([string]$out).Trim() }
    }
    return $null
}

# Native commands report failure through $LASTEXITCODE, not exceptions.
function Run($exe) {
    & $exe @args
    if ($LASTEXITCODE -ne 0) { Die "$exe $($args -join ' ') failed (exit $LASTEXITCODE)" }
}

# -- 1. Git ---------------------------------------------------------------------
Step "1/6 Git"
if (-not (Have "git")) {
    [void](Install-WithWinget "Git.Git" "Git")
    if (-not (Have "git")) {
        $gitDefault = "C:\Program Files\Git\cmd"
        if (Test-Path "$gitDefault\git.exe") { $env:Path = "$env:Path;$gitDefault" }
    }
    if (-not (Have "git")) { Die "Git is required: https://git-scm.com/download/win (then run this again)" }
}
Ok (& git --version)

# -- 2. Python 3.8+ -----------------------------------------------------------------
Step "2/6 Python 3.8 or newer"
$py = Find-Python
if (-not $py) {
    [void](Install-WithWinget "Python.Python.3.12" "Python 3.12")
    $py = Find-Python
    if (-not $py) {
        $guess = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"
        if ($env:LOCALAPPDATA -and (Test-Path $guess)) { $py = $guess }
    }
    if (-not $py) { Die "Python 3.8+ is required: https://www.python.org/downloads/ (tick 'Add python.exe to PATH', then run this again)" }
}
Ok "$(& $py --version) at $py"

# -- 3. the game ----------------------------------------------------------------
Step "3/6 the game ($Branch) into $Dir"
if (Test-Path (Join-Path $Dir ".git")) {
    Run git -C $Dir fetch --depth 1 origin $Branch
    Run git -C $Dir checkout -q -B $Branch FETCH_HEAD
    Ok "updated the existing copy"
} else {
    if ((Test-Path $Dir) -and (Get-ChildItem $Dir -Force | Select-Object -First 1)) {
        Die "$Dir exists and is not empty (use -Dir)"
    }
    # Only the game's folder: the repository also holds a whole firmware.
    & git clone --depth 1 --branch $Branch --filter=blob:none --sparse $Repo $Dir
    if ($LASTEXITCODE -eq 0) {
        Run git -C $Dir sparse-checkout set $GamePath
        Ok "cloned (game folder only)"
    } else {
        if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
        Run git clone --depth 1 --branch $Branch $Repo $Dir
        Ok "cloned"
    }
}
$Game = Join-Path $Dir $GamePath
$HostDir = Join-Path $Game "python_version"
if (-not (Test-Path (Join-Path $HostDir "wasteland_pygame.py"))) { Die "no python_version in branch '$Branch' (try -Branch)" }
if (-not (Test-Path (Join-Path $Game "wasteland.lua"))) { Die "no wasteland.lua in branch '$Branch'" }
Ok "game files present"

# -- 4. fonts -------------------------------------------------------------------
Step "4/6 fonts (DejaVu Sans Mono: the text lines up like on the device)"
$fontDirs = @($HostDir)
if ($IsWin) { $fontDirs += (Join-Path $env:WINDIR "Fonts") }
if ($env:LOCALAPPDATA) { $fontDirs += (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts") }
if (-not $IsWin) { $fontDirs += "/usr/share/fonts/truetype/dejavu" }
function Fonts-Found {
    foreach ($d in $fontDirs) {
        if ((Test-Path ([IO.Path]::Combine($d, "DejaVuSansMono.ttf"))) -and (Test-Path ([IO.Path]::Combine($d, "DejaVuSansMono-Bold.ttf")))) { return $true }
    }
    return $false
}
if (Fonts-Found) {
    Ok "found"
} else {
    # The fonts' own release; the two files go next to the game, which looks there.
    $url = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
    $zip = Join-Path ([IO.Path]::GetTempPath()) "dejavu-fonts.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                if ($entry.Name -eq "DejaVuSansMono.ttf" -or $entry.Name -eq "DejaVuSansMono-Bold.ttf") {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $HostDir $entry.Name), $true)
                }
            }
        } finally { $archive.Dispose() }
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } catch {
        Warn "couldn't download the fonts: $($_.Exception.Message)"
    }
    if (Fonts-Found) { Ok "installed next to the game" } else { Warn "not found: the game runs, but its text won't line up" }
}

# -- 5. pygame and lupa ------------------------------------------------------------
Step "5/6 pygame and lupa (in $HostDir\.venv)"
$venv = Join-Path $HostDir ".venv"
function Venv-Python {
    $win = Join-Path $venv "Scripts\python.exe"
    if (Test-Path $win) { return $win }
    return (Join-Path $venv "bin/python")
}
function Deps-Ok {
    $vp = Venv-Python
    if (-not (Test-Path $vp)) { return $false }
    & $vp -c "import pygame; from lupa import lua54" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}
if (Deps-Ok) {
    Ok "already installed"
} else {
    if (Test-Path $venv) { Remove-Item -Recurse -Force $venv }
    Run $py -m venv $venv
    $vp = Venv-Python
    Run $vp -m pip install --quiet --upgrade pip
    & $vp -m pip install --quiet --prefer-binary -r (Join-Path $HostDir "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        Die "pygame or lupa failed to install. A very new Python may not have them yet: install Python 3.12 (winget install Python.Python.3.12) and run this again."
    }
    if (-not (Deps-Ok)) { Die "pygame or lupa installed but won't load; see the messages above" }
    Ok (& $vp -c "import pygame, lupa; print('pygame', pygame.version.ver, '- lupa', lupa.__version__)" 2>$null | Select-Object -Last 1)
}
$vp = Venv-Python

# -- 6. a quick test game, and launchers -------------------------------------------
Step "6/6 a quick test game (no window), and launchers"
$test = Join-Path ([IO.Path]::GetTempPath()) "wasteland_check.py"
@"
import os, sys, tempfile
os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"
os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"
sys.path.insert(0, sys.argv[1])
os.chdir(sys.argv[1])
import wasteland_pygame as w
h = w.run(keys=[10, 32], mute=True, data_dir=tempfile.mkdtemp())
print("ERROR " + h.error if h.error else "OK %d frames" % h.frames)
"@ | Set-Content -Path $test -Encoding ASCII
$result = (& $vp $test $HostDir 2>&1 | Select-Object -Last 1) -as [string]
Remove-Item $test -Force -ErrorAction SilentlyContinue
if ($result -like "OK*") { Ok "the game started and drew $($result.Substring(3))" }
else { Die "the test game failed: $result" }

# play.bat: double-click to play (passes options through, e.g. play.bat --fullscreen)
$bat = Join-Path $Dir "play.bat"
@"
@echo off
rem Start Wasteland Survivor. Options: --fullscreen --scale N --look gray^|device^|amber^|green --mute
cd /d "$HostDir"
"$vp" wasteland_pygame.py %*
"@ | Set-Content -Path $bat -Encoding ASCII
Ok "launcher: $bat"

# Shortcuts (Windows only): pythonw, so no console window opens.
if ($IsWin) {
    $pyw = Join-Path $venv "Scripts\pythonw.exe"
    if (-not (Test-Path $pyw)) { $pyw = $vp }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $targets = @(
            (Join-Path ([Environment]::GetFolderPath("Desktop")) "Wasteland Survivor.lnk"),
            (Join-Path ([Environment]::GetFolderPath("Programs")) "Wasteland Survivor.lnk")
        )
        foreach ($t in $targets) {
            $lnk = $shell.CreateShortcut($t)
            $lnk.TargetPath = $pyw
            $lnk.Arguments = "wasteland_pygame.py"
            $lnk.WorkingDirectory = $HostDir
            $lnk.Description = "Survive the Zone"
            $lnk.Save()
        }
        Ok "shortcuts: desktop and Start menu"
    } catch {
        Warn "couldn't make shortcuts: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Ready." -ForegroundColor White -NoNewline
Write-Host " Play with the 'Wasteland Survivor' shortcut, or:"
Write-Host "  $bat                 (a window, 800x600)"
Write-Host "  $bat --fullscreen"
Write-Host "Run this installer again any time to update the game."
