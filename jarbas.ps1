[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "deploy", "undeploy", "start-deploy", "status", "remove", "help")]
    [string]$Command,

    [switch]$SkipTest,
    [switch]$VerboseLog,
    [switch]$DryRun,

    [Alias('?', '/?')]
    [switch]$Help
)

# Force ASCII/green terminal feel
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.ForegroundColor = 'Green'

# ==============================
# HELP METADATA
# ==============================

$CommandHelp = @{
    start          = @{
        Description = "Initializes the JBoss application server process."
        Usage       = "jarbas.ps1 start"
        Details     = "Sets environment variables and polls management port until server responds or timeout."
    }
    stop           = @{
        Description = "Terminates the JBoss application server process."
        Usage       = "jarbas.ps1 stop"
        Details     = "Issues :shutdown via jboss-cli.bat and waits for port closure."
    }
    restart        = @{
        Description = "Stop followed by start. Full cycle."
        Usage       = "jarbas.ps1 restart"
        Details     = "Calls :reload via JBoss CLI and monitors restart cycle."
    }
    deploy         = @{
        Description = "Compile, package via Maven Wrapper and deploy artifact to JBoss."
        Usage       = "jarbas.ps1 deploy [-SkipTest] [-DryRun]"
        Details     = "Runs mvnw.cmd clean package. Copies artifact to deployments dir. Creates .dodeploy marker."
    }
    undeploy       = @{
        Description = "Undeploy artifact from JBoss via CLI."
        Usage       = "jarbas.ps1 undeploy"
        Details     = "Calls jboss-cli undeploy and polls for marker file removal."
    }
    remove         = @{
        Description = "Physically removes artifact from JBoss deployments directory."
        Usage       = "jarbas.ps1 remove"
        Details     = "Deletes artifact file and all associated deployment marker files."
    }
    "start-deploy" = @{
        Description = "Full pipeline: build, deploy, then boot server."
        Usage       = "jarbas.ps1 start-deploy [-SkipTest] [-DryRun]"
        Details     = "Combines deploy workflow followed immediately by startup workflow."
    }
    status         = @{
        Description = "Reports current server state to operator."
        Usage       = "jarbas.ps1 status"
        Details     = "Checks PID file and TCP port. Prints ONLINE or OFFLINE."
    }
}

# ==============================
# BANNER
# ==============================

function Show-Banner {
    $Host.UI.RawUI.ForegroundColor = 'Green'

    Write-Host ""
    Write-Host "  +===========================================================+"
    Write-Host "  |                                                           |"
    Write-Host "  |     ###    ###    ###    ###  ###  ####    ####   ####   |"
    Write-Host "  |      ##     ##     ##   ###   ###  ##  ##  ##  ## ##     |"
    Write-Host "  |      ##    ####    ##  ###    ###  ##  ##  ####   ####   |"
    Write-Host "  |  ##  ##   ##  ##   ## ###     ###  ##  ##  ##  ##     ## |"
    Write-Host "  |   ####   ###  ###  #####      ###  ####   ####   ####    |"
    Write-Host "  |                                                           |"
    Write-Host "  +===========================================================+"
    Write-Host "         JARBAS ENTERPRISE CLI  --  VER 1.0.0"
    Write-Host "         BUILD/DEPLOY/MANAGE :: JBOSS/WILDFLY SUBSYSTEM"
    Write-Host "  +-----------------------------------------------------------+"
    Write-Host ""
}

# ==============================
# RETRO TYPEWRITER OUTPUT
# ==============================

