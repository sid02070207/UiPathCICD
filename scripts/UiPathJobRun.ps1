<#
.SYNOPSIS 
    Run UiPath Orchestrator Job.

.DESCRIPTION 
    This script is to run orchestrator job.

.PARAMETER processName 
    Orchestrator process name to run.

.PARAMETER uriOrch 
    The URL of Orchestrator.

.PARAMETER tenantlName 
    The tenant name.

.PARAMETER orchestrator_user
    On-premises Orchestrator admin user name who has a Role of Create Package.

.PARAMETER orchestrator_pass
    The password of the on-premises Orchestrator admin user.

.PARAMETER userKey
    User key for Cloud Platform Orchestrator.

.PARAMETER accountName
    Account logical name for Cloud Platform Orchestrator.

.PARAMETER input_path
    The full path to a JSON input file. Only required if the entry-point workflow has input parameters.

.PARAMETER jobscount
    The number of job runs. (default 1)

.PARAMETER result_path
    The full path to a JSON file or a folder where the result json file will be created.

.PARAMETER priority
    The priority of job runs. One of the following values: Low, Normal, High. (default Normal)

.PARAMETER robots
    The comma-separated list of specific robot names.

.PARAMETER folder_organization_unit
    The Orchestrator folder (organization unit).

.PARAMETER user
    The name of the user. This should be a machine user, not an orchestrator user. For local users, the format should be MachineName\UserName

.PARAMETER language
    The orchestrator language.

.PARAMETER machine
    The name of the machine.

.PARAMETER timeout
    The timeout for job executions in seconds. (default 1800)

.PARAMETER fail_when_job_fails
    The command fails when at least one job fails. (default true)

.PARAMETER wait
    The command waits for job runs completion. (default true)

.PARAMETER job_type
    The type of the job that will run. Values supported for this command: Unattended, NonProduction. For classic folders do not specify this argument.

.PARAMETER disableTelemetry
    Disable telemetry data.

.EXAMPLE
PS> .\UiPathJobRun.ps1 -processName SimpleRPAFlow -uriOrch https://cloud.uipath.com -tenantlName AbdullahTenant -accountName accountLogicalName -userKey uYxxxxxxxx -folder_organization_unit MyWork-Dev 
- (Cloud Example) Run a process named SimpleRPAFlow in folder MyWork-Dev 

.EXAMPLE
PS> .\UiPathJobRun.ps1 -processName SimpleRPAFlow -uriOrch https://myorch.company.com -tenantlName AbdullahTenant -orchestrator_user admin -orchestrator_pass 123456 -folder_organization_unit MyWork-Dev 
- (On Prem Example) Run a process named SimpleRPAFlow in folder MyWork-Dev 

#>

Param (
    # Required
    [string] $processName = "",             # Process Name (pos. 0) Required.
    [string] $uriOrch = "",                 # Orchestrator URL (pos. 1) Required.
    [string] $tenantlName = "",             # Orchestrator Tenant (pos. 2) Required.

    # Cloud - Required together
    [string] $accountName = "",             # Cloud Account Name
    [string] $userKey = "",                 # Cloud User Key (OAuth2 refresh token)

    # On Premises - Required together
    [string] $orchestrator_user = "",      # Orchestrator username
    [string] $orchestrator_pass = "",      # Orchestrator password

    # Optional
    [string] $input_path = "",
    [string] $jobscount = "1",
    [string] $result_path = "",
    [string] $priority = "Normal",
    [string] $robots = "",
    [string] $folder_organization_unit = "",
    [string] $language = "",
    [string] $user = "",
    [string] $machine = "",
    [string] $timeout = "1800",
    [string] $fail_when_job_fails = "true",
    [string] $wait = "true",
    [string] $job_type = "",
    [string] $disableTelemetry = ""
)

function WriteLog {
    Param (
        [string] $message,
        [switch] $err
    )
    
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
$debugLog = "$scriptPath\orchestrator-job-run.log"

# Verify UiPath CLI folder
$uipathCLI = "$scriptPath\uipathcli\lib\net461\uipcli.exe"
if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
    WriteLog "UiPath CLI does not exist in this folder. Attempting to download it..."
    try {
        if (-not (Test-Path -Path "$scriptPath\uipathcli")) {
            New-Item -Path "$scriptPath" -ItemType Directory -Name "uipathcli" | Out-Null
        }
        Invoke-WebRequest -Uri "https://www.myget.org/F/uipath-dev/api/v2/package/UiPath.CLI/1.0.7802.11617" -OutFile "$scriptPath\uipathcli\cli.zip" -UseBasicParsing
        Expand-Archive -LiteralPath "$scriptPath\uipathcli\cli.zip" -DestinationPath "$scriptPath\uipathcli" -Force
        Remove-Item "$scriptPath\uipathcli\cli.zip" -Force
        WriteLog "UiPath CLI is downloaded and extracted in folder $scriptPath\uipathcli"
        if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
            WriteLog "Unable to locate uipathcli.exe after it was downloaded." -err
            exit 1
        }
    }
    catch {
        WriteLog ("Error Occurred: " + $_.Exception.Message) -err
        exit 1
    }
}

