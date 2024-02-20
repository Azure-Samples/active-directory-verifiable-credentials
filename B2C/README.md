# Entra Verified ID integration with Azure AD B2C

The B2C Custom Policies have moved [here](https://github.com/Azure-Samples/active-directory-verifiable-credentials-dotnet/tree/main/3-asp-net-core-api-b2c/B2C) to be part of the ASPNet Core sample code. 

<<<<<<< HEAD
Please check out the new [Microsoft Entra ID for customers](https://learn.microsoft.com/en-us/entra/external-id/customers/overview-customers-ciam) if considering using Azure AD B2C.
=======
**UPDATE 2022-06-30** Added B2C Policy that presents a QR code on the signin page so you can signin with VC already there.

**UPDATE 2022-05-10** You need to change your existing Rules files since the claim `sub` is now a restricted claim and will no longer work. You need to change it to `oid`. See `oid` in this README file below.

## What you will be able to do with the solution in this repository is:

- Issue Verifiable Credentials for accounts in your Azure AD B2C tenant
- Issue Verifiable Credentials during signup of new users in your Azure AD B2C tenant (new)
- Signin to B2C with your Verifiable Credentials by scanning a QR code
 
![Scan QR code](/ReadmeFiles/b2c-vc-scan-qr-code.png)

## What you need to deploy to test this sample

- Deploy your Azure AD Verifiable Credentials
- Deploy one of the dotnet or nodejs samples and verify that work with the sample VCs 
- Deploy your Azure AD B2C tenant and create your B2C test user
- Create your VC credentials that uses your B2C tenant for issuance of VCs
- Edit and upload the B2C Custom Policies in the [policies](./policies) folder
- Reconfigure the sample to use your B2C credentials
 
## Deploy your Azure AD Verifiable Credentials

To deploy your Azure AD Verifiable Credentials environment, you can either follow the tutorial in the documentation [https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant) or use the ARM template provided in this github repo [ARM](/ARM).

## Deploy one of the samples and verify that work with the sample VCs

Pick a sample [here](https://github.com/Azure-Samples/active-directory-verifiable-credentials/#about-these-samples) of your prefered language and follow the respective instructions for getting it to work. It is important that you get the sample to work before you go any further since it will be easier to troubleshoot if you know that the sample works with your Azure AD Verifiable Credentials deployment.

Once you have the sample app working, and you can issue and verify the sample credential, you can verify that it also will respond to the API that Azure AD B2C will call. To do this, you need the `id` (guid) that is unique for the browser session. You can either find it in the trace output in the console window of the running sample app, or you can find it in the browsers developer console (F12 in Edge/Chrome, then Console) _after_ you have completed a verification in the browser. To test the B2C API, run the below in a powershell prompt (change the `$id` and `$ngrokUrl` values first).

```powershell
$id="2fb8dce0-9d69-481a-8a2b-f64b684a8aae"
$ngrokUrl="https://df4a-256-714-401-356.ngrok.io"
$response = Invoke-WebRequest -Uri "$ngrokUrl/api/verifier/presentation-response-b2c" `
                              -Method Post -Body (@{id=$id;}|ConvertTo-json) -ContentType "application/json"
$response.Content | ConvertFrom-json
```

## Deploy your Azure AD B2C tenant

Follow this tutorial on how to create your Azure AD B2C tenant [https://docs.microsoft.com/en-us/azure/active-directory-b2c/tutorial-create-tenant](https://docs.microsoft.com/en-us/azure/active-directory-b2c/tutorial-create-tenant).

Then, you need to make the B2C tenant ready for B2C Custom Policies via following this tutorial [https://docs.microsoft.com/en-us/azure/active-directory-b2c/custom-policy-get-started?tabs=applications#custom-policy-starter-pack](https://docs.microsoft.com/en-us/azure/active-directory-b2c/custom-policy-get-started?tabs=applications#custom-policy-starter-pack). Make sure you deploy the Custom Policy Starter Pack and signup a test user.

## Create your credentials that uses your B2C tenant for issuance of VCs

Create your Rules & Display file for the credential you will be using for the B2C integration.

For the files, replace the values in `<...>` for your values and make sure the `configuration` points to the metadata of your deployed B2C Custom Policy.
After you have saved the files, upload them to the storage account that was created with your Azure AD Verifiable Credentials deployment. The documentation for how to do that is found here [https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-issuer#upload-the-configuration-files](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-issuer#upload-the-configuration-files).

**Display file**
```json
{
  "locale": "en-US",
  "card": {
    "title": "B2CverifiedAccount",
    "issuedBy": "b2ctenant",
    "backgroundColor": "#B8CEC1",
    "textColor": "#ffffff",
    "logo": {
      "uri": "https://cljungdemob2c.blob.core.windows.net/uxcust/templates/images/snoopy-small.jpg",
      "description": "B2C Logo"
    },
    "description": "Use your verified credential card to prove you have a B2C account."
  },
  "consent": {
    "title": "Do you want to get your B2C VC card?",
    "instructions": "Sign in with your account to get your card."
  },
  "claims": [
    {
      "claim": "vc.credentialSubject.firstName",
      "label": "First name",
      "type": "String"
    },
    {
      "claim": "vc.credentialSubject.lastName",
      "label": "Last name",
      "type": "String"
    },
    {
      "claim": "vc.credentialSubject.country",
      "label": "Country",
      "type": "String"
    },
    {
      "claim": "vc.credentialSubject.oid",
      "label": "oid",
      "type": "String"
    },
    {
      "claim": "vc.credentialSubject.tid",
      "label": "tid",
      "type": "String"
    },
    {
      "claim": "vc.credentialSubject.displayName",
      "label": "displayName",
      "type": "String"
    },
    {
      "claim": "vc.credentialSubject.username",
      "label": "username",
      "type": "String"
    }
  ]
}
```


**Rules file for id_token flow**
```json
{
  "attestations": {
    "idTokens": [
      {
        "clientId": "<your-app-id>",
        "configuration": "https://yourtenant.b2clogin.com/yourtenant.onmicrosoft.com/B2C_1A_susi/v2.0/.well-known/openid-configuration",
        "redirectUri": "vcclient://openid",
        "scope": "openid",
        "mapping": [
          {
            "outputClaim": "displayName",
            "required": true,
            "inputClaim": "name",
            "indexed": false
          },
          {
            "outputClaim": "oid",
            "required": true,
            "inputClaim": "oid",
            "indexed": false
          },
          {
            "outputClaim": "tid",
            "required": true,
            "inputClaim": "tid",
            "indexed": false
          },
          {
            "outputClaim": "username",
            "required": true,
            "inputClaim": "email",
            "indexed": true
          },
          {
            "outputClaim": "lastName",
            "required": true,
            "inputClaim": "family_name",
            "indexed": false
          },
          {
            "outputClaim": "firstName",
            "required": true,
            "inputClaim": "given_name",
            "indexed": false
          },
          {
            "outputClaim": "country",
            "required": true,
            "inputClaim": "ctry",
            "indexed": false
          }
        ],
        "required": true
      }
    ]
  },
  "validityInterval": 2592000,
  "vc": {
    "type": [
      "<NameOfYourCredential>"
    ]
  }
}
```

**Rules file for id_token_hint flow**
```json
{
  "attestations": {
    "idTokenHints": [
      {
        "mapping": [
          {
            "outputClaim": "displayName",
            "required": true,
            "inputClaim": "displayName",
            "indexed": false
          },
          {
            "outputClaim": "oid",
            "required": true,
            "inputClaim": "oid",
            "indexed": false
          },
          {
            "outputClaim": "tid",
            "required": true,
            "inputClaim": "tid",
            "indexed": false
          },
          {
            "outputClaim": "username",
            "required": true,
            "inputClaim": "username",
            "indexed": true
          },
          {
            "outputClaim": "lastName",
            "required": true,
            "inputClaim": "lastName",
            "indexed": false
          },
          {
            "outputClaim": "firstName",
            "required": true,
            "inputClaim": "firstName",
            "indexed": false
          },
          {
            "outputClaim": "country",
            "required": true,
            "inputClaim": "country",
            "indexed": false
          }
        ],
        "required": true
      }
    ]
  },
  "validityInterval": 2592000,
  "vc": {
    "type": [
      "<NameOfYourCredential>"
    ]
  }
}
```

## Configure and upload the B2C Custom Policies

The policies for the B2V+VC integration are B2C Custom Policies with custom html, which is needed to generate the QR code. You therefor need to first upload the html files to your Azure Storage Account and then edit and upload the xml policy files.

| File   | Description |
| -------- | ----------- |
| TrustFrameworkExtensionsVC.xml | Extensions for VC's to the TrustFrameworkExtensions from the Starter Pack |
| SignUpVCOrSignin.xml | Standard Signup/Signin B2C policy but that issues a VC during user signup |
| SignUpOrSignInVC.xml | Standard Signup/Signin B2C policy but with Verifiable Credentials added as a claims provider option (button) |
| SignUpOrSignInVCQ.xml | Standard Signup/Signin B2C policy but with a QR code on signin page so you can scan it already there. Signup journey ends with issue the new user a VC via the id_token_hint flow. |
| SigninVC.xml | Policy lets you signin to your B2C account via scanning the QR code and present your VC |
| SigninVCMFA.xml | Policy that uses VCs as a MFA after you've signed in with userid/password |

### Deploy the custom html

-  You can use the same storage account that you use for your VC credentials, but create a new container because you need to CORS enable it as explained [here](https://docs.microsoft.com/en-us/azure/active-directory-b2c/customize-ui-with-html?pivots=b2c-user-flow#2-create-an-azure-blob-storage-account). If you create a new storage account, you should perform step 2 through 3.1. Note that you can select `LRS` for Replication as `RA-GRS` is a bit overkill. Make sure you enable CORS for your B2C tenant.
- Download your copy of [qrcode.min.js](https://raw.githubusercontent.com/davidshimjs/qrcodejs/master/qrcode.min.js) and upload it to the container in the Azure Storage.
- Edit `selfAsserted.html` and change the `script src` reference to point to your Azure Storage location. 
- Upload the files `selfAsserted.html`, `unified.html` and `unifiedquick.html` to the container in the Azure Storage.
- Copy the full url to the files and test that you can access them in a browser. If it fails, the B2C UX will not work either. If it works, you need to update the [TrustFrameworkExtensionsVC.xml](.\policies\TrustFrameworkExtensionsVC.xml) files with the `LoadUri` references.

### Create the REST API key in the portal
The Technical Profile `REST-VC-PostIssuanceClaims`, that is used during VC innuance during user signup, is configured to use an api-key for security. Therefor, create a Policy Key in the B2C portal with the name `RestApiKey` and manually set the key value to something unique. You need to add this value to the sample app's appSettings file also.

### Edit and upload the B2C Custom Policies

Do search and replace in all the xml files in [policies](.\policies) folder for:

- `yourtenant.onmicrosoft.com` to the real name of your B2C tenant, like `contoso.onmicrosoft.com`
 
Then do the following changes to the [TrustFrameworkExtensionsVC.xml](.\policies\TrustFrameworkExtensionsVC.xml) file:

- Find `LoadUri` and replace the value of the url for `selfAsserted.html` that you uploaded in the previous step. 
- all places where `VCServiceUrl` references your deployment of the samples, like `https://df4a-256-714-401-356.ngrok.io/api/`
- all place where `ServiceUrl` references your deployment of the samples, like `https://df4a-256-714-401-356.ngrok.io/api/`

Upload the xml policy files to your B2C tenant starting with TrustFrameworkExtensionsVC.xml first. Note that you already should have uploaded the TrustFrameworkBase.xml and trustFrameworkExtensions.xml in a previous step. 

A tip here, if you use `ngrok`, is to start it and leave it running so that the hostname doesn't change after you have uploaded the B2C policy files.

## Reconfigure the sample to use your B2C credentials

Regardless which language you picked for your sample, you need to update the `issuance_request_config.json` file and the `presentation_request_config.json` file and change the `type` attribute to match the name of your VC credential.  

## Testing

Steps:

1. Run the `B2C_1A_VC_susiq` policy and sign up a new user. During the signup flow you will issue this user a VC
1. Run the `B2C_1A_VC_susiq` policy, scan the QR code and signin to your B2C account using your VC. 

![B2C+VC signin page](/ReadmeFiles/b2c-vc-signin-page.png)


The result will be an id_token that looks something like this.

![B2C+VC jwt token](/ReadmeFiles/b2c-vc-jwt-token.png)

## SocialAndLocalAccountsWithMfa changes

The B2C sample policies in this repo are created using the [SocialAndLocalAccounts](https://github.com/Azure-Samples/active-directory-b2c-custom-policy-starterpack/tree/main/SocialAndLocalAccounts). This means that if you try and use them with the [SocialAndLocalAccountsWithMfa](https://github.com/Azure-Samples/active-directory-b2c-custom-policy-starterpack/tree/main/SocialAndLocalAccountsWithMfa) version, with a different TrustFrameworkBase.xml file, then you will get errors during uploading of the policies. You need to modify these two files since the orchestration step numbers are different between the two starter pack base files. 

| File | Changes |
|------|--------|
| SignupOrSigninVCQ.xml | OrchestrationStep 7-8-9 should be changed to 9-10-11 |
| SignUpVCOrSignin.xml | OrchestrationStep 7-8-9 should be changed to 9-10-11 |
>>>>>>> ef5b587e3210e7528d8e64f2ecb5f1c8b093199a
