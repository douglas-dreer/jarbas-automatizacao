[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "deploy", "undeploy", "undeploy-remove", "start-deploy", "status", "remove", "help")]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$HelpTopic,

    [switch]$SkipTest,
    [switch]$VerboseLog,
    [switch]$DryRun,

    [Alias('?', '/?')]
    [switch]$Help
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==============================
# PALETTE
# ==============================
# Primary   : Green  (acid green)
# Accent    : Cyan   (electric)
# Warning   : Yellow (neon)
# Error     : Red    (hot)
# Noise     : DarkGreen (dim scanline)
# Dim       : DarkGray

# ==============================
# GLITCH ENGINE
# ==============================

$GlitchChars = @('%','$','#','@','!','&','*','^','~','?','/','\','|','+','=','<','>')

function Get-GlitchString {
    param([int]$Length = 12)
    $out = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $out += $GlitchChars[(Get-Random -Maximum $GlitchChars.Count)]
    }
    return $out
}

function Write-GlitchLine {
    param([string]$FinalText, [int]$Iterations = 4, [int]$DelayMs = 35)
    for ($i = 0; $i -lt $Iterations; $i++) {
        $noise = Get-GlitchString -Length $FinalText.Length
        Write-Host "`r  $noise" -NoNewline -ForegroundColor DarkGreen
        Start-Sleep -Milliseconds $DelayMs
    }
    Write-Host "`r  $FinalText" -ForegroundColor Green
}

function Write-GlitchBlock {
    param([string[]]$Lines, [int]$Iterations = 3, [int]$DelayMs = 25)
    foreach ($line in $Lines) {
        Write-GlitchLine -FinalText $line -Iterations $Iterations -DelayMs $DelayMs
    }
}

# ==============================
# NOISE / SCANLINES
# ==============================

function Write-Scanline {
    $noise = Get-GlitchString -Length (Get-Random -Minimum 20 -Maximum 55)
    Write-Host "  $noise" -ForegroundColor DarkGreen
}

function Write-ScanlineBlock {
    param([int]$Lines = 3)
    for ($i = 0; $i -lt $Lines; $i++) { Write-Scanline }
}

# ==============================
# SYS COORDINATES (fake HUD data)
# ==============================

function Get-SysCoords {
    $node     = "0x{0:X4}" -f (Get-Random -Maximum 65535)
    $fakeProc = Get-Random -Minimum 1000 -Maximum 9999
    $mem      = "{0:N0}" -f (Get-Random -Minimum 32000 -Maximum 131072)
    $ts       = Get-Date -Format "HHmmss.fff"
    return "SYS.NODE $node  |  PROC.$fakeProc  |  MEM $mem KB  |  CLK $ts"
}

function Write-HudHeader {
    param([string]$Title)

    $coords = Get-SysCoords

    # Dynamic width: adapt to real terminal width, floor at 40
    $termWidth  = try { $Host.UI.RawUI.WindowSize.Width } catch { 80 }
    if ($termWidth -lt 1) { $termWidth = 80 }
    $innerWidth = [math]::Max($termWidth - 4, 40)

    # prefix: "╔══[ TITLE ]" = Title.Length + 6  (3 for ╔══, 1 [, space, 1 ], space)
    $prefixLen = $Title.Length + 6
    $padRight  = [math]::Max($innerWidth - $prefixLen, 1)

    # Coords line: pad with spaces to fill the box, then close with ║
    $coordsDisplay = " $coords"
    $maxCoords     = $innerWidth - 1   # -1 to leave room for closing ║
    if ($coordsDisplay.Length -gt $maxCoords) {
        $coordsDisplay = $coordsDisplay.Substring(0, $maxCoords - 3) + "..."
    }
    # Right-pad with spaces so the closing ║ always aligns
    $coordsPadded = $coordsDisplay.PadRight($maxCoords)

    Write-Host ""
    Write-Host "  ╔══[ $Title ]" -ForegroundColor Cyan -NoNewline
    Write-Host ("═" * $padRight)  -ForegroundColor Cyan -NoNewline
    Write-Host "╗"                -ForegroundColor Cyan
    Write-Host "  ║" -ForegroundColor Cyan -NoNewline
    Write-Host $coordsPadded      -ForegroundColor DarkGray -NoNewline
    Write-Host "║"                -ForegroundColor Cyan
    Write-Host "  ╚"              -ForegroundColor Cyan -NoNewline
    Write-Host ("═" * $innerWidth) -ForegroundColor Cyan -NoNewline
    Write-Host "╝"                -ForegroundColor Cyan
    Write-Host ""
}

function Write-HudFooter {
    $coords    = Get-SysCoords
    $termWidth = try { $Host.UI.RawUI.WindowSize.Width } catch { 80 }
    if ($termWidth -lt 1) { $termWidth = 80 }
    $maxLen    = $termWidth - 4
    $line      = "┄┄┄ $coords ┄┄┄"
    if ($line.Length -gt $maxLen) { $line = $line.Substring(0, $maxLen - 3) + "..." }
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkGray
    Write-Host ""
}

# ==============================
# OUTPUT HELPERS
# ==============================

function Write-Cyber {
    param([string]$Message, [ConsoleColor]$Color = 'Green')
    Write-Host "  $Message" -ForegroundColor $Color
}

