<#
.SYNOPSIS
    Guided 7-step signing key upgrade for Microsoft Entra Verified ID authorities.

.DESCRIPTION
    Upgrades a Verified ID authority's signing key from P-256K (secp256k1) to P-256
    to become FIPS compliant. Follows the documented process at:
    https://learn.microsoft.com/en-us/entra/verified-id/signing-key-upgrade#upgrading-the-signing-key

    Steps:
      1. Create a new P-256 signing key in Key Vault
      2. Generate a new DID document (did.json)
      3. [Manual] Deploy did.json to web servers
      4. Synchronize with DID document (start using the new key)
      5. Generate well-known DID configuration (did-configuration.json)
      6. [Manual] Deploy did-configuration.json to web servers
      7. Validate well-known DID configuration (linked domain verified)

.PARAMETER TenantId
    The Azure AD / Entra tenant ID. If omitted, you will be prompted.

.PARAMETER ClientId
    The app registration client ID with Verifiable Credentials Service Admin permission.
    If omitted, you will be prompted.

.PARAMETER AuthorityId
    The Verified ID authority ID to upgrade. If omitted, the script lists all
    authorities and lets you choose. Can use -Did instead.

.PARAMETER Did
    The DID string (e.g. did:web:example.com) of the authority to upgrade.
    The script resolves this to the authority ID automatically.
    Use this instead of -AuthorityId when you know the DID but not the GUID.

.PARAMETER OutputDir
    Directory to save did.json and did-configuration.json files. Defaults to the
    current directory.

.PARAMETER StartFromStep
    Resume from a specific step (1-7). Useful when a previous run failed and you
    want to pick up where you left off. Defaults to 1 (start from beginning).

.PARAMETER UseDeviceCode
    Use device-code flow instead of interactive browser login.

.EXAMPLE
    .\Upgrade-SigningKey.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444"

.EXAMPLE
    .\Upgrade-SigningKey.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444" -AuthorityId "00aa00aa-bb11-cc22-dd33-44ee44ee44ee" -OutputDir "C:\deploy"

.EXAMPLE
    .\Upgrade-SigningKey.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444" -Did "did:web:example.com"

.EXAMPLE
    .\Upgrade-SigningKey.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444" -StartFromStep 4

.NOTES
    Prerequisites:
      - The admin user must have permission to keys in Key Vault.
      - The app registration must have the API Permission for
        'Verifiable Credentials Service Admin' (6a8b4b39-c021-437c-b060-5a14a3fd65f3/full_access).
      - PowerShell 7+ required (pwsh). Windows PowerShell 5.1 is not supported.
      - MSAL.PS module is required for authentication (installed automatically if missing).
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$AuthorityId,

    [Parameter()]
    [string]$Did,

    [Parameter()]
    [string]$OutputDir = ".",

    [Parameter()]
    [ValidateRange(1, 7)]
    [int]$StartFromStep = 1,

    [Parameter()]
    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Require PowerShell 7+ ─────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "  [FAIL] This script requires PowerShell 7 or later." -ForegroundColor Red
    Write-Host "  You are running PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Windows PowerShell 5.1 writes UTF-8 with a BOM, which corrupts" -ForegroundColor Yellow
    Write-Host "  did.json and did-configuration.json and causes DID resolution failures." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Install PowerShell 7: https://aka.ms/install-powershell" -ForegroundColor Cyan
    Write-Host "  Then re-run this script from a 'pwsh' prompt." -ForegroundColor Cyan
    exit 1
}

# ─── Constants ────────────────────────────────────────────────────────────────
$BaseUrl = "https://verifiedid.did.msidentity.com"
$Scope   = "6a8b4b39-c021-437c-b060-5a14a3fd65f3/full_access"

# ─── Helper functions ─────────────────────────────────────────────────────────