WriteLog "-----------------------------------------------------------------------------"
WriteLog "uipcli location: $uipathCLI"

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($processName) -or [string]::IsNullOrWhiteSpace($uriOrch) -or [string]::IsNullOrWhiteSpace($tenantlName)) {
    WriteLog "Missing required parameters: processName, uriOrch, or tenantlName." -err
    exit 1
}

# Validate authentication parameters: either cloud or on-prem
if ([string]::IsNullOrWhiteSpace($accountName) -or [string]::IsNullOrWhiteSpace($userKey)) {
    if ([string]::IsNullOrWhiteSpace($orchestrator_user) -or [string]::IsNullOrWhiteSpace($orchestrator_pass)) {
        WriteLog "Authentication parameters missing. Provide either accountName & userKey (Cloud) OR orchestrator_user & orchestrator_pass (On Prem)." -err
        exit 1
    }
}

# Build UiPath CLI parameters
$ParamList = New-Object 'Collections.Generic.List[string]'
$ParamList.Add("job")
$ParamList.Add("run")
$ParamList.Add($processName)
$ParamList.Add($uriOrch)
$ParamList.Add($tenantlName)

if ($accountName) {
    $ParamList.Add("-a")
    $ParamList.Add($accountName)
}
if ($userKey) {
    $ParamList.Add("-t")
    $ParamList.Add($userKey)
}
if ($orchestrator_user) {
    $ParamList.Add("-u")
    $ParamList.Add($orchestrator_user)
}
if ($orchestrator_pass) {
    $ParamList.Add("-p")
    $ParamList.Add($orchestrator_pass)
}
if ($input_path) {
    $ParamList.Add("-i")
    $ParamList.Add($input_path)
}
if ($jobscount) {
    $ParamList.Add("-j")
    $ParamList.Add($jobscount)
}
if ($result_path) {
    $ParamList.Add("-R")
    $ParamList.Add($result_path)
}
if ($priority) {
    $ParamList.Add("-P")
    $ParamList.Add($priority)
}
if ($robots) {
    $ParamList.Add("-r")
    $ParamList.Add($robots)
}
if ($folder_organization_unit) {
    $ParamList.Add("-o")
    $ParamList.Add($folder_organization_unit)
}
if ($language) {
    $ParamList.Add("-l")
    $ParamList.Add($language)
}
if ($user) {
    $ParamList.Add("-U")
    $ParamList.Add($user)
}
if ($machine) {
    $ParamList.Add("-M")
    $ParamList.Add($machine)
}
if ($timeout) {
    $ParamList.Add("-T")
    $ParamList.Add($timeout)
}
if ($fail_when_job_fails) {
    $ParamList.Add("-f")
    $ParamList.Add($fail_when_job_fails)
}
if ($wait) {
    $ParamList.Add("-w")
    $ParamList.Add($wait)
}
if ($job_type) {
    $ParamList.Add("-b")
    $ParamList.Add($job_type)
}
if ($disableTelemetry) {
    $ParamList.Add("-y")
    $ParamList.Add($disableTelemetry)
}

# Mask sensitive info before logging 
$ParamMask = New-Object 'Collections.Generic.List[string]'
$ParamMask.AddRange($ParamList)
$secretIndex = $ParamMask.IndexOf("-p")
if ($secretIndex -ge 0 -and $orchestrator_pass) {
    $ParamMask[$secretIndex + 1] = ("*" * $orchestrator_pass.Length)
}
$secretIndex = $ParamMask.IndexOf("-t")
if ($secretIndex -ge 0 -and $userKey) {
    $ParamMask[$secretIndex + 1] = $userKey.Substring(0,4) + ("*" * ($userKey.Length - 4))
}

WriteLog "Executing: $uipathCLI $($ParamMask -join ' ')"

# Run the UiPath CLI with parameters
& "$uipathCLI" $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Done!"
    exit 0
} else {
    WriteLog "Unable to run process. Exit code $LASTEXITCODE" -err
    exit 1
}