function Write-CyberOK {
    param([string]$Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-CyberWarn {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Write-CyberError {
    param([string]$Message)
    Write-Host "  [X] $Message" -ForegroundColor Red
}

function Write-CyberDim {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor DarkGray
}

# ==============================
# HUD PROGRESS BAR
# ==============================

$script:SpinFrames = @('▸▹▹▹▹','▹▸▹▹▹','▹▹▸▹▹','▹▹▹▸▹','▹▹▹▹▸')
$script:SpinIdx    = 0

function Write-HudProgress {
    param([int]$Elapsed, [int]$Total, [string]$Label = "PROC", [datetime]$StartTime = [datetime]::MinValue)

    $pct    = [math]::Min([int](($Elapsed / $Total) * 30), 30)
    $filled = "█" * $pct
    $empty  = "░" * (30 - $pct)
    $frame  = $script:SpinFrames[$script:SpinIdx % 5]
    $script:SpinIdx++
    $pctNum = [math]::Min([int](($Elapsed / $Total) * 100), 100)

    # Real wall-clock elapsed — more honest than loop counter
    if ($StartTime -ne [datetime]::MinValue) {
        $wallSec = [int]([datetime]::Now - $StartTime).TotalSeconds
    } else {
        $wallSec = $Elapsed
    }

    $line = "  [$frame] [$filled$empty] $pctNum% · ${wallSec}s / ${Total}s · $Label"
    Write-Host "`r$line" -NoNewline -ForegroundColor Green
}

function Write-HudProgressComplete {
    param([int]$Total, [string]$Label = "PROC", [datetime]$StartTime = [datetime]::MinValue)

    if ($StartTime -ne [datetime]::MinValue) {
        $wallSec = [int]([datetime]::Now - $StartTime).TotalSeconds
    } else {
        $wallSec = $Total
    }

    $filled = "█" * 30
    $frame  = "▸▸▸▸▸"
    $line   = "  [$frame] [$filled] 100% · ${wallSec}s / ${Total}s · $Label"
    Write-Host "`r$line" -NoNewline -ForegroundColor Green
}

function Write-HudSpinner {
    param([string]$Label, [string]$Extra = "")
    $frame = $script:SpinFrames[$script:SpinIdx % 5]
    $script:SpinIdx++
    Write-Host "`r  [$frame] $Label $Extra" -NoNewline -ForegroundColor Green
}

# ==============================
# HELP METADATA
# ==============================

$CommandHelp = @{
    start = @{
        Description = "Starts the JBoss server."
        Usage       = "jarbas.ps1 start"
        Details     = "Initializes the environment and waits until the management port becomes available."
    }
    stop = @{
        Description = "Stops the JBoss server."
        Usage       = "jarbas.ps1 stop"
        Details     = "Uses jboss-cli shutdown and waits until the management port is closed."
    }
    restart = @{
        Description = "Performs a graceful reload."
        Usage       = "jarbas.ps1 restart"
        Details     = "Uses :reload via JBoss CLI and monitors the restart cycle."
    }
    deploy = @{
        Description = "Builds with Maven Wrapper and deploys to JBoss."
        Usage       = "jarbas.ps1 deploy [-SkipTest] [-DryRun]"
        Details     = "Runs mvnw.cmd clean package; copies the built artifact to the JBoss deployments directory and creates a .dodeploy marker."
    }
    undeploy = @{
        Description = "Undeploy artifact on JBoss."
        Usage       = "jarbas.ps1 undeploy"
        Details     = "Using jboss-cli to undeploy artifact."
    }
    remove = @{
        Description = "Removes the deployed artifact from JBoss deployments."
        Usage       = "jarbas.ps1 remove"
        Details     = "Deletes the artifact from the JBoss deployments directory and clears deployment markers."
    }
    "start-deploy" = @{
        Description = "Builds/deploys the artifact and then starts the server."
        Usage       = "jarbas.ps1 start-deploy [-SkipTest] [-DryRun]"
        Details     = "Combines the deploy workflow followed by the startup workflow."
    }
    "undeploy-remove" = @{
        Description = "Undeploys via CLI then physically removes the artifact and all markers."
        Usage       = "jarbas.ps1 undeploy-remove"
        Details     = "Runs undeploy first and waits for confirmation. Only removes the file if undeploy succeeded. Aborts on any CLI or marker error."
    }
    status = @{
        Description = "Displays the current server status."
        Usage       = "jarbas.ps1 status"
        Details     = "Shows PID, status, and port availability."
    }
}

# ==============================
# BANNER
# ==============================

function Show-Banner {
    Write-Host ""
    Write-ScanlineBlock -Lines 2

    $bannerLines = @(
        "     ██╗ █████╗ ██████╗ ██████╗  █████╗ ███████╗",
        "     ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝",
        "     ██║███████║██████╔╝██████╔╝███████║███████╗ ",
        "██   ██║██╔══██║██╔══██╗██╔══██╗██╔══██║╚════██║",
        "╚█████╔╝██║  ██║██║  ██║██████╔╝██║  ██║███████║",
        " ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝"
    )

    Write-GlitchBlock -Lines $bannerLines -Iterations 5 -DelayMs 20

    Write-ScanlineBlock -Lines 1

    Write-Host ""
    Write-Host ("  " + ("─" * 50)) -ForegroundColor DarkGreen
    Write-Host "  JARBAS ENTERPRISE CLI  ·  v1.0.0  ·  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "  $(Get-SysCoords)" -ForegroundColor DarkGray
    Write-Host ("  " + ("─" * 50)) -ForegroundColor DarkGreen
    Write-Host ""
}

# ==============================
# HELP FUNCTIONS
# ==============================

function Show-Help {
    Show-Banner

    Write-HudHeader "COMMAND REFERENCE"

    Write-Host "  USAGE:" -ForegroundColor Cyan
    Write-Host "    jarbas.ps1 <command> [options]" -ForegroundColor Green
    Write-Host ""
    Write-Host "  COMMANDS:" -ForegroundColor Cyan
    foreach ($cmd in $CommandHelp.Keys) {
        Write-Host ("    {0,-16} " -f $cmd) -ForegroundColor Green -NoNewline
        Write-Host $CommandHelp[$cmd].Description -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  OPTIONS:" -ForegroundColor Cyan
    Write-Host "    -SkipTest       Skip Maven tests during build" -ForegroundColor Green
    Write-Host "    -DryRun         Show actions without executing" -ForegroundColor Green
    Write-Host "    -VerboseLog     Enable verbose logging" -ForegroundColor Green
    Write-Host "    -Help           Show this help" -ForegroundColor Green
    Write-Host ""
    Write-Host "  TIP:" -ForegroundColor Cyan
    Write-Host "    jarbas.ps1 help start" -ForegroundColor DarkGray
    Write-HudFooter
}

function Show-CommandHelp {
    param([string]$CmdName)

    if (-not $CommandHelp.ContainsKey($CmdName)) {
        Write-CyberError "UNKNOWN COMMAND: $CmdName"
        return
    }

    Show-Banner

    $cmd = $CommandHelp[$CmdName]
    Write-HudHeader "HELP :: $($CmdName.ToUpper())"

    Write-Host "  COMMAND  :" -ForegroundColor Cyan -NoNewline
    Write-Host " $CmdName" -ForegroundColor Green
    Write-Host "  DESC     :" -ForegroundColor Cyan -NoNewline
    Write-Host " $($cmd.Description)" -ForegroundColor Green
    Write-Host "  USAGE    :" -ForegroundColor Cyan -NoNewline
    Write-Host " $($cmd.Usage)" -ForegroundColor Green
    Write-Host "  DETAILS  :" -ForegroundColor Cyan -NoNewline
    Write-Host " $($cmd.Details)" -ForegroundColor DarkGray

    Write-HudFooter
}

if (-not $Command -or $Help) {
    Show-Help
    exit 0
}

if ($Command -eq "help") {
    if ($HelpTopic -and $CommandHelp.ContainsKey($HelpTopic)) {
        Show-CommandHelp -CmdName $HelpTopic
    } else {
        Show-Help
    }
    exit 0
}

# ==============================
# PATHS
# ==============================

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "jarbas.config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-CyberError "CONFIG FILE NOT FOUND: $ConfigFile"
    exit 1
}

$cfg           = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$JarbasPidFile = Join-Path $ScriptDir "jarbas.pid"

# ── Centralised logs directory ────────────────────────────────────────────
# All log files live under <ScriptDir>\logs\ regardless of what config says.
$LogsDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}
$LogFile  = Join-Path $LogsDir "jarbas.log"
$BuildLog = Join-Path $LogsDir "maven-build.log"
$CliLog   = Join-Path $LogsDir "jboss-cli.log"

# ==============================
# LOG SYSTEM
# ==============================

function Write-Log {
    param([string]$Level, [string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    if ($VerboseLog -or $Level -ne "DEBUG") {
        switch ($Level) {
            "ERROR" { Write-CyberError $Message }
            "WARN"  { Write-CyberWarn  $Message }
            "DEBUG" { Write-CyberDim   "DBG: $Message" }
            default { Write-Cyber      "·· $Message" }
        }
    }

    Add-Content -Path $LogFile -Value $line
}

function Die {
    param([string]$Message)
    Write-Log "ERROR" $Message
    Write-ScanlineBlock -Lines 1
    exit 1
}

# ==============================
# NETWORK: TEST TCP PORT
# ==============================

function Test-Port {
    param([string]$HostName, [int]$Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($HostName, $Port)
        $tcp.Close()
        return $true
    }
    catch { return $false }
}

# ==============================
# DEPLOY
# ==============================

function Deploy {

    Write-HudHeader "DEPLOY SEQUENCE"

    $env:JAVA_HOME = $cfg.java.home
    $env:Path      = "$($cfg.java.bin_dir);$env:Path"

    $mvnw = $cfg.maven.wrapper
    if (-not (Test-Path $mvnw)) { Die "MAVEN WRAPPER NOT FOUND: $mvnw" }

    $projRoot  = $cfg.project.root_dir
    $targetDir = $cfg.project.target_dir
    if (-not (Test-Path $projRoot)) { Die "PROJECT ROOT NOT FOUND: $projRoot" }

    $deployDir = $cfg.jboss.deployments_dir
    if (-not (Test-Path $deployDir)) { Die "DEPLOYMENTS DIR NOT FOUND: $deployDir" }

    $artifactName    = $cfg.project.artifact_name
    $artifactVersion = $cfg.project.artifact_version
    $packaging       = if ($cfg.project.packaging) { $cfg.project.packaging } else { "war" }

    # Canonical artifact filename: name-version.packaging  e.g. meu-projeto-1.0.0.jar
    $artifactFullName   = "$artifactName-$artifactVersion.$packaging"
    $patternWithVersion = "$artifactName-$artifactVersion.$packaging"
    $patternNoVersion   = "$artifactName*.$packaging"

    $mvnArgs = "clean package"
    if ($SkipTest) {
        $mvnArgs += " -DskipTests"
        Write-Log "INFO" "SkipTest enabled"
    }

    if ($DryRun) {
        Write-CyberWarn "DRY RUN MODE — NO CHANGES WILL BE MADE"
        Write-CyberDim  "CMD  : $mvnw $mvnArgs"
        Write-CyberDim  "SCAN : $targetDir"
        Write-CyberDim  "DEST : $deployDir"
        Write-Log "INFO" "DryRun — Deploy not executed"
        Write-HudFooter
        return
    }

    # ── PHASE 1 ── ENV ──────────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 1/4 · ENVIRONMENT"
    Write-Log "INFO" "JAVA_HOME=$($cfg.java.home)"

    # ── PHASE 2 ── BUILD ─────────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 2/4 · MAVEN BUILD"
    Write-Log "INFO" "Executing: $mvnw $mvnArgs"

    $buildLog = $BuildLog
    if (Test-Path $buildLog) { Remove-Item $buildLog -Force -ErrorAction SilentlyContinue }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $mvnw
    $psi.Arguments              = $mvnArgs
    $psi.WorkingDirectory       = $projRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()

    # Maven phase anchors → estimated progress %
    # Each entry: pattern to match in stdout → [pct, label]
    $mavenPhases = [ordered]@{
        "Building"                        = @(5,  "RESOLVING")
        "Downloading"                     = @(10, "DOWNLOADING")
        "Downloaded"                      = @(18, "DEPENDENCIES OK")
        "generate-sources"                = @(22, "GENERATE-SOURCES")
        "process-sources"                 = @(26, "PROCESS-SOURCES")
        "generate-resources"              = @(30, "GENERATE-RESOURCES")
        "compile"                         = @(40, "COMPILING")
        "process-classes"                 = @(48, "PROCESS-CLASSES")
        "generate-test-sources"           = @(52, "TEST-SOURCES")
        "test-compile"                    = @(56, "TEST-COMPILE")
        "test"                            = @(62, "TESTING")
        "prepare-package"                 = @(70, "PREPARE-PACKAGE")
        "package"                         = @(80, "PACKAGING")
        "verify"                          = @(88, "VERIFYING")
        "install"                         = @(94, "INSTALLING")
        "BUILD SUCCESS"                   = @(100, "BUILD SUCCESS")
        "BUILD FAILURE"                   = @(100, "BUILD FAILURE")
    }

    $currentPct   = 0
    $currentLabel = "STARTING"
    $lines        = 0
    $barWidth     = 30

    function Render-MavenBar {
        param([int]$Pct, [string]$Label, [int]$Lines)
        $filled = [math]::Min([int](($Pct / 100) * $barWidth), $barWidth)
        $empty  = $barWidth - $filled
        $bar    = ("█" * $filled) + ("░" * $empty)
        $frame  = $script:SpinFrames[$script:SpinIdx % 5]
        $script:SpinIdx++
        $noise  = Get-GlitchString -Length 4
        Write-Host "`r  [$frame] [$bar] $Pct% · $Label · $lines ln · $noise" -NoNewline -ForegroundColor Green
    }

    while (-not $proc.HasExited) {
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            Add-Content -Path $buildLog -Value $line
            $lines++

            # Check if this line matches a known Maven phase anchor
            foreach ($key in $mavenPhases.Keys) {
                if ($line -match [regex]::Escape($key)) {
                    $phaseData = $mavenPhases[$key]
                    if ($phaseData[0] -gt $currentPct) {
                        $currentPct   = $phaseData[0]
                        $currentLabel = $phaseData[1]
                    }
                    break
                }
            }
        }
        Render-MavenBar -Pct $currentPct -Label $currentLabel -Lines $lines
        Start-Sleep -Milliseconds 150
    }

    # Flush remaining output
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        Add-Content -Path $buildLog -Value $line
        $lines++
    }
    while (-not $proc.StandardError.EndOfStream) {
        Add-Content -Path $buildLog -Value $proc.StandardError.ReadLine()
    }

    if ($proc.ExitCode -ne 0) {
        # Force bar to show failure state
        $filled = ("█" * $barWidth)
        Write-Host "`r  [✖] [$filled] FAILED · $currentLabel · $lines ln      " -ForegroundColor Red
        Write-Host ""
        Write-Log "ERROR" "Maven build FAILED (ExitCode=$($proc.ExitCode)) — see: $buildLog"
        Write-ScanlineBlock -Lines 2
        return
    }

    # Force bar to 100% on success
    $filled = "█" * $barWidth
    $frame  = "▸▸▸▸▸"
    Write-Host "`r  [$frame] [$filled] 100% · BUILD SUCCESS · $lines ln      " -ForegroundColor Green
    Write-Host ""
    Write-Log "INFO" "Maven build finished successfully"
    Write-CyberOK "BUILD SUCCESSFUL"

    # ── PHASE 3 ── LOCATE ────────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 3/4 · ARTIFACT SCAN"

    $artifact = Get-ChildItem -Path $targetDir -Filter $patternWithVersion -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $artifact) {
        $artifact = Get-ChildItem -Path $targetDir -Filter $patternNoVersion -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if (-not $artifact) { Die "NO .$packaging ARTIFACT FOUND IN $targetDir" }

    Write-Log "INFO" "Artifact found: $($artifact.FullName)"
    Write-CyberOK "ARTIFACT LOCKED → $($artifact.Name)"

    # ── PHASE 4 ── DEPLOY ────────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 4/4 · DEPLOY TO TARGET"

    $destFile = Join-Path $deployDir $artifact.Name
    Write-Log "INFO" "Copying to: $destFile"

    # Spinner durante o copy (pode ser lento em arquivos grandes)
    $copyJob = Start-Job -ScriptBlock {
        param($src, $dst)
        Copy-Item -Path $src -Destination $dst -Force
    } -ArgumentList $artifact.FullName, $destFile

    $copyIdx = 0
    while ($copyJob.State -eq 'Running') {
        $frame = $script:SpinFrames[$copyIdx % 5]
        $copyIdx++
        Write-Host "`r  [$frame] COPYING ARTIFACT → $($artifact.Name)" -NoNewline -ForegroundColor Green
        Start-Sleep -Milliseconds 120
    }

    $copyResult = Receive-Job $copyJob -ErrorVariable copyErr
    Remove-Job $copyJob

    if ($copyErr) { Die "COPY FAILED: $copyErr" }

    Write-Host "`r  [▸▸▸▸▸] COPY COMPLETE → $($artifact.Name)          " -ForegroundColor Green
    Write-Host ""

    $doDeploy = "$destFile.dodeploy"
    try {
        $markers = @(
            "$destFile.dodeploy","$destFile.deployed","$destFile.failed",
            "$destFile.isdeploying","$destFile.isundeploying","$destFile.undeployed"
        )
        $total   = $markers.Count
        $current = 0
        foreach ($m in $markers) {
            $current++
            $pct    = [int](($current / $total) * 100)
            $filled = [math]::Min([int](($current / $total) * 20), 20)
            $bar    = ("█" * $filled) + ("░" * (20 - $filled))
            Write-Host "`r  [·] [$bar] $pct% · CLEARING MARKERS" -NoNewline -ForegroundColor DarkGray
            if (Test-Path $m) { Remove-Item $m -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 80
        }
        Write-Host "`r  [▸▸▸▸▸] [████████████████████] 100% · MARKERS CLEARED   " -ForegroundColor Green
        Write-Host ""

        New-Item -Path $doDeploy -ItemType File -Force | Out-Null
        Write-Log "INFO" "Marker created: $doDeploy"
    }
    catch { Die "MARKER CREATION FAILED: $($_.Exception.Message)" }

    Write-CyberOK "DEPLOY SUBMITTED · WAITING ON .DODEPLOY SIGNAL"
    Write-ScanlineBlock -Lines 1
    Write-HudFooter
}

# ==============================
# START JBoss
# ==============================

function Start-JBoss {

    Write-HudHeader "SERVER BOOT"

    $scriptPath = Join-Path $cfg.jboss.bin_dir $cfg.jboss.startup_script

    if ($DryRun) {
        Write-CyberWarn "DRY RUN — CMD: $scriptPath -c $($cfg.jboss.config)"
        Write-HudFooter
        return
    }

    $env:JAVA_HOME = $cfg.java.home
    $env:Path      = "$($cfg.java.bin_dir);$env:Path"

    Write-Log "INFO" "JAVA_HOME=$env:JAVA_HOME"
    Write-Log "INFO" "Launching: $scriptPath"

    Write-GlitchLine -FinalText "INITIATING BOOT SEQUENCE"

    $process = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c `"$scriptPath -c $($cfg.jboss.config)`"" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden `
        -PassThru

    $process.Id | Out-File $JarbasPidFile -Force

    Write-Log "DEBUG" "Script : $scriptPath"
    Write-Log "DEBUG" "Config : $($cfg.jboss.config)"

    Write-Cyber "POLLING $($cfg.jboss.host):$($cfg.jboss.port) ··" -Color Cyan
    Write-Host ""

    $timeout   = $cfg.jboss.startup_timeout
    $elapsed   = 0
    $bootStart = [datetime]::Now

    while ($elapsed -lt $timeout) {
        Write-HudProgress -Elapsed $elapsed -Total $timeout -Label "BOOT" -StartTime $bootStart

        if (Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port) {
            Write-HudProgressComplete -Total $timeout -Label "BOOT" -StartTime $bootStart
            Write-Host ""
            Write-GlitchLine -FinalText "MANAGEMENT PORT OPEN"
            Write-Log "INFO" "JBoss is ONLINE"
            Write-CyberOK "SERVER ONLINE · PID $($process.Id) · PORT $($cfg.jboss.port)"
            Write-ScanlineBlock -Lines 1
            Write-HudFooter
            return
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Host ""
    Write-Log "ERROR" "Boot timeout after ${timeout}s"
    Write-CyberError "BOOT TIMEOUT — SERVER DID NOT RESPOND AFTER ${timeout}s"
    Write-CyberDim   "  Management port $($cfg.jboss.host):$($cfg.jboss.port) never opened."
    Write-CyberDim   "  Possible causes:"
    Write-CyberDim   "    · JBoss failed to start — check boot log:"
    Write-CyberDim   "      $($cfg.jboss.boot_log)"
    Write-CyberDim   "    · Server log for runtime errors:"
    Write-CyberDim   "      $($cfg.jboss.log_file)"
    Write-CyberDim   "    · Wrong JAVA_HOME: $($cfg.java.home)"
    Write-CyberDim   "    · Port $($cfg.jboss.port) already in use by another process"
    Write-CyberDim   "      Check: netstat -ano | findstr $($cfg.jboss.port)"
    Write-HudFooter
    exit 1
}

# ==============================
# STOP JBoss
# ==============================

function Stop-JBoss {

    Write-HudHeader "SERVER SHUTDOWN"

    $cliPath    = Join-Path $cfg.jboss.bin_dir "jboss-cli.bat"
    $controller = "$($cfg.jboss.host):$($cfg.jboss.port)"

    # Pre-check: is the server even reachable before trying CLI?
    Write-GlitchLine -FinalText "CHECKING MANAGEMENT PORT"
    if (-not (Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port)) {
        Write-Host ""
        Write-CyberWarn "SERVER IS NOT RESPONDING ON $controller"
        Write-CyberWarn "NOTHING TO STOP — SERVER MAY ALREADY BE OFFLINE"
        Write-CyberDim  "  If the process is still running, kill it manually via Task Manager"
        Write-CyberDim  "  or check: Get-Process -Name 'java'"
        Write-Log "WARN" "Stop aborted — port $controller not responding before CLI call"
        Write-HudFooter
        return
    }

    # Run jboss-cli capturing stdout + stderr
    Write-GlitchLine -FinalText "ISSUING SHUTDOWN COMMAND"

    $cliLog  = $CliLog

    # Build args array — avoids all quoting/escaping issues with cmd /c
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $cliPath
    $psi.Arguments              = "--connect --controller=$controller --command=:shutdown"
    $psi.WorkingDirectory       = $cfg.jboss.bin_dir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $cliProc   = New-Object System.Diagnostics.Process
    $cliProc.StartInfo = $psi

    $stdoutBuf = [System.Text.StringBuilder]::new()
    $stderrBuf = [System.Text.StringBuilder]::new()
    $cliProc.add_OutputDataReceived({ param($s,$e); if ($null -ne $e.Data) { [void]$stdoutBuf.AppendLine($e.Data) } })
    $cliProc.add_ErrorDataReceived( { param($s,$e); if ($null -ne $e.Data) { [void]$stderrBuf.AppendLine($e.Data) } })

    $null = $cliProc.Start()
    $cliProc.BeginOutputReadLine()
    $cliProc.BeginErrorReadLine()

    $spinIdx    = 0
    $cliTimeout = 30
    $cliStart   = [datetime]::Now

    while (-not $cliProc.HasExited) {
        $waited = ([datetime]::Now - $cliStart).TotalSeconds
        if ($waited -gt $cliTimeout) {
            $cliProc.Kill()
            Write-Host ""
            Write-CyberError "CLI TIMEOUT — jboss-cli did not respond within ${cliTimeout}s"
            Write-CyberDim   "  Partial output (if any): $cliLog"
            Write-Log "ERROR" "CLI timeout after ${cliTimeout}s"
            Write-HudFooter
            return
        }
        $frame = $script:SpinFrames[$spinIdx % 5]; $spinIdx++
        Write-Host "`r  [$frame] WAITING FOR CLI RESPONSE ··· controller=$controller  ($([int]$waited)s)" -NoNewline -ForegroundColor Green
        Start-Sleep -Milliseconds 200
    }
    $cliProc.WaitForExit()
    Write-Host ""

    $cliOutput = $stdoutBuf.ToString() + "`n" + $stderrBuf.ToString()
    Set-Content -Path $cliLog -Value $cliOutput -Force
    $cliExitCode = $cliProc.ExitCode

    Write-Log "DEBUG" "jboss-cli shutdown exit code: $cliExitCode — log: $cliLog"

    # Check for known errors
    $knownError = Resolve-CliError -Output $cliOutput
    if ($knownError) {
        Write-ScanlineBlock -Lines 1
        Write-CyberError $knownError
        Write-CyberDim   "  Full CLI output saved to: $cliLog"
        Write-Log "ERROR" $knownError
        Write-HudFooter
        return
    }

    if ($cliExitCode -ne 0) {
        $lastLine = ($cliOutput -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
        Write-ScanlineBlock -Lines 1
        Write-CyberError "CLI EXITED WITH CODE $cliExitCode"
        Write-CyberDim   "  HINT: $lastLine"
        Write-CyberDim   "  Full output: $cliLog"
        Write-Log "ERROR" "CLI exit $cliExitCode — $lastLine"
        Write-HudFooter
        return
    }

    # CLI succeeded — poll port until closed
    Write-Cyber "CLI OK · DRAINING $controller ··" -Color Cyan
    Write-Host ""

    $timeout       = 30
    $elapsed       = 0
    $shutdownStart = [datetime]::Now

    while ($elapsed -lt $timeout) {
        Write-HudProgress -Elapsed $elapsed -Total $timeout -Label "SHUTDOWN" -StartTime $shutdownStart

        if (-not (Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port)) {
            Write-HudProgressComplete -Total $timeout -Label "SHUTDOWN" -StartTime $shutdownStart
            Write-Host ""
            Write-GlitchLine -FinalText "PORT CLOSED"
            Write-Log "INFO" "JBoss fully stopped"
            Write-CyberOK "SERVER OFFLINE"
            Remove-Item $JarbasPidFile -Force -ErrorAction SilentlyContinue
            Write-ScanlineBlock -Lines 1
            Write-HudFooter
            return
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Host ""
    Write-Log "WARN" "Shutdown timeout — port still open after ${timeout}s"
    Write-CyberWarn "SHUTDOWN TIMEOUT — PORT $controller STILL OPEN AFTER ${timeout}s"
    Write-CyberDim  "  The server accepted the shutdown command but is taking too long."
    Write-CyberDim  "  Check server log: $($cfg.jboss.log_file)"
    Write-CyberDim  "  Or force-kill: Get-Process -Name 'java' | Stop-Process"
    Write-HudFooter
}

# ==============================
# RESTART
# ==============================

function Restart-JBoss {
    Write-HudHeader "RESTART CYCLE"
    Stop-JBoss
    Start-JBoss
}

# ==============================
# START-DEPLOY
# ==============================

function Start-And-Deploy-Project {
    Clear-And-ShowLastCommand
    Deploy
    Start-JBoss
}

# ==============================
# REMOVE ARTIFACT
# ==============================

function Remove-Artifact {
    Write-HudHeader "ARTIFACT REMOVAL"

    $deployDir = $cfg.jboss.deployments_dir
    $name      = $cfg.project.artifact_name
    $version   = $cfg.project.artifact_version
    $packaging = if ($cfg.project.packaging) { $cfg.project.packaging } else { "war" }

    if (-not (Test-Path $deployDir)) { Die "DEPLOYMENTS DIR NOT FOUND: $deployDir" }

    # Match exact versioned name first, fallback to wildcard
    $pattern  = if ($version) { "$name-$version.$packaging" } else { "$name*.$packaging" }
    $artifact = Get-ChildItem -Path $deployDir -Filter $pattern -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $artifact) { Die "NO ARTIFACT MATCHING '$pattern' IN '$deployDir'" }

    Write-GlitchLine -FinalText "TARGET ACQUIRED: $($artifact.Name)"
    Write-Log "INFO" "Removing: $($artifact.FullName)"

    try {
        $markers = @(
            "$($artifact.FullName).dodeploy","$($artifact.FullName).deployed","$($artifact.FullName).failed",
            "$($artifact.FullName).isdeploying","$($artifact.FullName).isundeploying","$($artifact.FullName).undeployed"
        )
        $total   = $markers.Count + 1   # +1 for the artifact itself
        $current = 0

        foreach ($m in $markers) {
            $current++
            $pct    = [int](($current / $total) * 100)
            $filled = [math]::Min([int](($current / $total) * 20), 20)
            $bar    = ("█" * $filled) + ("░" * (20 - $filled))
            Write-Host "`r  [·] [$bar] $pct% · PURGING MARKERS" -NoNewline -ForegroundColor DarkGray
            if (Test-Path $m) { Remove-Item $m -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 80
        }

        $current++
        $pct    = [int](($current / $total) * 100)
        $filled = [math]::Min([int](($current / $total) * 20), 20)
        $bar    = ("█" * $filled) + ("░" * (20 - $filled))
        Write-Host "`r  [·] [$bar] $pct% · REMOVING ARTIFACT" -NoNewline -ForegroundColor Green
        Remove-Item $artifact.FullName -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 80

        Write-Host "`r  [▸▸▸▸▸] [████████████████████] 100% · ARTIFACT PURGED   " -ForegroundColor Green
        Write-Host ""
        Write-Log "INFO" "Artifact removed"
        Write-CyberOK "ARTIFACT PURGED"
    }
    catch { Die "REMOVE FAILED: $($_.Exception.Message)" }

    Write-ScanlineBlock -Lines 1
    Write-HudFooter
}

# ==============================
# UNDEPLOY — CLI ERROR PATTERNS
# ==============================
# Maps known jboss-cli output fragments to human-readable messages.
# Checked against both stdout and stderr after the process exits.

# Patterns are only checked when exit code != 0.
# Broad patterns like "Error:" are intentionally excluded to avoid false
# positives from the JVM WARNING lines that appear in every CLI invocation.
$CliErrorPatterns = [ordered]@{
    "Could not connect to remote"         = "CANNOT CONNECT TO CONTROLLER — IS THE SERVER RUNNING?"
    "Connection refused"                  = "CONNECTION REFUSED ON $($cfg.jboss.host):$($cfg.jboss.port)"
    "WFLYPRT0053"                         = "JBOSS PORT UNREACHABLE — CHECK HOST/PORT IN CONFIG"
    "Failed to connect to the controller" = "CLI FAILED TO CONNECT TO MANAGEMENT INTERFACE"
    "WFLYCTL0216"                         = "DEPLOYMENT NOT FOUND ON SERVER — ALREADY UNDEPLOYED?"
    "WFLYCTL0062"                         = "COMPOSITE OPERATION FAILED — DEPLOYMENT MAY NOT EXIST"
    "WFLYCTL0379"                         = "DEPLOYMENT IS STILL IN USE — CANNOT UNDEPLOY NOW"
    "WFLYCTL0217"                         = "OPERATION CANCELLED BY SERVER"
    "AuthenticationException"             = "AUTHENTICATION FAILED — CHECK JBOSS MANAGEMENT CREDENTIALS"
    "BUILD FAILURE"                       = "CLI SCRIPT REPORTED BUILD FAILURE"
}

function Resolve-CliError {
    param([string]$Output)
    # Only match specific WFLY error codes and connection failures.
    # Never match on generic strings that appear in normal JVM output (WARNING, Error:, etc.)
    foreach ($pattern in $CliErrorPatterns.Keys) {
        if ($Output -match [regex]::Escape($pattern)) {
            return $CliErrorPatterns[$pattern]
        }
    }
    return $null
}

# ==============================
# UNDEPLOY
# ==============================

function Invoke-Undeploy {
    Write-HudHeader "UNDEPLOY SEQUENCE"
    Write-GlitchLine -FinalText "SENDING UNDEPLOY SIGNAL"

    $cliPath    = Join-Path $cfg.jboss.bin_dir "jboss-cli.bat"
    $controller = "$($cfg.jboss.host):$($cfg.jboss.port)"
    $deployDir  = $cfg.jboss.deployments_dir
    $artifact   = $cfg.project.artifact_name
    $version    = $cfg.project.artifact_version
    $packaging  = if ($cfg.project.packaging) { $cfg.project.packaging } else { "war" }
    $fullName   = if ($version) { "$artifact-$version.$packaging" } else { "$artifact.$packaging" }

    # ── Pre-flight: check if the server is reachable ────────────────────────
    Write-GlitchLine -FinalText "CHECKING MANAGEMENT PORT"
    if (-not (Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port)) {
        Write-Host ""
        Write-CyberWarn "SERVER IS NOT RESPONDING ON $controller"
        Write-CyberWarn "CANNOT UNDEPLOY — SERVER IS OFFLINE"
        Write-CyberDim  "  Start the server first, or use 'remove' to force-delete the file."
        Write-Log "WARN" "Undeploy aborted — port $controller not responding"
        Write-HudFooter
        return
    }

    # ── Run jboss-cli via cmd.exe /c ────────────────────────────────────────
    # .bat files must be invoked through cmd.exe on Windows — calling them
    # directly via ProcessStartInfo causes the wrapper to exit immediately
    # before the Java child process finishes, making HasExited unreliable.
    $cliLog      = $CliLog
    $cliCommand  = "`"$cliPath`" --connect --controller=$controller --command=`"undeploy $fullName`""

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "cmd.exe"
    $psi.Arguments              = "/c $cliCommand"
    $psi.WorkingDirectory       = $cfg.jboss.bin_dir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $cliProc   = New-Object System.Diagnostics.Process
    $cliProc.StartInfo = $psi

    $stdoutBuf = [System.Text.StringBuilder]::new()
    $stderrBuf = [System.Text.StringBuilder]::new()
    $cliProc.add_OutputDataReceived({ param($s,$e); if ($null -ne $e.Data) { [void]$stdoutBuf.AppendLine($e.Data) } })
    $cliProc.add_ErrorDataReceived( { param($s,$e); if ($null -ne $e.Data) { [void]$stderrBuf.AppendLine($e.Data) } })

    $null = $cliProc.Start()
    $cliProc.BeginOutputReadLine()
    $cliProc.BeginErrorReadLine()

    $spinIdx    = 0
    $cliTimeout = 30
    $cliStart   = [datetime]::Now

    while (-not $cliProc.HasExited) {
        $waited = ([datetime]::Now - $cliStart).TotalSeconds
        if ($waited -gt $cliTimeout) {
            $cliProc.Kill()
            Write-Host ""
            Write-CyberError "CLI TIMEOUT — jboss-cli did not respond within ${cliTimeout}s"
            Write-CyberDim   "  The CLI process was forcibly terminated."
            Write-CyberDim   "  Partial output (if any): $cliLog"
            Write-Log "ERROR" "CLI timeout after ${cliTimeout}s"
            Write-HudFooter
            return
        }
        $frame = $script:SpinFrames[$spinIdx % 5]; $spinIdx++
        Write-Host "`r  [$frame] CALLING JBOSS-CLI ··· controller=$controller  ($([int]$waited)s)" -NoNewline -ForegroundColor Green
        Start-Sleep -Milliseconds 200
    }
    $cliProc.WaitForExit()
    Write-Host ""

    $cliOutput   = $stdoutBuf.ToString() + "`n" + $stderrBuf.ToString()
    $cliExitCode = $cliProc.ExitCode

    # Always save full CLI output for debugging
    Set-Content -Path $cliLog -Value $cliOutput -Force
    Write-Log "DEBUG" "jboss-cli exit=$cliExitCode · log=$cliLog"

    # ── Interpret CLI result ─────────────────────────────────────────────────
    # Only check for known errors if the process reported failure.
    # exit 0 with WARNING lines in output is normal JVM noise — not an error.
    if ($cliExitCode -ne 0) {
        $knownError = Resolve-CliError -Output $cliOutput
        if ($knownError) {
            Write-ScanlineBlock -Lines 1
            Write-CyberError $knownError
            Write-Log "ERROR" $knownError
            Write-CyberDim   "  Full CLI output: $cliLog"
            Write-HudFooter
            return
        }
        # Unknown non-zero exit — show last meaningful line as hint
        $lastLine = ($cliOutput -split "`n" | Where-Object { $_ -notmatch '^\s*$' -and $_ -notmatch '^WARNING' } | Select-Object -Last 1)
        Write-ScanlineBlock -Lines 1
        Write-CyberError "CLI EXITED WITH CODE $cliExitCode"
        Write-CyberDim   "  HINT: $lastLine"
        Write-CyberDim   "  Full output: $cliLog"
        Write-Log "ERROR" "CLI exit $cliExitCode — $lastLine"
        Write-HudFooter
        return
    }

    # ── CLI succeeded — poll marker files until server confirms undeploy ───────
    $basePath      = Join-Path $deployDir $fullName
    $timeout       = 60
    $elapsed       = 0
    $undeployStart = [datetime]::Now

    Write-Cyber "CLI OK · POLLING SERVER FOR UNDEPLOY CONFIRMATION ··" -Color Cyan
    Write-Host ""

    # Grace period: give the server 2s to start processing before first check.
    # Without this the loop can exit immediately if the file was already gone
    # before the server had a chance to write any marker.
    Write-HudProgress -Elapsed 0 -Total $timeout -Label "UNDEPLOY" -StartTime $undeployStart
    Start-Sleep -Seconds 2
    $elapsed = 2

    while ($elapsed -lt $timeout) {

        # ── Always sleep first, then render, then check ──────────────────────
        # This ensures the bar is visible for at least one full tick before
        # any exit path fires, so the user always sees feedback.
        Start-Sleep -Seconds 1
        $elapsed++
        Write-HudProgress -Elapsed $elapsed -Total $timeout -Label "UNDEPLOY" -StartTime $undeployStart

        $fileGone       = -not (Test-Path $basePath)
        $undeployedMark =  (Test-Path "$($basePath).undeployed")
        $failedMark     =  (Test-Path "$($basePath).failed")
        $isUndeploying  =  (Test-Path "$($basePath).isundeploying")

        # Hard failure — server explicitly rejected the undeploy
        if ($failedMark) {
            Write-HudProgressComplete -Total $timeout -Label "UNDEPLOY" -StartTime $undeployStart
            Write-Host ""
            Write-CyberError "UNDEPLOY FAILED — SERVER REPORTED .failed MARKER"
            Write-CyberDim   "  Marker: $($basePath).failed"
            Write-CyberDim   "  Check server log: $($cfg.jboss.log_file)"
            Write-Log "ERROR" "Undeploy failed — .failed marker: $basePath"
            Write-ScanlineBlock -Lines 1
            Write-HudFooter
            return
        }

        # Still in progress — server is actively undeploying, keep waiting
        if ($isUndeploying) {
            continue
        }

        # Success — server confirmed undeploy via marker or file removal
        if ($undeployedMark -or $fileGone) {
            Write-HudProgressComplete -Total $timeout -Label "UNDEPLOY" -StartTime $undeployStart
            Write-Host ""
            Write-GlitchLine -FinalText "UNDEPLOY CONFIRMED"
            Write-Log "INFO" "Undeploy complete: $fullName"
            Write-CyberOK "UNDEPLOY COMPLETE"
            Write-ScanlineBlock -Lines 1
            Write-HudFooter
            return
        }
    }

    Write-Host ""
    Write-Log "WARN" "Undeploy timeout after ${timeout}s: $fullName"
    Write-CyberWarn "TIMEOUT — NO CONFIRMATION AFTER ${timeout}s"
    Write-CyberDim  "  CLI reported success but server marker was never written."
    Write-CyberDim  "  The undeploy may still complete — check server log:"
    Write-CyberDim  "  $($cfg.jboss.log_file)"
    Write-ScanlineBlock -Lines 1
    Write-HudFooter
}

# ==============================
# STATUS
# ==============================

function Get-JBossStatus {
    Write-HudHeader "SYSTEM STATUS"

    Write-Host ("  {0,-18} {1,-12} {2,-10} {3}" -f "PROCESS","STATUS","PID","PORT") -ForegroundColor Cyan
    Write-Host ("  " + ("─" * 50)) -ForegroundColor DarkGreen

    if (Test-Path $JarbasPidFile) {
        $jbossPid = Get-Content $JarbasPidFile
        $online   = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if ($online) {
            Write-Host ("  {0,-18} " -f "JBOSS") -ForegroundColor Green -NoNewline
            Write-Host ("{0,-12} " -f "ONLINE")   -ForegroundColor Green -NoNewline
            Write-Host ("{0,-10} " -f $jbossPid)  -ForegroundColor DarkGray -NoNewline
            Write-Host "$($cfg.jboss.port)"        -ForegroundColor Cyan
            Write-Host ""
            Write-CyberOK "MANAGEMENT PORT RESPONDING"
            Write-HudFooter
            return
        }
    }

    Write-Host ("  {0,-18} " -f "JBOSS") -ForegroundColor Green  -NoNewline
    Write-Host ("{0,-12} "   -f "OFFLINE") -ForegroundColor Red  -NoNewline
    Write-Host ("{0,-10} "   -f "-")       -ForegroundColor DarkGray -NoNewline
    Write-Host "-"                          -ForegroundColor DarkGray
    Write-Host ""
    Write-CyberWarn "SERVER NOT RESPONDING ON $($cfg.jboss.host):$($cfg.jboss.port)"
    Write-ScanlineBlock -Lines 1
    Write-HudFooter
}

# ==============================
# COMMAND LINE ECHO
# ==============================

function Get-EffectiveCommandLine {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($scriptPath)
    if ($Command)    { $parts.Add($Command) }
    if ($SkipTest)   { $parts.Add('-SkipTest') }
    if ($DryRun)     { $parts.Add('-DryRun') }
    if ($VerboseLog) { $parts.Add('-VerboseLog') }
    if ($Help)       { $parts.Add('-Help') }
    return ($parts -join ' ')
}

function Clear-And-ShowLastCommand {
    $cmdLine = Get-EffectiveCommandLine
    Clear-Host
    $Host.UI.RawUI.ForegroundColor = 'Green'
    Write-Host ""
    Write-Host "  > $cmdLine" -ForegroundColor DarkGray
    Show-Banner
}

# ==============================
# UNDEPLOY + REMOVE  (pipeline)
# ==============================

function Invoke-UndeployAndRemove {

    Write-HudHeader "UNDEPLOY + REMOVE PIPELINE"

    $deployDir = $cfg.jboss.deployments_dir
    $name      = $cfg.project.artifact_name
    $version   = $cfg.project.artifact_version
    $packaging = if ($cfg.project.packaging) { $cfg.project.packaging } else { "war" }
    $fullName  = if ($version) { "$name-$version.$packaging" } else { "$name.$packaging" }
    $basePath  = Join-Path $deployDir $fullName

    # ── Sanity checks before doing anything ─────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 1/3 · PRE-FLIGHT CHECKS"

    if (-not (Test-Path $deployDir)) {
        Write-CyberError "DEPLOYMENTS DIR NOT FOUND: $deployDir"
        Write-Log "ERROR" "Deployments dir not found: $deployDir"
        Write-HudFooter
        return
    }

    $artifactExists = Test-Path $basePath
    if (-not $artifactExists) {
        Write-CyberWarn "ARTIFACT NOT FOUND IN DEPLOYMENTS DIR: $fullName"
        Write-CyberDim  "  Path checked: $basePath"
        Write-CyberDim  "  It may have already been removed, or the config name is wrong."
        Write-Log "WARN" "Artifact not found before undeploy: $basePath"
        Write-HudFooter
        return
    }

    Write-CyberOK "ARTIFACT LOCATED: $fullName"

    if (-not (Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port)) {
        Write-CyberWarn "SERVER NOT RESPONDING ON $($cfg.jboss.host):$($cfg.jboss.port)"
        Write-CyberWarn "CANNOT UNDEPLOY — SERVER IS OFFLINE"
        Write-CyberDim  "  Use 'remove' instead to force-delete the file without CLI."
        Write-Log "WARN" "Undeploy-Remove aborted — server not reachable"
        Write-HudFooter
        return
    }

    Write-CyberOK "MANAGEMENT PORT REACHABLE"

    # ── Phase 2: Undeploy via CLI ────────────────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 2/3 · UNDEPLOY VIA CLI"

    # Call Invoke-Undeploy — it handles CLI errors, spinner and marker polling internally.
    # We capture whether it succeeded by checking the state of marker files afterward.
    Invoke-Undeploy

    # After Invoke-Undeploy returns, verify the outcome via marker files
    $undeployedMark  = Test-Path "$basePath.undeployed"
    $deployedMark    = Test-Path "$basePath.deployed"
    $failedMark      = Test-Path "$basePath.failed"
    $fileStillExists = Test-Path $basePath

    if ($failedMark) {
        Write-CyberError "UNDEPLOY FAILED — SERVER REPORTED A FAILURE MARKER"
        Write-CyberDim   "  Marker found: $basePath.failed"
        Write-CyberDim   "  Check server log: $($cfg.jboss.log_file)"
        Write-Log "ERROR" "Undeploy failed — .failed marker found: $basePath"
        Write-HudFooter
        return
    }

    if ($deployedMark -or ($fileStillExists -and -not $undeployedMark)) {
        Write-CyberError "UNDEPLOY DID NOT COMPLETE — ARTIFACT STILL APPEARS DEPLOYED"
        Write-CyberDim   "  deployed marker: $deployedMark"
        Write-CyberDim   "  undeployed marker: $undeployedMark"
        Write-CyberDim   "  artifact file exists: $fileStillExists"
        Write-CyberDim   "  Aborting remove to avoid data corruption."
        Write-Log "ERROR" "Undeploy-Remove aborted — artifact still deployed after CLI call"
        Write-HudFooter
        return
    }

    Write-CyberOK "UNDEPLOY CONFIRMED — PROCEEDING TO REMOVE"

    # ── Phase 3: Physical removal ────────────────────────────────────────────
    Write-GlitchLine -FinalText "PHASE 3/3 · PHYSICAL REMOVAL"

    Remove-Artifact

    Write-CyberOK "PIPELINE COMPLETE · ARTIFACT UNDEPLOYED AND REMOVED"
    Write-HudFooter
}

# ==============================
# ROUTER
# ==============================

switch ($Command) {
    "start"         { Clear-And-ShowLastCommand; Start-JBoss }
    "stop"          { Clear-And-ShowLastCommand; Stop-JBoss }
    "restart"       { Clear-And-ShowLastCommand; Restart-JBoss }
    "remove"        { Clear-And-ShowLastCommand; Remove-Artifact }
    "status"        { Clear-And-ShowLastCommand; Get-JBossStatus }
    "deploy"        { Clear-And-ShowLastCommand; Deploy }
    "undeploy"        { Clear-And-ShowLastCommand; Invoke-Undeploy }
    "undeploy-remove" { Clear-And-ShowLastCommand; Invoke-UndeployAndRemove }
    "start-deploy"  { Clear-And-ShowLastCommand; Deploy; Start-JBoss }
    default {
        Clear-And-ShowLastCommand
        Write-CyberError "UNRECOGNIZED COMMAND: $Command"
        Write-Host ""
        Show-Help
        exit 1
    }
}