function Set-Utf8NoBomContent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Write-StepHeader {
    param([int]$StepNumber, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host "  Step $StepNumber of 7: $Title" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [i] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Confirm-Continue {
    param([string]$Prompt = "Press ENTER to continue or Ctrl+C to abort...")
    Write-Host ""
    Read-Host "  $Prompt"
}

function Confirm-NextStepOrExit {
    param([int]$CompletedStep)
    if ($CompletedStep -ge 7) { return $false }
    $nextStep = $CompletedStep + 1
    Write-Host ""
    Write-Host ("─" * 78) -ForegroundColor DarkGray
    $choice = Read-Host "  Step $CompletedStep complete. Continue to Step ${nextStep}? [Y/N]"
    if ($choice -match '^[yY]') {
        Write-Log "User chose to continue to Step $nextStep"
        return $true
    }
    else {
        Write-Info "Exiting after Step $CompletedStep. You can resume later with -StartFromStep $nextStep."
        Write-Log "User chose to exit after Step $CompletedStep"
        return $false
    }
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8
}

function Write-StepFailure {
    param([int]$StepNumber, [string]$ErrorMessage)
    Write-Fail $ErrorMessage
    Write-Log "FAILED at Step ${StepNumber}: $ErrorMessage"
    Write-Host ""
    Write-Host "  To resume from this step, re-run with:" -ForegroundColor Yellow
    $resumeCmd = "  .\Upgrade-SigningKey.ps1 -TenantId `"$TenantId`" -ClientId `"$ClientId`" -AuthorityId `"$authorityId`" -StartFromStep $StepNumber"
    Write-Host "  $resumeCmd" -ForegroundColor Cyan
    Write-Log "Resume command: $resumeCmd"
    Write-Host ""
    Write-Host "  Log file: $($script:LogFile)" -ForegroundColor Gray
}

function Invoke-VerifiedIdApi {
    <#
    .SYNOPSIS
        Calls the Verified ID Admin API and returns the parsed response.
    #>
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$AccessToken,
        [object]$Body = $null,
        [switch]$Silent
    )

    $uri = "$BaseUrl$Endpoint"
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    $params = @{
        Uri     = $uri
        Method  = $Method
        Headers = $headers
    }
    if ($Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
    }

    Write-Verbose "  $Method $uri"
    try {
        $response = Invoke-RestMethod @params -ErrorAction Stop
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode
        $errorBody = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errorBody = $_.ErrorDetails.Message
        }
        if (-not $Silent) {
            Write-Fail "API call failed: $Method $Endpoint"
            if ($statusCode) { Write-Fail "  HTTP $([int]$statusCode) $statusCode" }
            if ($errorBody)  { Write-Fail "  $errorBody" }
        }
        throw
    }
}

function Get-HttpStatusCode {
    param($ErrorRecord)
    if ($ErrorRecord.Exception.Response) {
        return [int]$ErrorRecord.Exception.Response.StatusCode
    }
    elseif ($ErrorRecord.Exception.InnerException -and $ErrorRecord.Exception.InnerException.Response) {
        return [int]$ErrorRecord.Exception.InnerException.Response.StatusCode
    }
    return $null
}

# ─── Ensure MSAL.PS module ───────────────────────────────────────────────────

if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Info "MSAL.PS module not found. Installing from PSGallery..."
    try {
        Install-Module -Name MSAL.PS -Scope CurrentUser -Force -AllowClobber
    }
    catch {
        Write-Fail "Failed to install MSAL.PS module: $($_.Exception.Message)"
        Write-Fail "Please install it manually: Install-Module -Name MSAL.PS -Scope CurrentUser -Force"
        exit 1
    }
}
try {
    Import-Module MSAL.PS -ErrorAction Stop
}
catch {
    Write-Fail "Failed to import MSAL.PS module: $($_.Exception.Message)"
    exit 1
}

# ─── Collect parameters ──────────────────────────────────────────────────────

if (-not $TenantId) {
    $TenantId = Read-Host "Enter your Entra tenant ID (e.g. contoso.onmicrosoft.com or GUID)"
}
if (-not $ClientId) {
    $ClientId = Read-Host "Enter your app registration Client ID"
}

# ─── Authenticate ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Authenticating to Verified ID Admin API..." -ForegroundColor Cyan

$msalParams = @{
    ClientId = $ClientId
    TenantId = $TenantId
    Scopes   = @($Scope)
}

