<#
This script migrates Credential Contracts off from Azure Storage to the new model.
The actual update, at the end of this file, is commented out so you can make test runs.
Uncomment that section when you are ready to migrate
#>
param (
    [Parameter(Mandatory=$true)][string]$TenantId,
    [Parameter(Mandatory=$True)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$StorageAccessKey
)

##########################################################################################################
# just print the 70's style header
##########################################################################################################
function PrintMsg($msg) {
    $banner = "".PadLeft(78,"*")
    write-host "`n$banner`n* $msg`n$banner"
}

##########################################################################################################
# download a blob from Azure storage using the shared access key
##########################################################################################################
function DownloadBlobFromStorage (
    [Parameter(Mandatory=$true)][string]$ResourceUrl,
    [Parameter(Mandatory=$true)][string]$AccessKey
    )
{
    $ifMac = ""
    if ( $env:PATH -imatch "/usr/bin" ) { $ifMac = "0" }
    $uri = New-Object System.Uri -ArgumentList $resourceUrl
    $StorageAccountName = $resourceUrl.Split("/")[2].Split(".")[0]
    $headers = @{"x-ms-version"="2014-02-14"}
    $headers.Add("x-ms-date", $(([DateTime]::UtcNow.ToString('r')).ToString()) )
    $dataToMac = [System.Text.Encoding]::UTF8.GetBytes("GET`n`n`n$IfMac`n`n`n`n`n`n`n`n`nx-ms-date:$($headers["x-ms-date"])`nx-ms-version:$($headers["x-ms-version"])`n/$StorageAccountName$($uri.AbsolutePath)")
    $signature = [System.Convert]::ToBase64String((new-object System.Security.Cryptography.HMACSHA256((,[System.Convert]::FromBase64String($AccessKey)))).ComputeHash($dataToMac))   
    $headers.Add("Authorization", "SharedKey " + $StorageAccountName + ":" + $signature);
    return Invoke-RestMethod -Uri $ResourceUrl -Method "GET" -headers $headers
}

##########################################################################################################
# login to tenant using device code flow
##########################################################################################################
function Connect-AzADVCTenantViaDeviceFlow( 
        [Parameter(Mandatory=$True)][string]$ClientId,
        [Parameter(Mandatory=$True)][string]$TenantId,
        [Parameter()][string]$Scope = "6a8b4b39-c021-437c-b060-5a14a3fd65f3/full_access",                
        [Parameter(DontShow)][int]$Timeout = 300 # Timeout in seconds to wait for user to complete sign in process
)
{
    if ( !($Scope -imatch "offline_access") ) { $Scope += " offline_access"} # make sure we get a refresh token
    $retVal = $null
    try {
        $DeviceCodeRequest = Invoke-RestMethod -Method "POST" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
                                                -Body @{ client_id=$ClientId; scope=$scope; } -ContentType "application/x-www-form-urlencoded"
        Write-Host $DeviceCodeRequest.message -ForegroundColor Yellow
        $url = $DeviceCodeRequest.verification_uri 
        Set-Clipboard -Value $DeviceCodeRequest.user_code
        if ( $env:PATH -imatch "/usr/bin" ) {
            $ret = [System.Diagnostics.Process]::Start("/usr/bin/open","$url")
        } else {
            $browser = (Get-ItemProperty HKCU:\Software\Microsoft\windows\Shell\Associations\UrlAssociations\http\UserChoice).ProgId
            $pgm = "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
            $params = "-inprivate -new-window"
            switch( $browser.Replace("HTML", "").Replace("URL", "").ToLower() ) {        
                "firefox" { 
                    $pgm = "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
                    $params = "-private -new-window"
                } 
                "chrome" { 
                    $pgm = "$env:ProgramFiles (x86)\Google\Chrome\Application\chrome.exe"
                    $params = "--incognito --new-window"
                } 
            }      
            $ret = [System.Diagnostics.Process]::Start($pgm,"$params $url")
        }
        $TimeoutTimer = [System.Diagnostics.Stopwatch]::StartNew()
        while ([string]::IsNullOrEmpty($TokenRequest.access_token)) {
            if ($TimeoutTimer.Elapsed.TotalSeconds -gt $Timeout) {
                throw 'Login timed out, please try again.'
            }
            $TokenRequest = try {
                Invoke-RestMethod -Method "POST" -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                                    -Body @{ grant_type="urn:ietf:params:oauth:grant-type:device_code"; code=$DeviceCodeRequest.device_code; client_id=$ClientId} `
                                    -ErrorAction Stop
            }
            catch {
                $Message = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($Message.error -ne "authorization_pending") {
                    throw
                }
            }
            Start-Sleep -Seconds 2
        }
        $retVal = $TokenRequest
    }
    finally {
        try {
            $TimeoutTimer.Stop()
        }
        catch {
            # We don't care about errors here
        }
    }
    $global:authHeader =@{ 'Content-Type'='application/json'; 'Authorization'=$retval.token_type + ' ' + $retval.access_token }
    #return $retval.access_token
}

# transform claims mapping into new format
function MigrateClaimsMapping( $claimsMapping ) {
    $mapping = ""
    foreach( $claims in $claimsMapping ) {
        $sep = ""
        foreach ($claim in $claims.PSObject.Properties) { 
            $indexed = "false"
            if ( $claim.Value.indexed -eq $True ) { $indexed = "true"}
            $mapping += "$sep{ `"outputClaim`": `"$($claim.Name)`", `"required`": true, `"inputClaim`": `"$($claim.Value.claim)`", `"indexed`": $indexed }"
            $sep = ",`n              "
        }
    }
    return $mapping
}

##########################################################################################################
# Main script
##########################################################################################################


write-host "Signing in to Tenant $TenantId..."
Connect-AzADVCTenantViaDeviceFlow -TenantId $tenantId -ClientId $clientId

$baseUrl="https://beta.did.msidentity.com/$tenantID/api/portable/v1.0/admin"

write-host "Retrieving VC Credential Contracts for tenant $tenantId..."
$contracts = Invoke-RestMethod -Method "GET" -Headers $global:authHeader -Uri "$baseUrl/contracts" -ErrorAction Stop

# enumerate all contracts 
foreach( $contract in $contracts ) {
    # only process old contracts that uses Azure Storage for display & rules files
    if ( !($contract.rulesFile -and $contract.displayFile) ) {
        PrintMsg "$($contract.contractName) - already good"
        continue
    }

    PrintMsg "$($contract.contractName) - converting..."

    write-host "Downloading " $contract.rulesFile
    $rules = DownloadBlobFromStorage -ResourceUrl $contract.rulesFile -AccessKey $StorageAccessKey
    write-host "Downloading " $contract.displayFile
    $display = DownloadBlobFromStorage -ResourceUrl $contract.displayFile -AccessKey $StorageAccessKey

    if ( !$rules -or !$display ) {
        write-host "Failed to get display & rules files"
        continue
    }

    write-host "Converting display definitions..."
    $sep = ""
    $displayClaims = ""
    foreach( $claim in $display.default.claims.PSObject.Properties ) {
        $displayClaims += "$sep{ `"claim`": `"$($claim.Name)`", `"label`": `"$($claim.Value.label)`", `"type`": `"$($claim.Value.type)`" }"
        $sep = ",`n"
    }
    $newDisplay = @"
"displays": [
    {
    "locale": "$($display.default.locale)",
    "card": $($display.default.card | ConvertTo-Json),
    "consent": $($display.default.consent | ConvertTo-json),
    "claims": [
        $displayClaims
    ]
    }
  ]
"@

    write-host "Converting rules definitions..."
    if ( $rules.attestations.idTokens ) {
        $newRules = "`"idTokens`": ["
        # old model didn't separate idTokens from idTokenHints, so we find the difference in the configuration
        foreach( $idToken in $rules.attestations.idTokens ) {
            if ( $idToken.configuration -eq "https://self-issued.me" ) {
                $newRules = "`"idTokenHints`": ["
                break
            }
        }
        foreach( $idToken in $rules.attestations.idTokens ) {
            $sep = ""
            $newRules += "$sep{ "
            # idTokens - add configuration section (not needed anymore for idTokenHints)
            if ( $idToken.configuration -ne "https://self-issued.me" ) {
                $newRules += "`"clientId`": `"$($idToken.client_id)`",`"configuration`": `"$($idToken.configuration)`", `"redirectUri`": `"$($idToken.redirect_uri)`", `"scope`": `"$($idToken.scope)`", "
            }
            $mapping = MigrateClaimsMapping $idToken.mapping
            $newRules += "`"mapping`": [ $mapping ], `"required`": true }"
            $sep = ",`n"
        }
        $newRules += "]"
    }

    if ( $rules.attestations.presentations ) {
        foreach( $presentation in $rules.attestations.presentations ) {
            $mapping = MigrateClaimsMapping $presentation.mapping
            $presentation.mapping = ("{ `"mapping`": [ $mapping ], `"required`": true }" | ConvertFrom-json).mapping
        }
        $newRules = ($rules.attestations | ConvertTo-json -Depth 15)
        $newRules = $newRules.Substring(1, $newRules.Length-2)
    }

    if ( $rules.attestations.accessTokens ) {
        $newRules = "`"accessTokens`": ["
        foreach( $accessToken in $rules.attestations.accessTokens ) {
            $sep = ""
            $mapping = MigrateClaimsMapping $accessToken.mapping
            $newRules += "$sep{ `"mapping`": [ $mapping ], `"required`": true }"
            $sep = ",`n"
        }
        $newRules += "]"
    }

    if ( $rules.attestations.selfIssued ) {
        $mapping = MigrateClaimsMapping $rules.attestations.selfIssued.mapping
        $newRules = "`"selfIssued`": { `"mapping`": [ $mapping ], `"required`": true }"
    }
      
    $newContract = @"
{
  "id": "$($contract.id)",
  "tenantId": "$($contract.tenantId)",
  "contractName": "$($contract.contractName)",
  "issuerId": "$($contract.issuerId)",
  "status": "$($contract.status)",
  "issueNotificationEnabled": $($contract.issueNotificationEnabled.ToString().ToLower()),
  "issueNotificationAllowedToGroupOids": [],
  "availableInVcDirectory": $($contract.availableInVcDirectory.ToString().ToLower()),
  "rules": {
    "attestations": {
        $newRules
    }
  },
  $newDisplay
}
"@
    write-host "New Contract..."
    write-host ($newContract | ConvertFrom-json | ConvertTo-json -Depth 15 )

# uncomment this to do the actual update    
<# 
    write-host "Updating Contract..."
    $newContract = ($newContract | ConvertFrom-json | ConvertTo-json -Depth 15 -Compress)
    Invoke-RestMethod -Method "PUT" -Uri "$baseUrl/contracts/$($contract.Id)" -Headers $global:authHeader -Body $newContract -ContentType "application/json" -ErrorAction Stop
#>

} # foreach
