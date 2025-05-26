<#
.SYNOPSIS 
    Test a given package or run a test set

.DESCRIPTION 
    Test a given package or run a test set in orchestrator

.PARAMETER project_path 
     The path to a test package file.

.PARAMETER testset 
     The name of the test set to execute. The test set should use the latest version of the test cases. If the test set does not belong to the default folder (organization unit) it must be prefixed with the folder name, e.g. AccountingTeam\TestSet

.PARAMETER orchestrator_url 
    Required. The URL of the Orchestrator instance.

.PARAMETER orchestrator_tenant 
    Required. The tenant of the Orchestrator instance.

.PARAMETER result_path 
    Results file path

.PARAMETER orchestrator_user
    Required. The Orchestrator username used for authentication. Must be used together with the password.

.PARAMETER orchestrator_pass
    Required. The Orchestrator password used for authentication. Must be used together with the username

.PARAMETER UserKey
    Required. The Orchestrator OAuth2 refresh token used for authentication. Must be used together with the account name and client id.

.PARAMETER account_name
    Required. The Orchestrator CloudRPA account name. Must be used together with the refresh token and client id.

.PARAMETER folder_organization_unit
    The Orchestrator folder (organization unit).

.PARAMETER environment
    The environment to deploy the package to. Must be used together with the project path. Required when not using a modern folder.

.PARAMETER timeout
    The time in seconds for waiting to finish test set executions. (default 7200) 

.PARAMETER out
    Type of result file

.PARAMETER language
    The orchestrator language.

.PARAMETER disableTelemetry
    Disable telemetry data.


.EXAMPLE
.\UiPathRunTest.ps1 <orchestrator_url> <orchestrator_tenant> [-project_path <package>] [-testset <testset>] [-orchestrator_user <orchestrator_user> -orchestrator_pass <orchestrator_pass>] [-UserKey <auth_token> -account_name <account_name>] [-environment <environment>] [-folder_organization_unit <folder_organization_unit>] [-language <language>]

  Examples:
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -S "MyRobotTests"
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -project_path "C:\UiPath\Project\project.json" -environment TestingEnv
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -project_path "C:\UiPath\Project\project.json" -folder_organization_unit MyFolder
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -project_path "C:\UiPath\Project\project.json" -folder_organization_unit MyFolder -environment MyEnvironment
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -UserKey a7da29a2c93a717110a82 -account_name myAccount -testset "MyRobotTests"
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -UserKey a7da29a2c93a717110a82 -account_name myAccount -project_path "C:\UiPath\Project\project.json" -environment TestingEnv -out junit
    .\UiPathRunTest.ps1 "https://uipath-orchestrator.myorg.com" default -UserKey a7da29a2c93a717110a82 -account_name myAccount -project_path "C:\UiPath\Project\project.json" -environment TestingEnv -result_path "C:\results.json" -out uipath -language en-US
#>
Param (

    # Required
    [string] $orchestrator_url = "", # The URL of the Orchestrator instance.
	[string] $orchestrator_tenant = "", # The tenant of the Orchestrator instance.

	[string] $project_path = "", # The path to a test package file.
	[string] $testset = "", # The name of the test set to execute.

	[string] $result_path = "", # Results file path

    # Cloud - Required
    [string] $account_name = "", # Orchestrator CloudRPA account name.
	[string] $UserKey = "", # OAuth2 refresh token.

    # On-prem - Required
    [string] $orchestrator_user = "", # Orchestrator username.
	[string] $orchestrator_pass = "", # Orchestrator password.
	
	[string] $folder_organization_unit = "", # Folder (organization unit).
	[string] $language = "", # Orchestrator language.
    [string] $environment = "", # Environment to deploy the package to.
    [string] $disableTelemetry = "", # Disable telemetry data.
    [string] $timeout = "", # Timeout in seconds (default 7200).
    [string] $out = "" # Type of result file.
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
$debugLog = "$scriptPath\orchestrator-test-run.log"

# Verify UiPath CLI folder
$uipathCLI = "$scriptPath\uipathcli\lib\net461\uipcli.exe"
if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
    WriteLog "UiPath CLI does not exist in this folder. Attempting to download it..."
    try {
        $cliFolder = "$scriptPath\uipathcli"
        if (-not (Test-Path $cliFolder)) {
            New-Item -Path $scriptPath -Name "uipathcli" -ItemType Directory | Out-Null
        }
        Invoke-WebRequest "https://www.myget.org/F/uipath-dev/api/v2/package/UiPath.CLI/1.0.7802.11617" -OutFile "$cliFolder\cli.zip"
        Expand-Archive -LiteralPath "$cliFolder\cli.zip" -DestinationPath $cliFolder -Force
        Remove-Item "$cliFolder\cli.zip" -Force
        WriteLog "UiPath CLI downloaded and extracted in folder $cliFolder"
        if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
            WriteLog "Unable to locate uipathcli.exe after download."
            exit 1
        }
    }
    catch {
        WriteLog ("Error occurred: " + $_.Exception.Message) -err
        exit 1
    }
}