try {
    if ($UseDeviceCode) {
        $tokenResult = Get-MsalToken @msalParams -DeviceCode
    }
    else {
        try {
            $tokenResult = Get-MsalToken @msalParams -Interactive
        }
        catch {
            Write-Info "Interactive browser login failed (WebView2 not available). Falling back to device-code flow..."
            $tokenResult = Get-MsalToken @msalParams -DeviceCode
        }
    }
}
catch {
    Write-Fail "Authentication failed: $($_.Exception.Message)"
    Write-Fail "Verify the app registration has 'Verifiable Credentials Service Admin' API permission with admin consent."
    exit 1
}

$accessToken = $tokenResult.AccessToken
Write-Success "Authenticated as $($tokenResult.Account.Username)"

# ─── Resolve output directory ────────────────────────────────────────────────

$resolved = Resolve-Path -Path $OutputDir -ErrorAction SilentlyContinue
if ($resolved) { $OutputDir = $resolved.Path }
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ─── Initialize log file ─────────────────────────────────────────────────────

$script:LogFile = Join-Path $OutputDir "upgrade-signingkey.log"
Write-Log "=== Signing key upgrade started ==="
Write-Log "TenantId: $TenantId | ClientId: $ClientId | StartFromStep: $StartFromStep"
Write-Log "Authenticated as $($tokenResult.Account.Username)"

# ─── List authorities and select ──────────────────────────────────────────────

Write-Host ""
Write-Host "Fetching authorities..." -ForegroundColor Cyan
try {
    $authoritiesResponse = Invoke-VerifiedIdApi -Method GET `
        -Endpoint "/v1.0/verifiableCredentials/authorities" `
        -AccessToken $accessToken
}
catch {
    Write-Fail "Failed to fetch authorities: $($_.Exception.Message)"
    Write-Fail "Verify your permissions and network connectivity."
    exit 1
}

$authorities = $authoritiesResponse.value
if (-not $authorities -or $authorities.Count -eq 0) {
    Write-Fail "No authorities found in this tenant."
    exit 1
}

if ($AuthorityId) {
    $selectedAuthority = $authorities | Where-Object { $_.id -eq $AuthorityId }
    if (-not $selectedAuthority) {
        Write-Fail "Authority '$AuthorityId' not found."
        exit 1
    }
}
elseif ($Did) {
    $selectedAuthority = $authorities | Where-Object { $_.didModel.did -eq $Did }
    if (-not $selectedAuthority) {
        Write-Fail "No authority found with DID '$Did'."
        Write-Fail "Available DIDs:"
        foreach ($a in $authorities) { Write-Fail "  $($a.didModel.did)" }
        exit 1
    }
    Write-Success "Matched authority by DID: $($selectedAuthority.name)"
}
else {
    Write-Host ""
    Write-Host "  Available authorities:" -ForegroundColor White
    for ($i = 0; $i -lt $authorities.Count; $i++) {
        $a = $authorities[$i]
        $status = $a.didModel.didDocumentStatus
        $keyType = "unknown"
        if ($a.didModel.signingKeys -and $a.didModel.signingKeys.Count -gt 0) {
            $keyType = "(check Key Vault for curve type)"
        }
        Write-Host "    [$($i + 1)] $($a.name)" -ForegroundColor White -NoNewline
        Write-Host "  DID: $($a.didModel.did)" -ForegroundColor Gray -NoNewline
        Write-Host "  Status: $status" -ForegroundColor Gray
    }
    Write-Host ""

    if ($authorities.Count -eq 1) {
        $selectedIndex = 0
        Write-Info "Only one authority found — selecting '$($authorities[0].name)' automatically."
    }
    else {
        $selection = Read-Host "  Select authority [1-$($authorities.Count)]"
        $selectedIndex = [int]$selection - 1
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $authorities.Count) {
            Write-Fail "Invalid selection."
            exit 1
        }
    }
    $selectedAuthority = $authorities[$selectedIndex]
}

$authorityId = $selectedAuthority.id
$authorityName = $selectedAuthority.name

Write-Log "Authority: $authorityName ($authorityId)"

