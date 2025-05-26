<#
.SYNOPSIS 
    Manage UiPath Orchestrator assets

.DESCRIPTION 
    Delete assets from an Orchestrator instance (based on asset name).
    Deploy assets to an Orchestrator instance.

.PARAMETER $operation 
    Manage assets operation (delete | deploy) 

.PARAMETER $assets_file 
     The following is a sample CSV file. The column names are required! Only the first column is used but you need to at least have empty columns in place.
                                  name,type,value
                                  asset_1_name,boolean,false # we can have comments
                                  asset_2_name,integer,
                                  asset_3_name,text,
                                  asset_4_name,credential,username::password

.PARAMETER orchestrator_url 
    Required. The URL of the Orchestrator instance.

.PARAMETER orchestrator_tenant 
    Required. The tenant of the Orchestrator instance.

.PARAMETER orchestrator_user
    Required for on-prem. The Orchestrator username used for authentication. Must be used together with the password.

.PARAMETER orchestrator_pass
    Required for on-prem. The Orchestrator password used for authentication. Must be used together with the username

.PARAMETER UserKey
    Required for cloud. The Orchestrator OAuth2 refresh token used for authentication. Must be used together with the account name.

.PARAMETER account_name
    Required for cloud. The Orchestrator CloudRPA account name. Must be used together with the refresh token.

.PARAMETER folder_organization_unit
    The Orchestrator folder (organization unit).

.PARAMETER language
    The Orchestrator language.

.PARAMETER disableTelemetry
    Disable telemetry data. Use "-y" as a switch.

.EXAMPLE
    . 'C:\scripts\UiPathManageAssets.ps1' deploy assets_file.csv "https://uipath-orchestrator.myorg.com" defaultTenant -orchestrator_user admin -orchestrator_pass 123456
#>

Param (
    # Required parameters
    [string] $operation = "", # Manage assets operation (delete | deploy) 
    [string] $assets_file = "", # Assets file
    
    [string] $orchestrator_url = "", # Required. The URL of the Orchestrator instance.
    [string] $orchestrator_tenant = "", # Required. The tenant of the Orchestrator instance.

    # Cloud - Required
    [string] $account_name = "", # Required for cloud
    [string] $UserKey = "",       # Required for cloud
    
    # On-prem - Required
    [string] $orchestrator_user = "", # Required for on-prem
    [string] $orchestrator_pass = "", # Required for on-prem
	
    [string] $folder_organization_unit = "", # Orchestrator folder (organization unit)
    [string] $language = "",                  # Orchestrator language
    [switch] $disableTelemetry                # Disable telemetry switch (use -disableTelemetry)
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
    }
    else {
        Write-Host $line
    }
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = "$scriptPath\orchestrator-test-run.log"

# Verify UiPath CLI existence
$uipathCLI = "$scriptPath\uipathcli\lib\net461\uipcli.exe"
if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
    WriteLog "UiPath CLI does not exist in this folder. Attempting to download it..."
    try {
        New-Item -Path "$scriptPath" -ItemType Directory -Name "uipathcli" -ErrorAction SilentlyContinue | Out-Null
        Invoke-WebRequest "https://www.myget.org/F/uipath-dev/api/v2/package/UiPath.CLI/1.0.7802.11617" -OutFile "$scriptPath\uipathcli\cli.zip"
        Expand-Archive -LiteralPath "$scriptPath\uipathcli\cli.zip" -DestinationPath "$scriptPath\uipathcli" -Force
        WriteLog "UiPath CLI downloaded and extracted in folder $scriptPath\uipathcli"
        if (-not (Test-Path -Path $uipathCLI -PathType Leaf)) {
            WriteLog "Unable to locate uipathcli after download."
            exit 1
        }
    }
    catch {
        WriteLog ("Error occurred: " + $_.Exception.Message) -err
        exit 1
    }
}

WriteLog "-----------------------------------------------------------------------------"
WriteLog "uipcli location: $uipathCLI"

# Validate operation
if ($operation -ne "delete" -and $operation -ne "deploy") {
    WriteLog "Invalid operation. Operation must be 'delete' or 'deploy'. You typed '$operation'" -err
    exit 1
}

# Make assets_file full path if relative
if (-not ($assets_file.Contains("\"))) {
    $assets_file = "$scriptPath\$assets_file"
}

# Validate assets file exists
if (-not (Test-Path -Path $assets_file -PathType Leaf)) {
    WriteLog "Assets file does not exist: $assets_file" -err
    exit 1
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($orchestrator_url) -or [string]::IsNullOrWhiteSpace($orchestrator_tenant)) {
    WriteLog "Required parameters 'orchestrator_url' and 'orchestrator_tenant' must be specified." -err
    exit 1
}

# Validate authentication parameters (cloud or on-prem)
$cloudAuthProvided = (-not [string]::IsNullOrWhiteSpace($account_name) -and -not [string]::IsNullOrWhiteSpace($UserKey))
$onPremAuthProvided = (-not [string]::IsNullOrWhiteSpace($orchestrator_user) -and -not [string]::IsNullOrWhiteSpace($orchestrator_pass))

if (-not ($cloudAuthProvided -or $onPremAuthProvided)) {
    WriteLog "Authentication parameters incomplete. Provide either cloud credentials (-account_name and -UserKey) or on-prem credentials (-orchestrator_user and -orchestrator_pass)." -err
    exit 1
}

# Build UiPath CLI parameters
$ParamList = New-Object 'System.Collections.Generic.List[string]'
$ParamList.Add("asset")
$ParamList.Add($operation)
$ParamList.Add($assets_file)
$ParamList.Add($orchestrator_url)
$ParamList.Add($orchestrator_tenant)

if ($account_name) {
    $ParamList.Add("-a")
    $ParamList.Add($account_name)
}
if ($UserKey) {
    $ParamList.Add("-t")
    $ParamList.Add($UserKey)
}
if ($orchestrator_user) {
    $ParamList.Add("-u")
    $ParamList.Add($orchestrator_user)
}
if ($orchestrator_pass) {
    $ParamList.Add("-p")
    $ParamList.Add($orchestrator_pass)
}
if ($folder_organization_unit) {
    $ParamList.Add("-o")
    $ParamList.Add($folder_organization_unit)
}
if ($language) {
    $ParamList.Add("-l")
    $ParamList.Add($language)
}
if ($disableTelemetry.IsPresent) {
    $ParamList.Add("-y")
}

# Mask sensitive information in logs
$ParamMask = $ParamList.Clone()
$secretIndex = $ParamMask.IndexOf("-p")
if ($secretIndex -ge 0) {
    $ParamMask[$secretIndex + 1] = ("*" * $orchestrator_pass.Length)
}
$secretIndex = $ParamMask.IndexOf("-t")
if ($secretIndex -ge 0) {
    $ParamMask[$secretIndex + 1] = $UserKey.Substring(0,4) + ("*" * ($UserKey.Length - 4))
}

WriteLog "Executing $uipathCLI $($ParamMask -join ' ')"

# Execute UiPath CLI command
& "$uipathCLI" $ParamList.ToArray()

if ($LASTEXITCODE -eq 0) {
    WriteLog "Done!"
    exit 0
}
else {
    WriteLog "Command execution failed with exit code $LASTEXITCODE" -err
    exit 1
}
