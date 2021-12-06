param (
    [Parameter(Mandatory=$true)][string]$SubscriptionId = "",                       # the guid of the Azure subscription
    [Parameter(Mandatory=$true)][Alias('t')][string]$TenantId = "",                 # the guid of the tenant
    [Parameter(Mandatory=$true)][Alias('r')][string]$ResourceGroupName = "",        # RG - either existing or the name to create
    [Parameter(Mandatory=$true)][Alias('k')][string]$KeyVaultName = "",             # name of your KV resource
    [Parameter(Mandatory=$true)][Alias('a')][string]$VCCredentialsApp = "VC-cred-app"
    )

if ((Get-Module -ListAvailable -Name "Az.Accounts") -eq $null) {  
  Install-Module -Name "Az.Accounts" -Scope CurrentUser 
}
if ((Get-Module -ListAvailable -Name "Az.Resources") -eq $null) {  
  Install-Module "Az.Resources" -Scope CurrentUser 
}

$ctx = Get-AzContext
if ( $null -eq $ctx ) {
    Connect-AzAccount -TenantId $TenantId -Subscription $SubscriptionId
    $ctx = Get-AzContext
}

function PrintMsg( $msg ) {  
  $buf = "".PadLeft(78,"*")
  write-host "`n$buf`n* $msg`n$buf"
}
##############################################################################################
# create the VC Credentials app - used to get get an access_token via client credentials for the Request API
PrintMsg "Creating your VC Credentials app $VCCredentialsApp"
$createdApp = $false
$spVCCredentialsApp = Get-AzADServicePrincipal -SearchString $VCCredentialsApp 
if ( $null -eq $spVCCredentialsApp ) {
  $appSecret = [Convert]::ToBase64String( [System.Text.Encoding]::Unicode.GetBytes( (New-Guid).Guid ) ) # create an app secret
  $SecureStringPassword = ConvertTo-SecureString -AsPlainText -Force -String $appSecret 
  $app = New-AzADApplication -DisplayName $VCCredentialsApp -ReplyUrls @("https://localhost","vcclient://openid") -Password $SecureStringPassword
  $spVCCredentialsApp = ($app | New-AzADServicePrincipal)
  write-host "Application:`t`t$VCCredentialsApp`nObjectID:`t`t$($app.ObjectId)`nAppID:`t`t$($VCCredentialsApp.ApplicationId)`nSecret:`t`t`t$appSecret"
  $createdApp = $true 
}
write-host "ServicePrincipal:`t$($spVCCredentialsApp.DisplayName)`nObjectID:`t`t$($spVCCredentialsApp.Id)`nAppID:`t`t`t$($spVCCredentialsApp.ApplicationId)"

##############################################################################################
# Adding VC Credentials app to KeyVault Access Policies
if ( $true -eq $createdApp ) {
  PrintMsg "Adding $VCCredentialsApp to KeyVault Access Policies"
  $kvap = Set-AzKeyVaultAccessPolicy -ResourceGroupName $ResourceGroupName  -VaultName $KeyVaultName -ObjectId $spVCCredentialsApp.Id -PermissionsToKeys Get,Create,Sign
}

##############################################################################################
# You must complete this step manually in the portal 
PrintMsg "Manual step you need to complete"

$clientPortalUrl = "https://portal.azure.com/$TenantId#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/CallAnAPI/appId/"+$spVCCredentialsApp.ApplicationId+"/objectId/"+$spVCCredentialsApp.Id+"/isMSAApp/"

write-host "1. Go to this url`n$clientPortalUrl`n"
write-host "2. Click +Add permission"
write-host "3. Click APIs my organization uses"
write-host "4. Search for Verifiable Credential Request Service and select it"
write-host "5. Check VerifiableCredential.Create.All and click Add permissions"
write-host "6. Click Grant admin consent"

write-host "`n`nFor appsettings.json and/or config.json files in the samples, these are values you need - Save them!"
write-host "{
`t`"azTenantId`": `"$TenantId`",
`t`"azClientId`": `"$($spVCCredentialsApp.ApplicationId)`",
`t`"azClientSecret`": `"$appSecret`",
}"