Write-Host ""
Write-Host "Selected authority: " -NoNewline
Write-Host "$authorityName" -ForegroundColor White
Write-Host "  Authority ID : $authorityId"
Write-Host "  DID          : $($selectedAuthority.didModel.did)"
Write-Host "  Domain(s)    : $($selectedAuthority.didModel.linkedDomainUrls -join ', ')"
Write-Host "  Doc Status   : $($selectedAuthority.didModel.didDocumentStatus)"

# ─── Pre-flight summary ──────────────────────────────────────────────────────

Write-Host ""
Write-Host ("-" * 78) -ForegroundColor DarkGray
Write-Host @"
  This script will walk you through the 7-step signing key upgrade process
  to migrate from P-256K (secp256k1) to P-256 (FIPS compliant).

  Reference: https://learn.microsoft.com/en-us/entra/verified-id/signing-key-upgrade

  Steps 1, 2, 4, 5, 7 call the Verified ID Admin API.
  Steps 3 and 6 require you to manually deploy files to your web server(s).
"@ -ForegroundColor Gray
Write-Host ("-" * 78) -ForegroundColor DarkGray

if ($StartFromStep -gt 1) {
    Write-Host ""
    Write-Host "  Resuming from Step $StartFromStep (skipping steps 1-$($StartFromStep - 1))." -ForegroundColor Yellow
}

# ─── Interactive Step Menu ─────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 78) -ForegroundColor DarkCyan
Write-Host "  Select which step(s) to run:" -ForegroundColor Cyan
Write-Host ("=" * 78) -ForegroundColor DarkCyan
Write-Host ""
Write-Host "    [A] Run ALL steps (from step $StartFromStep onward)" -ForegroundColor White
Write-Host ""
Write-Host "    [1] Create a new P-256 signing key in Key Vault" -ForegroundColor White
Write-Host "    [2] Generate a new DID document (did.json)" -ForegroundColor White
Write-Host "    [3] [Manual] Deploy did.json to web servers" -ForegroundColor White
Write-Host "    [4] Synchronize with DID document (start using new key)" -ForegroundColor White
Write-Host "    [5] Generate well-known DID configuration (did-configuration.json)" -ForegroundColor White
Write-Host "    [6] [Manual] Deploy did-configuration.json to web servers" -ForegroundColor White
Write-Host "    [7] Validate well-known DID configuration (linked domain verified)" -ForegroundColor White
Write-Host ""
$menuChoice = Read-Host "  Enter your choice [A / 1-7]"

$runAllSteps = $false
$currentStep = 0
$lastStep = 7

if ($menuChoice -match '^[aA]$') {
    $runAllSteps = $true
    $currentStep = $StartFromStep
    Write-Info "Running all steps from step $StartFromStep onward."
    Write-Log "Menu: User selected 'A' (all steps from $StartFromStep)"
}
elseif ($menuChoice -match '^[1-7]$') {
    $currentStep = [int]$menuChoice
    Write-Info "Starting from Step $currentStep."
    Write-Log "Menu: User selected Step $currentStep"
}
else {
    Write-Fail "Invalid choice '$menuChoice'. Please enter A or a number 1-7."
    Write-Log "Menu: Invalid choice '$menuChoice' — exiting"
    exit 1
}

