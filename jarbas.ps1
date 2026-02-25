# ==============================
# PARAMS
# ==============================

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



# Ensure UTF-8 output for banner and logs
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==============================
# HELP METADATA
# ==============================

$CommandHelp = @{
    start          = @{
        Description = "Starts the JBoss server."
        Usage       = "jarbas.ps1 start"
        Details     = "Initializes the environment and waits until the management port becomes available."
    }
    stop           = @{
        Description = "Stops the JBoss server."
        Usage       = "jarbas.ps1 stop"
        Details     = "Uses jboss-cli shutdown and waits until the management port is closed."
    }
    restart        = @{
        Description = "Performs a graceful reload."
        Usage       = "jarbas.ps1 restart"
        Details     = "Uses :reload via JBoss CLI and monitors the restart cycle."
    }
    deploy         = @{
        Description = "Builds with Maven Wrapper and deploys to JBoss."
        Usage       = "jarbas.ps1 deploy [-SkipTest] [-DryRun]"
        Details     = "Runs mvnw.cmd clean package; copies the built artifact to the JBoss deployments directory and creates a .dodeploy marker."
    }
    undeploy       = @{
        Description = "Undeploy artifact on jBoss."
        Usage       = "jarbas.ps1 undeploy "
        Details     = "Using o jboss-client undeploy artifact"
    }
    remove         = @{
        Description = "Removes the deployed artifact from JBoss deployments."
        Usage       = "jarbas.ps1 remove"
        Details     = "Deletes the artifact from the JBoss deployments directory and clears deployment markers."
    }
    "start-deploy" = @{
        Description = "Builds/deploys the artifact and then starts the server."
        Usage       = "jarbas.ps1 start-deploy [-SkipTest] [-DryRun]"
        Details     = "Combines the deploy workflow followed by the startup workflow."
    }
    status         = @{
        Description = "Displays the current server status."
        Usage       = "jarbas.ps1 status"
        Details     = "Shows PID, status, and port availability."
    }
}

# ==============================
# BANNER
# ==============================

function Show-Banner {
    # Save and temporarily change console color
    $originalColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = 'Cyan'

    $banner = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes(@"

     ██╗ █████╗ ██████╗ ██████╗  █████╗ ███████╗
     ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝
     ██║███████║██████╔╝██████╔╝███████║███████╗
██   ██║██╔══██║██╔══██╗██╔══██╗██╔══██║╚════██║
╚█████╔╝██║  ██║██║  ██║██████╔╝██║  ██║███████║
 ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝
 
"@))

    Write-Host $banner

    # Restore color
    $Host.UI.RawUI.ForegroundColor = $originalColor

    Write-Host ""
    Write-Host "              Jarbas Enterprise CLI v1.5.0" -ForegroundColor DarkGray
    Write-Host ""
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

    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  jarbas.ps1 <command> [options]"
    Write-Host ""

    Write-Host "AVAILABLE COMMANDS:" -ForegroundColor Yellow
    foreach ($cmd in $CommandHelp.Keys) {
        "{0,-15} {1}" -f ("  " + $cmd), $CommandHelp[$cmd].Description
    }

    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  -SkipTest       Skip Maven tests during build"
    Write-Host "  -DryRun         Show actions without executing them"
    Write-Host "  -VerboseLog     Enable verbose logging"
    Write-Host "  -Help           Show this help"
    Write-Host ""

    Write-Host "TIP:" -ForegroundColor Yellow
    Write-Host "  jarbas.ps1 help start"
    Write-Host ""
}

function Show-CommandHelp {
    param([string]$CmdName)

    if (-not $CommandHelp.ContainsKey($CmdName)) {
        Write-Host "Unknown command: $CmdName" -ForegroundColor Red
        return
    }

    Show-Banner

    $cmd = $CommandHelp[$CmdName]

    Write-Host "COMMAND:" -ForegroundColor Yellow
    Write-Host "  $CmdName"
    Write-Host ""

    Write-Host "DESCRIPTION:" -ForegroundColor Yellow
    Write-Host "  $($cmd.Description)"
    Write-Host ""

    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  $($cmd.Usage)"
    Write-Host ""

    Write-Host "DETAILS:" -ForegroundColor Yellow
    Write-Host "  $($cmd.Details)"
    Write-Host ""
}

# If no command is provided → show help and exit
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
    Write-Host "Config file not found: $ConfigFile"
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

    # Show all except DEBUG unless -VerboseLog is on
    if ($VerboseLog -or $Level -ne "DEBUG") {
        Write-Host $line
    }

    Add-Content -Path $LogFile -Value $line
}

