<#
.SYNOPSIS 
    Pack project into a NuGet package

.DESCRIPTION 
    This script is to pack a project into a NuGet package files (*.nupkg).

.PARAMETER project_path 
     Required. Path to a project.json file or a folder containing project.json files.

.PARAMETER destination_folder 
     Required. Destination folder.

.PARAMETER libraryOrchestratorUrl 
    (Optional, useful only for libraries) The Orchestrator URL.

.PARAMETER libraryOrchestratorTenant 
    (Optional, useful only for libraries) The Orchestrator tenant.

.PARAMETER libraryOrchestratorUsername
    (Optional, useful only for libraries) The Orchestrator username used for authentication. Must be used together with the password.

.PARAMETER libraryOrchestratorPassword
    (Optional, useful only for libraries) The Orchestrator password used for authentication. Must be used together with the username.

.PARAMETER libraryOrchestratorUserKey
    (Optional, useful only for libraries) The Orchestrator OAuth2 refresh token used for authentication. Must be used together with the account name and client id.

.PARAMETER libraryOrchestratorAccountName
    (Optional, useful only for libraries) The Orchestrator CloudRPA account name. Must be used together with the refresh token and client id.

.PARAMETER libraryOrchestratorFolder
    (Optional, useful only for libraries) The Orchestrator folder (organization unit).

.PARAMETER version
    Package version.

.PARAMETER autoVersion
    Auto-generate package version.

.PARAMETER outputType
    Force the output to a specific type. <Process|Library|Tests|Objects>

.PARAMETER language
    The orchestrator language.

.PARAMETER disableTelemetry
    Disable telemetry data.
#>

Param (
    # Required
    [string] $project_path = "", 
    [string] $destination_folder = "", 

    # Optional (libraries)
    [string] $libraryOrchestratorUrl = "", 
    [string] $libraryOrchestratorTenant = "",

    # Cloud (optional)
    [string] $libraryOrchestratorAccountName = "", 
    [string] $libraryOrchestratorUserKey = "", 

    # On prem (optional)
    [string] $libraryOrchestratorUsername = "", 
    [string] $libraryOrchestratorPassword = "", 
	
    [string] $libraryOrchestratorFolder = "", 
    [string] $language = "",  
    [string] $version = "", 
    [switch] $autoVersion, 
    [string] $outputType = "", 
    [string] $disableTelemetry = ""   
)

function WriteLog {
	Param ($message, [switch] $err)
	
	$now = Get-Date -Format "G"
	$line = "$now`t$message"
	$line | Add-Content $debugLog -Encoding UTF8
	if ($err) {
		Write-Host $line -ForegroundColor Red
	} else {
		Write-Host $line
	}
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = "$scriptPath\orchestrator-package-pack.log"

# Verify UiPath CLI existence or download
$uipathCLI = "$scriptPath\uipathcli\lib\net461\uipcli.exe"
if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
    WriteLog "UiPath CLI does not exist in this folder. Attempting to download it..."
    try {
        if (-not (Test-Path -Path "$scriptPath\uipathcli")) {
            New-Item -Path "$scriptPath" -Name "uipathcli" -ItemType Directory | Out-Null
        }
        Invoke-WebRequest -Uri "https://www.myget.org/F/uipath-dev/api/v2/package/UiPath.CLI/1.0.7802.11617" -OutFile "$scriptPath\uipathcli\cli.zip"
        Expand-Archive -LiteralPath "$scriptPath\uipathcli\cli.zip" -DestinationPath "$scriptPath\uipathcli" -Force
        WriteLog "UiPath CLI downloaded and extracted to $scriptPath\uipathcli"
        if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
            WriteLog "Unable to locate uipathcli.exe after download."
            exit 1
        }
    }
    catch {
        WriteLog ("Error Occurred: " + $_.Exception.Message) -err
        exit 1
    }
}

WriteLog "-----------------------------------------------------------------------------"
WriteLog "uipcli location : $uipathCLI"

if ([string]::IsNullOrEmpty($project_path) -or [string]::IsNullOrEmpty($destination_folder)) {
    WriteLog "Error: Required parameters project_path and destination_folder must be provided." -err
    exit 1
}

# Build CLI parameter list
$ParamList = New-Object 'Collections.Generic.List[string]'
$ParamList.Add("package")
$ParamList.Add("pack")
$ParamList.Add($project_path)
$ParamList.Add("-o")
$ParamList.Add($destination_folder)

if ($libraryOrchestratorUrl -ne "") {
    $ParamList.Add("--libraryOrchestratorUrl")
    $ParamList.Add($libraryOrchestratorUrl)
}
if ($libraryOrchestratorTenant -ne "") {
    $ParamList.Add("--libraryOrchestratorTenant")
    $ParamList.Add($libraryOrchestratorTenant)
}
if ($libraryOrchestratorAccountName -ne "") {
    $ParamList.Add("--libraryOrchestratorAccountName")
    $ParamList.Add($libraryOrchestratorAccountName)
}
if ($libraryOrchestratorUserKey -ne "") {
    $ParamList.Add("--libraryOrchestratorAuthToken")
    $ParamList.Add($libraryOrchestratorUserKey)
}
if ($libraryOrchestratorUsername -ne "") {
    $ParamList.Add("--libraryOrchestratorUsername")
    $ParamList.Add($libraryOrchestratorUsername)
}
if ($libraryOrchestratorPassword -ne "") {
    $ParamList.Add("--libraryOrchestratorPassword")
    $ParamList.Add($libraryOrchestratorPassword)
}
if ($libraryOrchestratorFolder -ne "") {
    $ParamList.Add("--libraryOrchestratorFolder")
    $ParamList.Add($libraryOrchestratorFolder)
}
if ($language -ne "") {
    $ParamList.Add("-l")
    $ParamList.Add($language)
}
if ($version -ne "") {
    $ParamList.Add("-v")
    $ParamList.Add($version)
}
if ($autoVersion.IsPresent) {
    $ParamList.Add("--autoVersion")
}
if ($outputType -ne "") {
    $ParamList.Add("--outputType")
    $ParamList.Add($outputType)
}
if ($disableTelemetry -ne "") {
    $ParamList.Add("-y")
    $ParamList.Add($disableTelemetry)
}

# Mask sensitive info before logging 
$ParamMask = @($ParamList)

# Mask password
$secretIndex = $ParamMask.IndexOf("--libraryOrchestratorPassword")
if ($secretIndex -ge 0) {
    $masked = "*" * $libraryOrchestratorPassword.Length
    $ParamMask[$secretIndex + 1] = $masked
}

# Mask Auth Token partially
$secretIndex = $ParamMask.IndexOf("--libraryOrchestratorAuthToken")
if ($secretIndex -ge 0) {
    if ($libraryOrchestratorUserKey.Length -gt 4) {
        $masked = $libraryOrchestratorUserKey.Substring(0,4) + ("*" * ($libraryOrchestratorUserKey.Length - 4))
    } else {
        $masked = "*" * $libraryOrchestratorUserKey.Length
    }
    $ParamMask[$secretIndex + 1] = $masked
}

WriteLog "Executing: $uipathCLI $($ParamMask -join ' ')"

# Execute the CLI command
& "$uipathCLI" $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Done! Package(s) created in: $destination_folder"
    Exit 0
} else {
    WriteLog "Failed to pack project. Exit code: $LASTEXITCODE" -err
    Exit 1
}
