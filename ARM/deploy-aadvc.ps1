param (
    [Parameter(Mandatory=$true)][string]$SubscriptionId = "",                       # the guid of the Azure subscription
    [Parameter(Mandatory=$true)][Alias('t')][string]$TenantId = "",                 # the guid of the tenant
    [Parameter(Mandatory=$true)][Alias('r')][string]$ResourceGroupName = "",        # RG - either existing or the name to create
    [Parameter(Mandatory=$true)][Alias('l')][string]$Location = "",                 # "West Europe" etc
    [Parameter(Mandatory=$true)][Alias('k')][string]$KeyVaultName = "",             # name of your KV resource
    [Parameter(Mandatory=$true)][Alias('s')][string]$StorageAccountName = "",       # name of your storage account - Nothing but aplhanumeric chars
    [Parameter(Mandatory=$false)][Alias('c')][string]$StorageAccountContainerName = "vcstg"
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

# The user/admin who runs this script. We need it to set KeyVault access policies
$user = Get-AzADUser -Mail $ctx.Account.Id

function PrintMsg( $msg ) {  
  $buf = "".PadLeft(78,"*")
  write-host "`n$buf`n* $msg`n$buf"
}
##############################################################################################
# Get the Enterprise App for VC's. The ApplicationId will be the same across all AAD tenants, 
# the ObjectID will be unique for this tenant
$appIdVCIS = "bb2a64ee-5d29-4b07-a491-25806dc854d3"
$nameVCIS = "Verifiable Credentials Service"
PrintMsg "Verifying $nameVCIS is available"
$spVCIS = Get-AzADServicePrincipal -ApplicationId $appIdVCIS
if ( $null -eq $spVCIS ) {
    write-host "Enterprise Application missing in tenant : '$nameVCIS'`n`n" `
                "- Make sure you can see '$nameVCIS' as an Enterprise Application`n"
    exit 1
}
write-host "ServicePrincipal:`t$($spVCIS.DisplayName)`nObjectID:`t`t$($spVCIS.Id)`nAppID:`t`t`t$($spVCIS.ApplicationId)"
##############################################################################################
# Get the servicePrincipal for the Request API (should already be there)
$appIdReqAPI = "3db474b9-6a0c-4840-96ac-1fceb342124f"
$nameReqAPI = "Verifiable Credentials Service Request"
PrintMsg "Verifying $nameReqAPI is available"
$spReqAPI = Get-AzADServicePrincipal -ApplicationId $appIdReqAPI
if ( $null -eq $spReqAPI ) {
    write-host "Enterprise Application missing in tenant : '$nameReqAPI'`n`n" `
                "- Make sure you can see '$nameReqAPI' as an Enterprise Application`n"
    exit 1
}
write-host "ServicePrincipal:`t$($spReqAPI.DisplayName)`nObjectID:`t`t$($spReqAPI.Id)`nAppID:`t`t`t$($spReqAPI.ApplicationId)"

##############################################################################################
# create an Azure resource group
PrintMsg "Creating resource group $ResourceGroupName"
$rg = Get-AzResourceGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ( $null -eq $rg ) {
    $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
}

##############################################################################################
# deploy the ARM template (KeyVault + Storage Account)
$params = @{
    KeyVaultName = $KeyVaultName
    skuName = "Standard"
    AADTenantId = $ctx.Tenant.Id
    AdminUserObjectId = $user.Id
    VerifiableCredentialsIssuerServicePrincipalObjectId = $spVCIS.Id
    VerifiableCredentialsRequestServicePrincipalObjectId = $spReqAPI.Id
    StorageAccountName = $StorageAccountName
    StorageAccountContainerName = $StorageAccountContainerName
}

$file = "$((get-location).Path)\ARM-Template-VC.json"
PrintMsg "Deploying ARM template $file"
New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $file -TemplateParameterObject $params

# set the appropriate reader permission for the VS service principal on the storage account so that it can 
# read the Rules & Display json files
$roleName = "Storage Blob Data Reader"
PrintMsg "Assigning $roleName roles to user and $($spVCIS.DisplayName)"
$scope = "/subscriptions/$($ctx.Subscription.Id)/resourcegroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName/blobServices/default/containers/$StorageAccountContainerName"
$roles = Get-AzRoleAssignment -Scope $scope

if (!($roles | where {$_.DisplayName -eq $roleName})) {
    New-AzRoleAssignment -ObjectId $spVCIS.Id -RoleDefinitionName $roleName -Scope $scope   # Verifiable Credentials Issuer app
    New-AzRoleAssignment -ObjectId $user.Id -RoleDefinitionName $roleName -Scope $scope     # you, the admin
}
