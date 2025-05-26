<#
.SYNOPSIS
    Deploy UiPath package to Orchestrator using PAT (Personal Access Token) for Cloud

.PARAMETER packages_path
    Path to the .nupkg file or directory

.PARAMETER orchestrator_url
    Orchestrator URL (e.g., https://cloud.uipath.com/{account}/portal_/orchestrator_)

.PARAMETER orchestrator_tenant
    Orchestrator Tenant name (e.g., DefaultTenant)

.PARAMETER account_name
    Account name in UiPath Cloud (e.g., siddhglesuos)

.PARAMETER pat
    Personal Access Token

#>

param (
    [string]$packages_path,
    [string]$orchestrator_url,
    [string]$orchestrator_tenant,
    [string]$account_name,
    [string]$pat
)

function WriteLog {
    param ($message)
    Write-Host "$(Get-Date -Format "u") - $message"
}

# Set CLI path
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$uipathCLI = "$scriptPath\uipathcli\lib\net461\uipcli.exe"

# Download UiPath CLI if missing
if (-not (Test-Path $uipathCLI)) {
    WriteLog "Downloading UiPath CLI..."
    Invoke-WebRequest "https://www.myget.org/F/uipath-dev/api/v2/package/UiPath.CLI/1.0.7802.11617" -OutFile "$scriptPath\uipathcli.zip"
    Expand-Archive -Path "$scriptPath\uipathcli.zip" -DestinationPath "$scriptPath\uipathcli"
}

# Execute deploy with PAT
WriteLog "Deploying package using PAT authentication..."
& "$uipathCLI" package deploy "$packages_path" "$orchestrator_url" "$orchestrator_tenant" `
    --cloud --account-name "$account_name" --client-pat "$pat"

if ($LASTEXITCODE -eq 0) {
    WriteLog "Package deployed successfully."
} else {
    WriteLog "Deployment failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
