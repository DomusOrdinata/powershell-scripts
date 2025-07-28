<#
.SYNOPSIS
    Entra ID Cutover Script – From Hybrid Sync to Cloud-Only
.DESCRIPTION
    This script performs a cutover from on-prem AD sync to Microsoft Entra ID (Azure AD) cloud-only mode.
    It:
        - Verifies the Microsoft.Graph PowerShell module is installed and imported
        - Authenticates the user and checks for required permissions
        - Initiates the cutover by disabling directory synchronization
        - Polls every 15 minutes until the OnPremisesSyncEnabled flag is confirmed false
        - Logs every action with timestamps to both console and log file
.NOTES
    Author: [Your Name]
    Date: [Today’s Date]
    Requirements: PowerShell 7+, Microsoft Graph PowerShell SDK, Hybrid Identity Administrator or Global Administrator permissions.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Logging Function --
$LogFile = "EntraIDCUTOVER_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$ts - $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "=== Entra ID Cutover Script STARTED ==="

# -- Ensure Microsoft.Graph module is installed --
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Log "Microsoft.Graph PowerShell module not found. Attempting installation..."
    try {
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -ErrorAction Stop
        Write-Log "Microsoft.Graph module installed successfully."
    } catch {
        Write-Log "ERROR: Failed to install Microsoft.Graph PowerShell module. $_"
        exit 1
    }
} else {
    Write-Log "Microsoft.Graph module already present."
}

# -- Import Microsoft.Graph module --
try {
    Import-Module Microsoft.Graph -ErrorAction Stop
    Write-Log "Microsoft.Graph module imported."
} catch {
    Write-Log "ERROR: Failed to import Microsoft.Graph module. $_"
    exit 1
}

# -- Authenticate with required Graph permissions --
try {
    Write-Log "Connecting to Microsoft Graph. Please complete authentication in the popup window..."
    Connect-MgGraph -Scopes "Organization.ReadWrite.All" | Out-Null
    Write-Log "Authenticated with Microsoft Graph."
} catch {
    Write-Log "ERROR: Failed to authenticate to Microsoft Graph. $_"
    exit 1
}

# -- Check required permissions for the account --
try {
    $context = Get-MgContext
    $me = Get-MgUser -UserId $context.Account
    Write-Log "Authenticated as: $($me.DisplayName) <$($me.UserPrincipalName)>"

    if (-not $context.Scopes -or ($context.Scopes -notcontains "Organization.ReadWrite.All")) {
        Write-Log "ERROR: Insufficient Microsoft Graph permissions. 'Organization.ReadWrite.All' is required."
        exit 1
    } else {
        Write-Log "Permission check: 'Organization.ReadWrite.All' scope granted."
    }
} catch {
    Write-Log "ERROR: Unable to verify account permissions. $_"
    exit 1
}

# -- Get current Org sync state --
try {
    $org = Get-MgOrganization
    if (-not $org) {
        Write-Log "ERROR: Failed to retrieve organization information."
        exit 1
    }
    $orgId = $org.Id
    $syncState = $org.OnPremisesSyncEnabled
    Write-Log "Current OnPremisesSyncEnabled: $syncState"
} catch {
    Write-Log "ERROR: Failed to retrieve organization details. $_"
    exit 1
}

if ($syncState -eq $false) {
    Write-Log "Directory sync already disabled. No cutover required."
    Write-Log "=== Entra ID Cutover Script ENDED ==="
    exit 0
}

# -- Initiate cutover --
try {
    Write-Log "Initiating cutover: Disabling Directory Synchronization (OnPremisesSyncEnabled = false)..."
    Update-MgOrganization -OrganizationId $orgId -OnPremisesSyncEnabled:$false
    Write-Log "Directory sync disable command sent. Polling status every 15 minutes..."
} catch {
    Write-Log "ERROR: Failed to set OnPremisesSyncEnabled to false. $_"
    exit 1
}

# -- Poll every 15min until OnPremisesSyncEnabled = False --
$maxChecks = 288  # 72 hours (4 per hour x 72h)
$checkCount = 0

while ($true) {
    Start-Sleep -Seconds (15 * 60)
    $checkCount++

    try {
        $org = Get-MgOrganization
        $syncState = $org.OnPremisesSyncEnabled
        Write-Log "Check #$($checkCount): OnPremisesSyncEnabled = $syncState"
    } catch {
        Write-Log "ERROR: Failed to poll organization sync state. $_"
    }

    if ($syncState -eq $false) {
        Write-Log "===== CUTOVER COMPLETED SUCCESSFULLY ====="
        Write-Host "`n`nCUTOVER COMPLETED SUCCESSFULLY`n"
        break
    }

    if ($checkCount -ge $maxChecks) {
        Write-Log "WARNING: Cutover did not complete within expected 72 hours. Manual intervention recommended."
        Write-Host "`nWARNING: Cutover did not complete within expected window. Please investigate manually.`n"
        break
    }
}

Write-Log "=== Entra ID Cutover Script ENDED ==="
