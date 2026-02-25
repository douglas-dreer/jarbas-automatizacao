[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "deploy", "start-deploy", "status", "help")]
    [string]$Command,

    [switch]$SkipTest,
    [switch]$VerboseLog,
    [switch]$DryRun,
    [switch]$Help
)

# UTF8 FIX
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==============================
# HELP METADATA
# ==============================

$CommandHelp = @{
    start          = @{
        Description = "Starts the JBoss server."
        Usage       = "jarbas.ps1 start"
        Details     = "Initializes environment and waits until management port becomes available."
    }
    stop           = @{
        Description = "Stops the JBoss server."
        Usage       = "jarbas.ps1 stop"
        Details     = "Uses jboss-cli shutdown and waits until port closes."
    }
    restart        = @{
        Description = "Performs graceful reload."
        Usage       = "jarbas.ps1 restart"
        Details     = "Uses :reload via CLI and monitors restart cycle."
    }
    deploy         = @{
        Description = "Builds and deploys artifact."
        Usage       = "jarbas.ps1 deploy [-SkipTest]"
        Details     = "Runs Maven clean package and copies artifact to deployments."
    }
    "start-deploy" = @{
        Description = "Deploys and then starts server."
        Usage       = "jarbas.ps1 start-deploy"
        Details     = "Combines deploy and start workflow."
    }
    status         = @{
        Description = "Displays current server status."
        Usage       = "jarbas.ps1 status"
        Details     = "Shows PID, uptime and port."
    }
}

# ==============================
# BANNER
# ==============================

function Show-Banner {
    # Configura o console
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    
    # Salva a cor atual
    $originalColor = $Host.UI.RawUI.ForegroundColor
    
    # Muda para Cyan
    $Host.UI.RawUI.ForegroundColor = 'Cyan'
    
    # Banner como here-string mas com encoding explícito
    $banner = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes(@"
     ██╗ █████╗ ██████╗ ██████╗  █████╗ ███████╗
     ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝
     ██║███████║██████╔╝██████╔╝███████║███████╗
██   ██║██╔══██║██╔══██╗██╔══██╗██╔══██║╚════██║
╚█████╔╝██║  ██║██║  ██║██████╔╝██║  ██║███████║
 ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝
"@))
    
    Write-Host $banner
    
    # Restaura a cor
    $Host.UI.RawUI.ForegroundColor = $originalColor
    
    Write-Host ""
    Write-Host "              Jarbas Enterprise CLI v1.0.0" -ForegroundColor DarkGray
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
    Write-Host "  -DryRun         Show actions without executing"
    Write-Host "  -VerboseLog     Enable verbose logging"
    Write-Host "  -Help           Show help"
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

# Se não passar comando → mostra help
if (-not $Command -or $Help) {
    Show-Help
    exit 0
}

if ($Command -eq "help") {
    Show-Help
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

    if ($VerboseLog -or $Level -ne "DEBUG") {
        Write-Host $line
    }

    Add-Content -Path $LogFile -Value $line
}

function Die {
    param([string]$Message)
    Write-Log "ERROR" $Message
    exit 1
}

# ==============================
# TEST PORT
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
# START
# ==============================

function Start-JBoss {

    Write-Log "INFO" "Starting JBoss"

    $scriptPath = Join-Path $cfg.jboss.bin_dir $cfg.jboss.startup_script

    if ($DryRun) {
        Write-Host "DRY RUN: $scriptPath"
        return
    }

    $env:JAVA_HOME = $cfg.java.home
    $env:Path = "$($cfg.java.bin_dir);$env:Path"

    $process = Start-Process `
        -FilePath "cmd.exe" `
        -ArgumentList "/c `"$scriptPath -c $($cfg.jboss.config)`"" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden `
        -PassThru

    $process.Id | Out-File $PidFile -Force

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
# STOP
# ==============================

function Stop-JBoss {

    Write-Log "INFO" "Stopping JBoss"

    $cliPath = Join-Path $cfg.jboss.bin_dir "jboss-cli.bat"
    $controller = "$($cfg.jboss.host):$($cfg.jboss.port)"

    Start-Process `
        -FilePath $cliPath `
        -ArgumentList "--connect --controller=$controller --command=:shutdown" `
        -WorkingDirectory $cfg.jboss.bin_dir `
        -WindowStyle Hidden

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
# RESTART
# ==============================

function Restart-JBoss {
    Write-Log "INFO" "Restarting JBoss"
    Stop-JBoss
    Start-JBoss
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
            "{0,-10} {1,-8} {2,-8} {3,-6}" -f "JBoss", "ONLINE", $jbossPid, $cfg.jboss.port
            return
        }
    }

    "{0,-10} {1,-8} {2,-8} {3,-6}" -f "JBoss", "OFFLINE", "-", "-"
}

# ==============================
# ROUTER
# ==============================

switch ($Command) {
    "start" { Start-JBoss }
    "stop" { Stop-JBoss }
    "restart" { Restart-JBoss }
    "status" { Get-JBossStatus }
    "deploy" { Write-Host "Deploy logic here" }
    "start-deploy" { Write-Host "Start-Deploy logic here" }
}