Write-Host ""
Confirm-Continue "Press ENTER to begin..."

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Create a new P-256 signing key
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 1) {
    Write-StepHeader 1 "Create a new P-256 signing key in Key Vault"
    Write-Log "Step 1: Starting — Create signing key"

    try {
        Write-Info "Calling POST .../didInfo/signingKeys with signingKeyCurve = P-256"
        try {
            $step1Result = Invoke-VerifiedIdApi -Method POST `
                -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId/didInfo/signingKeys" `
                -AccessToken $accessToken `
                -Body @{ signingKeyCurve = "P-256" }

            Write-Success "New signing key created."
            Write-Host "  Key ID   : $($step1Result.id)" -ForegroundColor Gray
            Write-Host "  Key URL  : $($step1Result.keyUrl)" -ForegroundColor Gray
            Write-Host "  Curve    : $($step1Result.curve)" -ForegroundColor Gray
        }
        catch {
            $statusCode = Get-HttpStatusCode $_
            $errMsg = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
            if ($statusCode -eq 404 -or ($statusCode -eq 400 -and $errMsg -match "Maximum number of signing keys")) {
                if ($statusCode -eq 400) {
                    Write-Info "Maximum number of signing keys reached."
                    Write-Info "A P-256 key likely already exists from a previous run. Falling back to key rotation..."
                }
                else {
                    Write-Info "Create signing key endpoint not available (HTTP 404)."
                    Write-Info "This authority may already have P-256 keys. Falling back to key rotation..."
                }
                Write-Info "Calling POST .../didInfo/signingKeys/rotate"

                $step1Result = Invoke-VerifiedIdApi -Method POST `
                    -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId/didInfo/signingKeys/rotate" `
                    -AccessToken $accessToken

                Write-Success "Signing key rotated successfully."
            }
            else {
                throw
            }
        }
        Write-Info "The authority's didDocumentStatus is now 'outOfSync'."
        Write-Log "Step 1: Completed successfully"
    }
    catch {
        Write-StepFailure 1 "Failed to create/rotate signing key: $($_.Exception.Message)"
        exit 1
    }

    if ($runAllSteps) {
        Confirm-Continue
        $currentStep = 2
    }
    elseif (Confirm-NextStepOrExit -CompletedStep 1) {
        $currentStep = 2
    }
    else { $currentStep = $lastStep + 1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Generate a new DID document
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 2) {
    Write-StepHeader 2 "Generate a new DID document (did.json)"
    Write-Log "Step 2: Starting — Generate DID document"

    try {
        Write-Info "Calling POST .../generateDidDocument"
        $step2Result = Invoke-VerifiedIdApi -Method POST `
            -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId/generateDidDocument" `
            -AccessToken $accessToken

        $didJsonPath = Join-Path $OutputDir "did.json"
        $jsonContent = $step2Result | ConvertTo-Json -Depth 20
        Set-Utf8NoBomContent -Path $didJsonPath -Content $jsonContent

        Write-Success "DID document generated and saved."
        Write-Host "  File: $didJsonPath" -ForegroundColor Gray
        Write-Info "The generated DID document contains both the new P-256 key and the old P-256K key."
        Write-Log "Step 2: Completed — saved $didJsonPath"
    }
    catch {
        Write-StepFailure 2 "Failed to generate DID document: $($_.Exception.Message)"
        exit 1
    }

    if ($runAllSteps) {
        Confirm-Continue
        $currentStep = 3
    }
    elseif (Confirm-NextStepOrExit -CompletedStep 2) {
        $currentStep = 3
    }
    else { $currentStep = $lastStep + 1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3 — (Manual) Deploy did.json
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 3) {
    Write-StepHeader 3 "[MANUAL] Deploy did.json to your web server(s)"
    Write-Log "Step 3: Starting — Manual deploy did.json"

    $didDomain = $selectedAuthority.didModel.linkedDomainUrls | Select-Object -First 1
    $didJsonPath = Join-Path $OutputDir "did.json"
    Write-Host "  You must deploy the file to:" -ForegroundColor White
    Write-Host "    https://<your-domain>/.well-known/did.json" -ForegroundColor Yellow
    if ($didDomain) {
        $domainBase = $didDomain.TrimEnd('/')
        Write-Host "    Expected URL: $domainBase/.well-known/did.json" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  The file is located at: $didJsonPath" -ForegroundColor Gray
    Write-Host ""

    Write-Log "Step 3: Waiting for manual deployment of did.json"

    $didUploaded = Read-Host "  Have you uploaded did.json to your web server? [Y/N]"
    if ($didUploaded -match '^[yY]') {
        if ($didDomain) {
            $didJsonUrl = "$($didDomain.TrimEnd('/'))/.well-known/did.json"
            Write-Info "Checking $didJsonUrl ..."
            try {
                $didResponse = Invoke-WebRequest -Uri $didJsonUrl -Method GET -UseBasicParsing -ErrorAction Stop
                if ($didResponse.StatusCode -eq 200) {
                    Write-Success "HTTP 200 OK — did.json is publicly accessible at $didJsonUrl"
                    Write-Log "Step 3: HTTP GET $didJsonUrl returned 200 OK"
                }
                else {
                    Write-Fail "Unexpected HTTP status: $($didResponse.StatusCode)"
                    Write-Log "Step 3: HTTP GET $didJsonUrl returned $($didResponse.StatusCode)"
                }
            }
            catch {
                Write-Fail "Could not reach $didJsonUrl — $($_.Exception.Message)"
                Write-Fail "Please verify the file is deployed and publicly accessible."
                Write-Log "Step 3: HTTP GET $didJsonUrl failed — $($_.Exception.Message)"
            }

            Write-Host ""
            Write-Host "  Please browse to the following URL and verify that the new key" -ForegroundColor White
            Write-Host "  is listed in the 'assertionMethod' section of did.json:" -ForegroundColor White
            Write-Host "    $didJsonUrl" -ForegroundColor Yellow
            Write-Host ""
            $didConfirmed = Read-Host "  Have you confirmed the new key is listed in assertionMethod? [Y/N]"
            if ($didConfirmed -match '^[yY]') {
                Write-Success "Admin confirmed new key is present in assertionMethod."
                Write-Log "Step 3: Admin confirmed new key in assertionMethod"
            }
            else {
                Write-Info "Please verify the new key appears in assertionMethod before proceeding to Step 4."
                Write-Log "Step 3: Admin did not confirm new key in assertionMethod"
            }
        }
        else {
            Write-Info "No linked domain found for this authority. Cannot auto-verify."
            Write-Info "Please manually verify did.json is deployed and contains the new key."
        }
    }
    else {
        Write-Info "Please upload did.json to your web server before continuing."
        Confirm-Continue "Once did.json is deployed and publicly accessible, press ENTER to continue..."
    }

    Write-Log "Step 3: Completed — admin confirmed did.json deployed"

    if ($runAllSteps) {
        $currentStep = 4
    }
    elseif (Confirm-NextStepOrExit -CompletedStep 3) {
        $currentStep = 4
    }
    else { $currentStep = $lastStep + 1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Synchronize with DID document
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 4) {
    Write-StepHeader 4 "Synchronize with DID document (start using new key)"
    Write-Log "Step 4: Starting — Synchronize with DID document"

    Write-Host "  WARNING: This step is irreversible. Once synchronized, the authority" -ForegroundColor Red
    Write-Host "  will sign with the new P-256 key. There is no API to revert to P-256K." -ForegroundColor Red
    Write-Host ""

    try {
        Write-Info "Calling POST .../didInfo/synchronizeWithDidDocument"
        Write-Info "This validates Key Vault and the public did.json match, then activates the new key."

        try {
            $step4Result = Invoke-VerifiedIdApi -Method POST `
                -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId/didInfo/synchronizeWithDidDocument" `
                -AccessToken $accessToken
        }
        catch {
            $statusCode = Get-HttpStatusCode $_
            if ($statusCode -eq 404) {
                Write-Info "Synchronize endpoint returned HTTP 404."
                Write-Info "Refreshing authority status to check if already published..."

                $refreshed = Invoke-VerifiedIdApi -Method GET `
                    -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId" `
                    -AccessToken $accessToken
                $step4Result = $refreshed
            }
            else {
                throw
            }
        }

        $docStatus = $step4Result.didModel.didDocumentStatus
        if ($docStatus -eq "published") {
            Write-Success "didDocumentStatus = 'published'."
            Write-Success "The authority is now signing with the new key."
        }
        else {
            Write-Info "didDocumentStatus = '$docStatus' (expected 'published')."
            Write-Info "The authority may need the did.json to be deployed first (Step 3)."
            Write-Info "If you have already deployed it, this may resolve on retry."
        }

        Write-Log "Step 4: Completed — didDocumentStatus = '$docStatus'"
    }
    catch {
        Write-StepFailure 4 "Failed to synchronize DID document: $($_.Exception.Message)"
        exit 1
    }

    if ($runAllSteps) {
        Confirm-Continue
        $currentStep = 5
    }
    elseif (Confirm-NextStepOrExit -CompletedStep 4) {
        $currentStep = 5
    }
    else { $currentStep = $lastStep + 1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5 — Generate well-known DID configuration
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 5) {
    Write-StepHeader 5 "Generate well-known DID configuration (did-configuration.json)"
    Write-Log "Step 5: Starting — Generate well-known DID configuration"

    try {
        $domainUrl = $selectedAuthority.didModel.linkedDomainUrls | Select-Object -First 1
        if (-not $domainUrl) {
            $domainUrl = Read-Host "  Enter the linked domain URL (e.g. https://verifiedid.contoso.com/)"
        }
        else {
            Write-Info "Using linked domain: $domainUrl"
            $override = Read-Host "  Press ENTER to use this domain or type a different URL"
            if ($override) { $domainUrl = $override }
        }

        Write-Info "Calling POST .../generateWellknownDidConfiguration with domainUrl = $domainUrl"
        $step5Result = Invoke-VerifiedIdApi -Method POST `
            -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId/generateWellknownDidConfiguration" `
            -AccessToken $accessToken `
            -Body @{ domainUrl = $domainUrl }

        $didConfigPath = Join-Path $OutputDir "did-configuration.json"
        $configContent = $step5Result | ConvertTo-Json -Depth 20
        Set-Utf8NoBomContent -Path $didConfigPath -Content $configContent

        Write-Success "DID configuration generated and saved."
        Write-Host "  File: $didConfigPath" -ForegroundColor Gray
        Write-Info "This confirms the new signing key is active (the configuration is signed with P-256)."
        Write-Log "Step 5: Completed — saved $didConfigPath"
    }
    catch {
        Write-StepFailure 5 "Failed to generate DID configuration: $($_.Exception.Message)"
        exit 1
    }

    if ($runAllSteps) {
        Confirm-Continue
        $currentStep = 6
    }
    elseif (Confirm-NextStepOrExit -CompletedStep 5) {
        $currentStep = 6
    }
    else { $currentStep = $lastStep + 1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6 — (Manual) Deploy did-configuration.json
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 6) {
    Write-StepHeader 6 "[MANUAL] Deploy did-configuration.json to your web server(s)"
    Write-Log "Step 6: Starting — Manual deploy did-configuration.json"

    $domainUrl = $selectedAuthority.didModel.linkedDomainUrls | Select-Object -First 1
    $didConfigPath = Join-Path $OutputDir "did-configuration.json"
    Write-Host "  You must deploy the file to:" -ForegroundColor White
    Write-Host "    https://<your-domain>/.well-known/did-configuration.json" -ForegroundColor Yellow
    if ($domainUrl) {
        $domainBase = $domainUrl.TrimEnd('/')
        Write-Host "    Expected URL: $domainBase/.well-known/did-configuration.json" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  The file is located at: $didConfigPath" -ForegroundColor Gray
    Write-Host ""

    Write-Log "Step 6: Waiting for manual deployment of did-configuration.json"

    $configUploaded = Read-Host "  Have you uploaded did-configuration.json to your web server? [Y/N]"
    if ($configUploaded -match '^[yY]') {
        if ($domainUrl) {
            $didConfigUrl = "$($domainUrl.TrimEnd('/'))/.well-known/did-configuration.json"
            Write-Info "Checking $didConfigUrl ..."
            try {
                $configResponse = Invoke-WebRequest -Uri $didConfigUrl -Method GET -UseBasicParsing -ErrorAction Stop
                if ($configResponse.StatusCode -eq 200) {
                    Write-Success "HTTP 200 OK — did-configuration.json is publicly accessible at $didConfigUrl"
                    Write-Log "Step 6: HTTP GET $didConfigUrl returned 200 OK"
                }
                else {
                    Write-Fail "Unexpected HTTP status: $($configResponse.StatusCode)"
                    Write-Log "Step 6: HTTP GET $didConfigUrl returned $($configResponse.StatusCode)"
                }
            }
            catch {
                Write-Fail "Could not reach $didConfigUrl — $($_.Exception.Message)"
                Write-Fail "Please verify the file is deployed and publicly accessible."
                Write-Log "Step 6: HTTP GET $didConfigUrl failed — $($_.Exception.Message)"
            }

            Write-Host ""
            Write-Host "  Please browse to the following URL and verify the new" -ForegroundColor White
            Write-Host "  did-configuration.json file is correct:" -ForegroundColor White
            Write-Host "    $didConfigUrl" -ForegroundColor Yellow
            Write-Host ""
            $configConfirmed = Read-Host "  Have you confirmed the new did-configuration.json is correct? [Y/N]"
            if ($configConfirmed -match '^[yY]') {
                Write-Success "Admin confirmed did-configuration.json is correct."
                Write-Log "Step 6: Admin confirmed did-configuration.json is correct"
            }
            else {
                Write-Info "Please verify did-configuration.json before proceeding to Step 7."
                Write-Log "Step 6: Admin did not confirm did-configuration.json"
            }
        }
        else {
            Write-Info "No linked domain found for this authority. Cannot auto-verify."
            Write-Info "Please manually verify did-configuration.json is deployed correctly."
        }
    }
    else {
        Write-Info "Please upload did-configuration.json to your web server before continuing."
        Confirm-Continue "Once did-configuration.json is deployed and publicly accessible, press ENTER to continue..."
    }

    Write-Log "Step 6: Completed — admin confirmed did-configuration.json deployed"

    if ($runAllSteps) {
        $currentStep = 7
    }
    elseif (Confirm-NextStepOrExit -CompletedStep 6) {
        $currentStep = 7
    }
    else { $currentStep = $lastStep + 1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7 — Validate well-known DID configuration
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -eq 7) {
    Write-StepHeader 7 "Validate well-known DID configuration (linked domain verification)"
    Write-Log "Step 7: Starting — Validate well-known DID configuration"

    try {
        Write-Info "Calling POST .../validateWellKnownDidConfiguration"
        Write-Info "This downloads and validates the deployed DID configuration."

        Invoke-VerifiedIdApi -Method POST `
            -Endpoint "/v1.0/verifiableCredentials/authorities/$authorityId/validateWellKnownDidConfiguration" `
            -AccessToken $accessToken

        Write-Success "Linked domain configuration validated successfully!"
        Write-Success "Linked domain status is now 'verified'."
        Write-Log "Step 7: Completed — validation successful"
    }
    catch {
        Write-StepFailure 7 "Validation failed: $($_.Exception.Message)"
        Write-Fail "Ensure did-configuration.json is correctly deployed."
        $domainUrl = $selectedAuthority.didModel.linkedDomainUrls | Select-Object -First 1
        if ($domainUrl) {
            Write-Fail "Check that the file is accessible at: $($domainUrl.TrimEnd('/.'))/.well-known/did-configuration.json"
        }
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMPLETE
# ═══════════════════════════════════════════════════════════════════════════════
if ($currentStep -le $lastStep) {
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host "  Signing key upgrade complete!" -ForegroundColor Green
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Authority  : $authorityName" -ForegroundColor White
    Write-Host "  DID        : $($selectedAuthority.didModel.did)" -ForegroundColor White
    Write-Host "  New Key    : P-256 (FIPS compliant)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Saved files:" -ForegroundColor Gray
    $didJsonPath = Join-Path $OutputDir "did.json"
    $didConfigPath = Join-Path $OutputDir "did-configuration.json"
    Write-Host "    - $didJsonPath" -ForegroundColor Gray
    Write-Host "    - $didConfigPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Log file: $($script:LogFile)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Post-upgrade notes:" -ForegroundColor Yellow
    Write-Host "    - New issuance and presentation requests now use the P-256 key." -ForegroundColor Gray
    Write-Host "    - Previously issued credentials (signed with P-256K) continue to" -ForegroundColor Gray
    Write-Host "      work since the old key remains in the DID document." -ForegroundColor Gray
    Write-Host "    - Once all old credentials expire or are reissued, you can remove" -ForegroundColor Gray
    Write-Host "      the old P-256K keys from Key Vault and regenerate did.json." -ForegroundColor Gray
    Write-Host ""

    Write-Log "=== Signing key upgrade completed successfully ==="
}