function Write-Retro {
    param(
        [string]$Message,
        [int]$DelayMs = 0
    )
    Write-Host $Message -ForegroundColor Green
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Write-RetroWarn {
    param([string]$Message)
    Write-Host "  *** WARNING *** $Message" -ForegroundColor Yellow
}

function Write-RetroError {
    param([string]$Message)
    Write-Host "  !!! ERROR !!! $Message" -ForegroundColor Red
}

function Write-RetroOK {
    param([string]$Message)
    Write-Host "  [ OK ] $Message" -ForegroundColor Green
}

# ==============================
# RETRO SPINNER / PROGRESS
# ==============================

$script:SpinnerIdx = 0
$script:SpinnerFrames = @('-', '\', '|', '/')

function Write-Spinner {
    param([string]$Label)
    $frame = $script:SpinnerFrames[$script:SpinnerIdx % 4]
    $script:SpinnerIdx++
    Write-Host "`r  [$frame] $Label..." -NoNewline -ForegroundColor Green
}

function Write-TickerBar {
    param([int]$Elapsed, [int]$Total, [string]$Label)
    $pct = [math]::Min([int](($Elapsed / $Total) * 20), 20)
    $filled = "#" * $pct
    $empty = "." * (20 - $pct)
    $line = "  [$filled$empty]  $Elapsed / $Total SEC  $Label"
    Write-Host "`r$line" -NoNewline -ForegroundColor Green
}

# ==============================
# HELP FUNCTIONS
# ==============================

function Get-Command-Description($cmd) {
    if ($CommandHelp.ContainsKey($cmd)) {
        return $CommandHelp[$cmd].Description
    }
    return ""
}

function Show-Help {
    Show-Banner

    Write-Host "  SYNTAX:" -ForegroundColor Yellow
    Write-Host "    jarbas.ps1 <COMMAND> [OPTIONS]"
    Write-Host ""
    Write-Host "  COMMANDS:" -ForegroundColor Yellow
    foreach ($cmd in $CommandHelp.Keys) {
        "    {0,-16} {1}" -f $cmd, $CommandHelp[$cmd].Description
    }
    Write-Host ""
    Write-Host "  OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -SkipTest       Bypass Maven test phase"
    Write-Host "    -DryRun         Print actions, do not execute"
    Write-Host "    -VerboseLog     Enable debug-level log output"
    Write-Host "    -Help           Display this screen"
    Write-Host ""
    Write-Host "  EXAMPLE:" -ForegroundColor Yellow
    Write-Host "    jarbas.ps1 help start"
    Write-Host ""
    Write-Host "  +-----------------------------------------------------------+"
    Write-Host ""
}

function Show-CommandHelp {
    param([string]$CmdName)

    if (-not $CommandHelp.ContainsKey($CmdName)) {
        Write-RetroError "UNKNOWN COMMAND: $CmdName"
        return
    }

    Show-Banner

    $cmd = $CommandHelp[$CmdName]

    Write-Host "  COMMAND  : $CmdName" -ForegroundColor Yellow
    Write-Host "  DESC     : $($cmd.Description)"
    Write-Host "  SYNTAX   : $($cmd.Usage)"
    Write-Host "  DETAILS  : $($cmd.Details)"
    Write-Host ""
    Write-Host "  +-----------------------------------------------------------+"
    Write-Host ""
}

# If no command → help and exit
if (-not $Command -or $Help) {
    Show-Help
    exit 0
}

if ($Command -eq "help") {
    if ($args.Count -ge 1 -and $CommandHelp.ContainsKey($args[0])) {
        Show-CommandHelp -CmdName $args[0]
    }
    else {
        Show-Help
    }
    exit 0
}


# ==============================
# PATHS
# ==============================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "jarbas.config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-RetroError "CONFIG FILE NOT FOUND: $ConfigFile"
    exit 1
}

$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$LogFile = $cfg.log.file
$PidFile = Join-Path $ScriptDir "jarbas.pid"

# ==============================
# LOG SYSTEM
# ==============================

function Write-Log {
    param([string]$Level, [string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    if ($VerboseLog -or $Level -ne "DEBUG") {
        switch ($Level) {
            "ERROR" { Write-RetroError $Message }
            "WARN" { Write-RetroWarn  $Message }
            default { Write-Retro      "  >> $Message" }
        }
    }

    Add-Content -Path $LogFile -Value $line
}

function Show-InputError {
    param([string]$Message)
    Write-RetroError $Message
    Write-Host ""
    Show-Help
}

function Die {
    param([string]$Message)
    Write-Log "ERROR" $Message
    exit 1
}

# ==============================
# NETWORK: TEST TCP PORT
# ==============================

function Test-Port {
    param(
        [string]$HostName,
        [int]$Port
    )

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($HostName, $Port)
        $tcp.Close()
        return $true
    }
    catch {
        return $false
    }
}

# ==============================
# DEPLOY  (Maven Wrapper + JBoss copy)
# ==============================

function Deploy {

    Write-Log "INFO" "DEPLOY SEQUENCE INITIATED"
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | PHASE 1 :: ENVIRONMENT SETUP                              |"
    Write-Retro "  +-----------------------------------------------------------+"

    $env:JAVA_HOME = $cfg.java.home
    $env:Path = "$($cfg.java.bin_dir);$env:Path"

    $mvnw = $cfg.maven.wrapper
    if (-not (Test-Path $mvnw)) {
        Die "MAVEN WRAPPER NOT FOUND: $mvnw"
    }

    $projRoot = $cfg.project.root_dir
    $targetDir = $cfg.project.target_dir
    if (-not (Test-Path $projRoot)) {
        Die "PROJECT ROOT NOT FOUND: $projRoot"
    }

    $deployDir = $cfg.jboss.deployments_dir
    if (-not (Test-Path $deployDir)) {
        Die "DEPLOYMENTS DIR NOT FOUND: $deployDir"
    }

    $artifactName = $cfg.project.artifact_name
    $artifactVersion = $cfg.project.artifact_version
    $packaging = $cfg.project.packaging
    if (-not $packaging) { $packaging = "war" }

    $patternWithVersion = "$artifactName*$artifactVersion*.$packaging"
    $patternNoVersion = "$artifactName*.$packaging"

    $mvnArgs = "clean package"
    if ($SkipTest) {
        $mvnArgs += " -DskipTests"
        Write-Log "INFO" "TESTS DISABLED (-DskipTests)"
    }

    if ($DryRun) {
        Write-Retro ""
        Write-Retro "  *** DRY RUN MODE -- NO CHANGES WILL BE MADE ***"
        Write-Retro "  CMD  : $mvnw $mvnArgs"
        Write-Retro "  SCAN : $targetDir"
        Write-Retro "  DEST : $deployDir"
        Write-Log "INFO" "DRY RUN -- DEPLOY NOT EXECUTED"
        return
    }

    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | PHASE 2 :: MAVEN BUILD                                    |"
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Log "INFO" "EXECUTING: $mvnw $mvnArgs"

    $buildLog = Join-Path $ScriptDir "maven-build.log"
    if (Test-Path $buildLog) { Remove-Item $buildLog -Force -ErrorAction SilentlyContinue }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $mvnw
    $psi.Arguments = $mvnArgs
    $psi.WorkingDirectory = $projRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()

    $lines = 0

    while (-not $proc.HasExited) {
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            Add-Content -Path $buildLog -Value $line
            $lines++
        }
        Write-Spinner "BUILD IN PROGRESS  LINES $lines"
        Start-Sleep -Milliseconds 200
    }

    Write-Host ""   # end spinner line

    while (-not $proc.StandardOutput.EndOfStream) {
        Add-Content -Path $buildLog -Value $proc.StandardOutput.ReadLine()
    }
    while (-not $proc.StandardError.EndOfStream) {
        Add-Content -Path $buildLog -Value $proc.StandardError.ReadLine()
    }

    if ($proc.ExitCode -ne 0) {
        Write-Log "ERROR" "MAVEN BUILD FAILED  EXIT CODE=$($proc.ExitCode)"
        Write-RetroError "BUILD FAILED -- SEE LOG: $buildLog"
        return
    }

    Write-Log "INFO" "MAVEN BUILD COMPLETE"
    Write-RetroOK "BUILD SUCCESSFUL"

    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | PHASE 3 :: ARTIFACT LOCATION                              |"
    Write-Retro "  +-----------------------------------------------------------+"

    $artifact = Get-ChildItem -Path $targetDir -Filter $patternWithVersion -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $artifact) {
        $artifact = Get-ChildItem -Path $targetDir -Filter $patternNoVersion -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if (-not $artifact) {
        Die "NO ARTIFACT FOUND IN $targetDir  PATTERN: $patternNoVersion"
    }

    Write-Log "INFO" "ARTIFACT LOCATED: $($artifact.FullName)"

    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | PHASE 4 :: COPY TO DEPLOYMENTS DIR                        |"
    Write-Retro "  +-----------------------------------------------------------+"

    $destFile = Join-Path $deployDir $artifact.Name
    Write-Log "INFO" "COPY TO: $destFile"

    try {
        Copy-Item -Path $artifact.FullName -Destination $destFile -Force
    }
    catch {
        Die "COPY FAILED: $($_.Exception.Message)"
    }

    $doDeploy = "$destFile.dodeploy"
    try {
        @(
            "$destFile.dodeploy", "$destFile.deployed", "$destFile.failed",
            "$destFile.isdeploying", "$destFile.isundeploying", "$destFile.undeployed"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }

        New-Item -Path $doDeploy -ItemType File -Force | Out-Null
        Write-Log "INFO" "MARKER CREATED: $doDeploy"
    }
    catch {
        Die "MARKER CREATION FAILED: $($_.Exception.Message)"
    }

    Write-RetroOK "DEPLOY SUBMITTED -- AWAITING .DODEPLOY PROCESSING"
    Write-Log "INFO" "DEPLOY SEQUENCE COMPLETE"
    Write-Retro "  +-----------------------------------------------------------+"
}

# ==============================
# START JBoss
# ==============================

function Start-JBoss {

    Write-Log "INFO" "JBOSS STARTUP SEQUENCE"
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | INITIATING SERVER BOOT                                    |"
    Write-Retro "  +-----------------------------------------------------------+"

    $scriptPath = Join-Path $cfg.jboss.bin_dir $cfg.jboss.startup_script

    if ($DryRun) {
        Write-Retro "  *** DRY RUN -- CMD: $scriptPath -c $($cfg.jboss.config)"
        return
    }

    $env:JAVA_HOME = $cfg.java.home
    $env:Path = "$($cfg.java.bin_dir);$env:Path"

    Write-Log "INFO" "JAVA_HOME=$env:JAVA_HOME"
    Write-Log "INFO" "LAUNCHING: $scriptPath"

    $process = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c `"$scriptPath -c $($cfg.jboss.config)`"" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden `
        -PassThru

    $process.Id | Out-File $PidFile -Force

    Write-Log "DEBUG" "SCRIPT   : $scriptPath"
    Write-Log "DEBUG" "CONFIG   : $($cfg.jboss.config)"
    Write-Log "DEBUG" "BIN DIR  : $($cfg.jboss.bin_dir)"

    $timeout = $cfg.jboss.startup_timeout
    $elapsed = 0

    Write-Retro "  WAITING FOR MANAGEMENT PORT $($cfg.jboss.host):$($cfg.jboss.port) ..."
    Write-Retro ""

    while ($elapsed -lt $timeout) {
        Write-TickerBar -Elapsed $elapsed -Total $timeout -Label "BOOT"

        $online = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if ($online) {
            Write-Host ""
            Write-Log "INFO" "JBOSS IS ONLINE"
            Write-RetroOK "SERVER ONLINE  PID=$($process.Id)"
            Write-Retro "  +-----------------------------------------------------------+"
            return
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Host ""
    Die "STARTUP TIMEOUT EXCEEDED AFTER $timeout SECONDS"
}

# ==============================
# STOP JBoss
# ==============================

function Stop-JBoss {

    Write-Log "INFO" "JBOSS SHUTDOWN SEQUENCE"
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | ISSUING SHUTDOWN COMMAND                                  |"
    Write-Retro "  +-----------------------------------------------------------+"

    $cliPath = Join-Path $cfg.jboss.bin_dir "jboss-cli.bat"
    $controller = "$($cfg.jboss.host):$($cfg.jboss.port)"

    Start-Process `
        -FilePath $cliPath `
        -ArgumentList "--connect --controller=$controller --command=:shutdown" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden

    $timeout = 30
    $elapsed = 0

    Write-Retro "  WAITING FOR PORT CLOSURE..."
    Write-Retro ""

    while ($elapsed -lt $timeout) {
        Write-TickerBar -Elapsed $elapsed -Total $timeout -Label "SHUTDOWN"

        $online = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if (-not $online) {
            Write-Host ""
            Write-Log "INFO" "JBOSS FULLY STOPPED"
            Write-RetroOK "SERVER OFFLINE"
            Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
            Write-Retro "  +-----------------------------------------------------------+"
            return
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Host ""
    Write-Log "WARN" "SHUTDOWN TIMEOUT EXCEEDED"
    Write-RetroWarn "STOP TIMEOUT -- PROCESS MAY STILL BE RUNNING"
    Write-Retro "  +-----------------------------------------------------------+"
}

# ==============================
# RESTART JBoss
# ==============================

function Restart-JBoss {
    Write-Log "INFO" "RESTART SEQUENCE"
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | RESTART :: STOP THEN START                                |"
    Write-Retro "  +-----------------------------------------------------------+"
    Stop-JBoss
    Start-JBoss
}

# ==============================
# START-DEPLOY (combo)
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
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | REMOVE ARTIFACT FROM DEPLOYMENTS                          |"
    Write-Retro "  +-----------------------------------------------------------+"

    $deployDir = $cfg.jboss.deployments_dir
    $name = $cfg.project.artifact_name
    $packaging = if ($cfg.project.packaging) { $cfg.project.packaging } else { "war" }

    if (-not (Test-Path $deployDir)) {
        Die "DEPLOYMENTS DIR NOT FOUND: $deployDir"
    }

    $pattern = "$name*.$packaging"
    $artifact = Get-ChildItem -Path $deployDir -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $artifact) {
        Die "NO ARTIFACT MATCHING '$pattern' IN '$deployDir'"
    }

    Write-Log "INFO" "REMOVING: $($artifact.FullName)"

    try {
        @(
            "$($artifact.FullName).dodeploy", "$($artifact.FullName).deployed", "$($artifact.FullName).failed",
            "$($artifact.FullName).isdeploying", "$($artifact.FullName).isundeploying", "$($artifact.FullName).undeployed"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }

        Remove-Item $artifact.FullName -Force -ErrorAction Stop

        Write-Log "INFO" "ARTIFACT REMOVED"
        Write-RetroOK "ARTIFACT REMOVED SUCCESSFULLY"
    }
    catch {
        Die "REMOVE FAILED: $($_.Exception.Message)"
    }

    Write-Retro "  +-----------------------------------------------------------+"
}

# ==============================
# UNDEPLOY
# ==============================

function Undeploy-Artifact {
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | UNDEPLOY SEQUENCE                                         |"
    Write-Retro "  +-----------------------------------------------------------+"

    $cliPath = Join-Path $cfg.jboss.bin_dir "jboss-cli.bat"
    $controller = "$($cfg.jboss.host):$($cfg.jboss.port)"
    $deployDir = $cfg.jboss.deployments_dir
    $artifact = $cfg.project.artifact_name
    $packaging = if ($cfg.project.packaging) { $cfg.project.packaging } else { "ear" }
    $argumentList = "--connect --controller=$controller --command=""undeploy $artifact.$packaging """

    Start-Process `
        -FilePath $cliPath `
        -ArgumentList $argumentList `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden `
        -PassThru

    if (-not $artifact.EndsWith(".$packaging")) {
        $artifact = "$artifact.$packaging"
    }

    $basePath = Join-Path $deployDir $artifact
    $timeout = 60
    $elapsed = 0

    Write-Retro "  AWAITING UNDEPLOY CONFIRMATION..."
    Write-Retro ""

    while ($elapsed -lt $timeout) {
        Write-TickerBar -Elapsed $elapsed -Total $timeout -Label "UNDEPLOY"

        $fileGone = (Test-Path $basePath)
        $isDeploying = (Test-Path "$($basePath).isdeploying")
        $isUndeploying = (Test-Path "$($basePath).isundeploying")
        $deployed = (Test-Path "$($basePath).deployed")
        $failed = (Test-Path "$($basePath).failed")
        $doDeploy = (Test-Path "$($basePath).dodeploy")
        $undeployedMark = (Test-Path "$($basePath).undeployed")

        $noActiveMarkers = -not ($isDeploying -or $isUndeploying -or $deployed -or $doDeploy -or $failed)

        if ($fileGone -and ($undeployedMark -or $noActiveMarkers)) {
            Write-Host ""
            Write-Log "INFO" "UNDEPLOY CONFIRMED: $artifact"
            Write-RetroOK "UNDEPLOY COMPLETE"
            break
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Host ""

    if ($elapsed -ge $timeout) {
        Write-Log "WARN" "UNDEPLOY TIMEOUT: $artifact"
        Write-RetroWarn "TIMEOUT WAITING FOR UNDEPLOY CONFIRMATION"
    }

    Write-Retro "  +-----------------------------------------------------------+"
}

# ==============================
# STATUS
# ==============================

function Get-JBossStatus {
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro "  | SERVER STATUS REPORT                                      |"
    Write-Retro "  +-----------------------------------------------------------+"
    Write-Retro ""

    "  {0,-16} {1,-10} {2,-10} {3,-8}" -f "PROCESS", "STATUS", "PID", "PORT"
    Write-Retro "  ------------------------------------------------"

    if (Test-Path $PidFile) {
        $jbossPid = Get-Content $PidFile
        $online = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if ($online) {
            "  {0,-16} {1,-10} {2,-10} {3,-8}" -f "JBOSS", "ONLINE", $jbossPid, $cfg.jboss.port
            Write-Retro ""
            Write-RetroOK "SERVER IS RESPONDING ON MANAGEMENT PORT"
            Write-Retro "  +-----------------------------------------------------------+"
            return
        }
    }

    "  {0,-16} {1,-10} {2,-10} {3,-8}" -f "JBOSS", "OFFLINE", "-", "-"
    Write-Retro ""
    Write-RetroWarn "SERVER IS NOT RESPONDING"
    Write-Retro "  +-----------------------------------------------------------+"
}

# ==============================
# COMMAND LINE ECHO
# ==============================

function Get-EffectiveCommandLine {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($scriptPath)

    if ($Command) { $parts.Add($Command) }
    if ($SkipTest) { $parts.Add('-SkipTest') }
    if ($DryRun) { $parts.Add('-DryRun') }
    if ($VerboseLog) { $parts.Add('-VerboseLog') }
    if ($Help) { $parts.Add('-Help') }

    return ($parts -join ' ')
}

function Clear-And-ShowLastCommand {
    param(
        [ConsoleColor]$Color = 'DarkGreen'
    )
    $cmdLine = Get-EffectiveCommandLine
    Clear-Host
    $Host.UI.RawUI.ForegroundColor = 'Green'
    Write-Host ""
    Write-Host "  >> $cmdLine" -ForegroundColor $Color
    Write-Host ""
    Show-Banner
}

# ==============================
# ROUTER
# ==============================

switch ($Command) {
    "start" { Clear-And-ShowLastCommand; Start-JBoss }
    "stop" { Clear-And-ShowLastCommand; Stop-JBoss }
    "restart" { Clear-And-ShowLastCommand; Restart-JBoss }
    "remove" { Clear-And-ShowLastCommand; Remove-Artifact }
    "status" { Clear-And-ShowLastCommand; Get-JBossStatus }
    "deploy" { Clear-And-ShowLastCommand; Deploy }
    "undeploy" { Clear-And-ShowLastCommand; Undeploy-Artifact }
    "start-deploy" { Clear-And-ShowLastCommand; Deploy; Start-JBoss }
    default {
        Clear-And-ShowLastCommand
        Write-RetroError "UNRECOGNIZED COMMAND: $Command"
        Write-Host ""
        Show-Help
        exit 1
    }
}