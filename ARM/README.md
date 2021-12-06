---
page_type: sample
languages:
- powershell
- ARM template
products:
- active-directory
description: "ARM template to configure your Verifiable Credential service"
urlFragment: "active-directory-verifiable-credentials"
---

# Verifiable Credentials Code Samples

This sample demonstrates how to setup and configure Microsoft's Azure Active Directory Verifiable Credentials preview using powershell and an ARM template. 

## About these samples

Welcome to Azure Active Directory Verifiable Credentials. The documentation has a tutorial [https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant) for setting up the Verifiable Credential service step by step, but in this sample, we'll show you how to automate the setup and configuration of your environment using [ARM templates](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/overview).

> **Important**: Azure Active Directory Verifiable Credentials is currently in public preview and this template is provided as-is.

The tutorial describes these steps to configure your Azure AD tenant so it can use this credentials service.

- Set up a service principal
- Create a key vault in Azure Key Vault
- Register an application in Azure AD
- Set up the Verifiable Credentials service

The following diagram illustrates the Azure AD Verifiable Credentials architecture and the component you configure.

![Diagram that illustrates the Azure AD Verifiable Credentials architecture.](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/media/verifiable-credentials-configure-tenant/verifiable-credentials-architecture.png)

## Prerequisites

- Sign up for [Azure Active Directory Premium editions](https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-get-started-premium) or join the [Microsoft 365 Developer Program](https://aka.ms/o365devprogram) and create a time limited sandbox tenant.
- If you don't have Azure subscription, [create one for free](https://azure.microsoft.com/free/?WT.mc_id=A261C142F). The subscription must have the above Azure AD tenant as its directory. If it doesn't, you need to [switch directory](https://docs.microsoft.com/en-us/azure/role-based-access-control/transfer-subscription) for the subscription. 
- Ensure that you have the [global administrator](https://docs.microsoft.com/en-us/azure/active-directory/roles/permissions-reference#global-administrator) permission for the directory you want to configure.
- Ensure that you have [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell) 7.0.6 LTS-x64, PowerShell 7.1.3-x64, or later installed. 
- Ensure that you have the [Azure Az](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-6.6.0) Powershell modeule installed.

These scripts work on Windows, Mac and Linux, given you have installed the above powershell modules on your machine.

## Set up a service principal, create a key vault and set access policies for the key vault

These three manual steps in the turorial is replaced by the powershell script [deploy-aadvc.ps1](deploy-aadvc.ps1) and the ARM template [ARM-Template-VC.json](ARM-Template-VC.json).

You run the powershell like this (please replace _all_ parameters with your values):

```powershell
./deploy-aadvc.ps1 -TenantId "<YOURTENANTID>" `
                   -SubscriptionId "<YOURSUBSCRIPTIONGUID>" `
                   -ResourceGroupName "vc-rg" `
                   -Location "West Europe" `
                   -KeyVaultName "myaadvckvname" `
                   -StorageAccountName "myaadvcstgname"
``` 

The powershell script will:
- Check that the `Verifiable Credential Issuer Service` (VCIS) exists in the Azure AD tenant. 
- Sets up the [Request API services princpial](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant#set-up-a-service-principal)
- Creates your resource group in your Azure subscription
- Deploys the ARM template [ARM-Template-VC.json](ARM-Template-VC.json)
- Adds you (the user signed in and running the script) and the Verifiable Credentials Issuer Service (VCIS) to the role `Storage Blob Data Reader` so you can upload Rules & Display files, and so VCIS can access them.

The ARM template creates the Azure KeyVault instance and adds the VCIS service principal, the Request API service principal and you (the user signed in and running the script) to an KeyVault Access Policy, as described in the [tutorial here](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant#create-a-key-vault). It also creates the Azure Storage Account and the blob container needed for storing the Rules and the Display files for a Verifiable Credential.

The powershell script will run for just a minute, but the actual deployment will take som 5-8 minutes to complete. 
After this part is completed, you can create your first Verifiable Credentials credential and edit/upload the Rules and Display file. In order to run the sample to test issuance and presentation of the Verifiable Credentials credential, you need to complete the next step and register an application.
 
## Register an application in Azure AD

Note - You need to perform this step before running a sample. You do not need to perform this step before creating your Verifiable Credentials credential and edit/upload the Rules and Display file.

As explained in the tutorial [https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant#register-an-application-in-azure-ad](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant#register-an-application-in-azure-ad), Azure AD Verifiable Credentials Request Service needs to be able to get access tokens to issue and verify. To get access tokens, register a web application and grant API permission for the API Verifiable Credential Request Service that you set up in the previous step.

```powershell
./create-aadvc-cred-app.ps1 -TenantId "<YOURTENANTID>" `
                   -SubscriptionId "<YOURSUBSCRIPTIONGUID>" `
                   -ResourceGroupName "vc-rg" `
                   -KeyVaultName "myaadvckvname" `
                   -VCCredentialsApp "VC-cred-app"
```
The script will register the application and add it to the KeyVault Access Policy, but you need to manually go to the Azure portal and add and grant the required permisions for the application, as explained [here](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant#grant-permissions-to-get-access-tokens).

**Add permission**

![Add App API permissions](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/media/verifiable-credentials-configure-tenant/add-app-api-permissions.png)

**Select APIs my organization uses**

![Search for the Service Principal](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/media/verifiable-credentials-configure-tenant/add-app-api-permissions-select-service-principal.png)

**Choose Application Permission and expand VerifiableCredential.Create.All**

![Add permission VerifiableCredential.Create.All](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/media/verifiable-credentials-configure-tenant/add-app-api-permissions-verifiable-credentials.png)

The script will end with outputting a direct link you can use in the browser. It will also output details you need to update before running the samples.

```powershell
******************************************************************************
* Manual step you need to complete
******************************************************************************
1. Go to this url
https://portal.azure.com/7d1ee427-...bb74#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/CallAnAPI/appId/ac8809a0-...da9/objectId/1d70629e-...d710/isMSAApp/

2. Click +Add permission
3. Click APIs my organization uses
4. Search for Verifiable Credential Request Service and select it
5. Check VerifiableCredential.Create.All and click Add permissions
6. Click Grant admin consent

For appsettings.json and/or config.json files in the samples, these are values you need - Save them!
{
        "azTenantId": "7d1ee427-...bb74",
        "azClientId": "ac8809a0-...da9",
        "azClientSecret": "ZQ...IA",
}
``` 
## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