function Show-InputError {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
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
# DEPLOY (Maven Wrapper + Deploy to JBoss)
# ==============================

function Deploy {

    Write-Log "INFO" "Starting deploy process..."

    # Enforce Java from config (affects mvnw.cmd)
    $env:JAVA_HOME = $cfg.java.home
    $env:Path = "$($cfg.java.bin_dir);$env:Path"

    # Validate config
    $mvnw = $cfg.maven.wrapper
    if (-not (Test-Path $mvnw)) {
        Die "Maven Wrapper not found: $mvnw"
    }

    $projRoot = $cfg.project.root_dir
    $targetDir = $cfg.project.target_dir
    if (-not (Test-Path $projRoot)) {
        Die "Project root not found: $projRoot"
    }

    $deployDir = $cfg.jboss.deployments_dir  # fixed: consistent casing 'jboss'
    if (-not (Test-Path $deployDir)) {
        Die "JBoss deployments directory does not exist: $deployDir"
    }

    $artifactName = $cfg.project.artifact_name
    $artifactVersion = $cfg.project.artifact_version
    $packaging = $cfg.project.packaging
    if (-not $packaging) { $packaging = "war" }  # default

    # Artifact patterns (with and without version)
    $patternWithVersion = "$artifactName*$artifactVersion*.$packaging"
    $patternNoVersion = "$artifactName*.$packaging"

    # Build arguments
    $mvnArgs = "clean package"
    if ($SkipTest) {
        $mvnArgs += " -DskipTests"
        Write-Log "INFO" "SkipTest enabled"
    }

    # Dry run mode: show intent and stop
    if ($DryRun) {
        Write-Host "DRY RUN: $mvnw $mvnArgs (wd: $projRoot)"
        Write-Host "DRY RUN: Will search artifact in: $targetDir\($patternWithVersion | $patternNoVersion)"
        Write-Host "DRY RUN: Will copy to: $deployDir and create .dodeploy"
        Write-Log "INFO" "DryRun - Deploy not executed"
        return
    }

    # Build log file capturing Maven stdout/stderr
    $buildLog = Join-Path $ScriptDir "maven-build.log"
    if (Test-Path $buildLog) { Remove-Item $buildLog -Force -ErrorAction SilentlyContinue }

    Write-Log "INFO" "Executing Maven Wrapper: $mvnw $mvnArgs"
    Write-Host "Starting build... this may take a few moments."

    # Start Maven process with output redirection and a simple progress bar
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
            if ($lines % 30 -eq 0) {
                Write-Progress -Activity "Project build" -Status "$lines lines processed" -PercentComplete 0
            }
        }
        Start-Sleep -Milliseconds 60
    }

    # Flush remaining stdout/stderr
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        Add-Content -Path $buildLog -Value $line
    }
    while (-not $proc.StandardError.EndOfStream) {
        $line = $proc.StandardError.ReadLine()
        Add-Content -Path $buildLog -Value $line
    }

    if ($proc.ExitCode -ne 0) {
        Write-Log "ERROR" "Maven build failed (ExitCode=$($proc.ExitCode)). Check: $buildLog"
        Write-Host "❌ Build failed. See: $buildLog" -ForegroundColor Red
        return
    }

    Write-Log "INFO" "Maven build finished successfully"
    Write-Host "✔ Build completed" -ForegroundColor Green

    # Locate the artifact (try with version, then fallback)
    $artifact = Get-ChildItem -Path $targetDir -Filter $patternWithVersion -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $artifact) {
        $artifact = Get-ChildItem -Path $targetDir -Filter $patternNoVersion -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if (-not $artifact) {
        Die "No .$packaging artifact found in '$targetDir' (patterns: '$patternWithVersion' / '$patternNoVersion')."
    }

    Write-Log "INFO" "Artifact found: $($artifact.FullName)"

    # Copy artifact to JBoss deployments
    $destFile = Join-Path $deployDir $artifact.Name
    Write-Log "INFO" "Copying artifact to deployments: $destFile"

    try {
        Copy-Item -Path $artifact.FullName -Destination $destFile -Force
    }
    catch {
        Die "Failed to copy artifact to '$deployDir': $($_.Exception.Message)"
    }

    # Create .dodeploy marker to force deployment
    $doDeploy = "$destFile.dodeploy"
    try {
        # Clean previous markers for the same artifact name if any exist
        @(
            "$destFile.dodeploy", "$destFile.deployed", "$destFile.failed",
            "$destFile.isdeploying", "$destFile.isundeploying", "$destFile.undeployed"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }

        New-Item -Path $doDeploy -ItemType File -Force | Out-Null
        Write-Log "INFO" "Created deployment marker: $doDeploy"
    }
    catch {
        Die "Failed to create .dodeploy marker: $($_.Exception.Message)"
    }

    Write-Host "✔ Deploy submitted to JBoss (wait for .dodeploy processing)" -ForegroundColor Green
    Write-Log "INFO" "Deploy finished successfully"
}