WriteLog "-----------------------------------------------------------------------------"
WriteLog "UiPath CLI location: $uipathCLI"

# Validate required parameters
if ([string]::IsNullOrEmpty($orchestrator_url) -or [string]::IsNullOrEmpty($orchestrator_tenant)) {
    WriteLog "Error: orchestrator_url and orchestrator_tenant are required parameters." -err
    exit 1
}

# Validate authentication parameters
if ([string]::IsNullOrEmpty($account_name) -or [string]::IsNullOrEmpty($UserKey)) {
    if ([string]::IsNullOrEmpty($orchestrator_user) -or [string]::IsNullOrEmpty($orchestrator_pass)) {
        WriteLog "Error: Provide either account_name and UserKey (cloud) OR orchestrator_user and orchestrator_pass (on-prem)." -err
        exit 1
    }
}

# Either project_path or testset is required
if ([string]::IsNullOrEmpty($project_path) -and [string]::IsNullOrEmpty($testset)) {
    WriteLog "Error: Either project_path or testset parameter must be specified." -err
    exit 1
}

# Build UiPath CLI parameters
$ParamList = New-Object 'System.Collections.Generic.List[string]'
$ParamList.Add("test")
$ParamList.Add("run")
$ParamList.Add($orchestrator_url)
$ParamList.Add($orchestrator_tenant)

if (-not [string]::IsNullOrEmpty($project_path)) {
    $ParamList.Add("-P")
    $ParamList.Add($project_path)
}
if (-not [string]::IsNullOrEmpty($testset)) {
    $ParamList.Add("-s")
    $ParamList.Add($testset)
}
if (-not [string]::IsNullOrEmpty($result_path)) {
    $ParamList.Add("-r")
    $ParamList.Add($result_path)
}
if (-not [string]::IsNullOrEmpty($account_name)) {
    $ParamList.Add("-a")
    $ParamList.Add($account_name)
}
if (-not [string]::IsNullOrEmpty($UserKey)) {
    $ParamList.Add("-t")
    $ParamList.Add($UserKey)
}
if (-not [string]::IsNullOrEmpty($orchestrator_user)) {
    $ParamList.Add("-u")
    $ParamList.Add($orchestrator_user)
}
if (-not [string]::IsNullOrEmpty($orchestrator_pass)) {
    $ParamList.Add("-p")
    $ParamList.Add($orchestrator_pass)
}
if (-not [string]::IsNullOrEmpty($folder_organization_unit)) {
    $ParamList.Add("-o")
    $ParamList.Add($folder_organization_unit)
}
if (-not [string]::IsNullOrEmpty($environment)) {
    $ParamList.Add("-e")
    $ParamList.Add($environment)
}
if (-not [string]::IsNullOrEmpty($timeout)) {
    $ParamList.Add("-w")
    $ParamList.Add($timeout)
}
if (-not [string]::IsNullOrEmpty($out)) {
    $ParamList.Add("--out")
    $ParamList.Add($out)
}
if (-not [string]::IsNullOrEmpty($language)) {
    $ParamList.Add("-l")
    $ParamList.Add($language)
}
if (-not [string]::IsNullOrEmpty($disableTelemetry)) {
    $ParamList.Add("-y")
    $ParamList.Add($disableTelemetry)
}

# Mask sensitive info before logging
$ParamMask = [System.Collections.Generic.List[string]]::new()
$ParamMask.AddRange($ParamList)

$secretIndex = $ParamMask.IndexOf("-p")
if ($secretIndex -ge 0 -and $orchestrator_pass) {
    $ParamMask[$secretIndex + 1] = "*" * $orchestrator_pass.Length
}
$secretIndex = $ParamMask.IndexOf("-t")
if ($secretIndex -ge 0 -and $UserKey) {
    $visibleChars = 4
    $hiddenLength = $UserKey.Length - $visibleChars
    $ParamMask[$secretIndex + 1] = $UserKey.Substring(0, $visibleChars) + ("*" * $hiddenLength)
}

WriteLog "Executing: $uipathCLI $($ParamMask -join ' ')"

# Run UiPath CLI
& "$uipathCLI" $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Done!"
    exit 0
} else {
    WriteLog "Unable to run test. Exit code $LASTEXITCODE" -err
    exit 1
}