# ==============================
# START JBoss
# ==============================

function Start-JBoss {

    Write-Log "INFO" "Starting JBoss"

    $scriptPath = Join-Path $cfg.jboss.bin_dir $cfg.jboss.startup_script

    if ($DryRun) {
        Write-Host "DRY RUN: $scriptPath -c $($cfg.jboss.config)"
        return
    }

    # Set Java for the JBoss process
    $env:JAVA_HOME = $cfg.java.home
    $env:Path = "$($cfg.java.bin_dir);$env:Path"

    Write-Log "INFO" "Using JAVA_HOME = $env:JAVA_HOME"
    Write-Log "INFO" "java.exe = $(Join-Path $cfg.java.bin_dir 'java.exe')"

    # NOTE: You can run standalone.bat directly; using cmd.exe /c works but provides less control
    $process = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c `"$scriptPath -c $($cfg.jboss.config)`"" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden `
        -PassThru


    Write-Log "DEBUG" "Script Path: $scriptPath"
    Write-Log "DEBUG" "Config: $($cfg.jboss.config)"
    Write-Log "DEBUG" "Bin Dir: $($cfg.jboss.bin_dir)"

    # Store PID for later stop/kill
    $process.Id | Out-File $PidFile -Force

    # Wait until management port responds or until timeout
    $timeout = $cfg.jboss.startup_timeout
    $elapsed = 0

    while ($elapsed -lt $timeout) {
        Write-Progress -Activity "Waiting for JBoss..." `
            -Status "$elapsed / $timeout sec" `
            -PercentComplete (($elapsed / $timeout) * 100)

        $online = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if ($online) {
            Write-Log "INFO" "JBoss is ONLINE"
            return
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Die "Startup timeout exceeded"
}

# ==============================
# STOP JBoss
# ==============================

function Stop-JBoss {

    Write-Log "INFO" "Stopping JBoss"

    $cliPath = Join-Path $cfg.jboss.bin_dir "jboss-cli.bat"
    $controller = "$($cfg.jboss.host):$($cfg.jboss.port)"

    # Attempt a graceful shutdown via CLI
    Start-Process `
        -FilePath $cliPath `
        -ArgumentList "--connect --controller=$controller --command=:shutdown" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden

    # Wait until port is closed or until timeout
    $timeout = 30
    $elapsed = 0

    while ($elapsed -lt $timeout) {
        $online = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if (-not $online) {
            Write-Log "INFO" "JBoss fully stopped"
            Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
            return
        }

        Start-Sleep -Seconds 1
        $elapsed++
    }

    Write-Log "WARN" "Stop timeout exceeded"
}

# ==============================
# RESTART JBoss
# ==============================

function Restart-JBoss {
    Write-Log "INFO" "Restarting JBoss"
    Stop-JBoss
    Start-JBoss
}

# ==============================
# START & DEPLOY (combo)
# ==============================

function Start-And-Deploy-Project {
    # Clear screen and show the effective command line for context
    Clear-And-ShowLastCommand
    Deploy
    Start-JBoss
}

# ==============================
# REMOVE Artifact from JBoss deployments
# ==============================

function Remove-Artifact {
    # Removes the deployed artifact file based on project settings
    $deployDir = $cfg.jboss.deployments_dir
    $name = $cfg.project.artifact_name
    $packaging = if ($cfg.project.packaging) { $cfg.project.packaging } else { "war" }

    if (-not (Test-Path $deployDir)) {
        Die "JBoss deployments directory not found: $deployDir"
    }

    $pattern = "$name*.$packaging"
    $artifact = Get-ChildItem -Path $deployDir -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $artifact) {
        Die "No artifact matching '$pattern' found under '$deployDir'"
    }

    Write-Log "INFO" "Removing artifact: $($artifact.FullName)"

    try {
        # Remove deployment markers first, then the artifact
        @(
            "$($artifact.FullName).dodeploy", "$($artifact.FullName).deployed", "$($artifact.FullName).failed",
            "$($artifact.FullName).isdeploying", "$($artifact.FullName).isundeploying", "$($artifact.FullName).undeployed"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }

        Remove-Item $artifact.FullName -Force -ErrorAction Stop
        
        Write-Log "INFO" "Artifact removed successfully"
        Write-Host "✔ Artifact removed" -ForegroundColor Green
    }
    catch {
        Die "Failed to remove artifact: $($_.Exception.Message)"
    }
}

# =============================
# UNDEPLOYMENT
# =============================
function Unpublish-Artifact {
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

    while ($elapsed -lt $timeout) {

        Write-Log "INFO" "$basePath"
      
        $fileGone = (Test-Path $basePath)
        $isDeploying = (Test-Path "$($basePath).isdeploying")
        $isUndeploying = (Test-Path "$($basePath).isundeploying")
        $deployed = (Test-Path "$($basePath).deployed")
        $failed = (Test-Path "$($basePath).failed")
        $doDeploy = (Test-Path "$($basePath).dodeploy")
        $undeployedMark = (Test-Path "$($basePath).undeployed")

        $noActiveMarkers = -not ($isDeploying -or $isUndeploying -or $deployed -or $doDeploy -or $failed)

        if ($fileGone -and ($undeployedMark -or $noActiveMarkers)) {
            Write-Log "INFO" "Undeploy done: $artifact"
            Write-Host "✔ Undeploy finished" -ForegroundColor Green
            break
        }

        Write-Progress -Activity "Waiting undeploy..." `
            -Status "Tempo decorrido: $elapsed s" `
            -PercentComplete (($elapsed / $timeout) * 100)

        Start-Sleep -Seconds 1
        $elapsed++
    }

    if ($elapsed -ge $timeout) {
        Write-Log "WARN" "Timeout aguardando undeploy do artefato: $artifact"
        Write-Host "⚠ Tempo esgotado aguardando undeploy" -ForegroundColor Yellow
    }
}


# ==============================
# STATUS
# ==============================

function Get-JBossStatus {

    "{0,-10} {1,-8} {2,-8} {3,-6}" -f "NAME", "STATUS", "PID", "PORT"

    if (Test-Path $PidFile) {

        $jbossPid = Get-Content $PidFile
        $online = Test-Port -HostName $cfg.jboss.host -Port $cfg.jboss.port

        if ($online) {
            "{0,-10} {1,-8} {2,-8} {3,-6}" -f "JBoss", "🟢", $jbossPid, $cfg.jboss.port
            return
        }
    }

    "{0,-10} {1,-8} {2,-8} {3,-6}" -f "JBoss", "🔴", "-", "-"
}

# ==============================
# COMMAND LINE ECHO (for clear/visibility)
# ==============================

function Get-EffectiveCommandLine {
    # Reconstructs the effective command line for display purposes
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

    # If additional command-level parameters exist in the future, append them here.

    return ($parts -join ' ')
}

function Clear-And-ShowLastCommand {
    param(
        [ConsoleColor]$Color = 'DarkGray'
    )
    $cmdLine = Get-EffectiveCommandLine
    Clear-Host
    Write-Host $cmdLine -ForegroundColor $Color
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
    "undeploy" { Clear-And-ShowLastCommand; Unpublish-Artifact }
    "start-deploy" { Clear-And-ShowLastCommand; Deploy; Start-JBoss }    
    default {
        Clear-And-ShowLastCommand
        Write-Host "Command or option invalided $Command" -ForegroundColor Red
        Show-Help
        exit 1
    }

}