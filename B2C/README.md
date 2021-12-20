# Azure AD Verifiable Credentials integration with Azure AD B2C
This folder includes what you need to integrate Azure AD B2C with Verifiable Credentials. Use cases are:

## What you will be able to do with the solution in this repository is:

- Issue Verifiable Credentials for accounts in your Azure AD B2C tenant
- Signin to B2C with your Verifiable Credentials by scanning a QR code
 
![Scan QR code](/ReadmeFiles/b2c-vc-scan-qr-code.png)

## What you need to deploy to test this sample

- Deploy your Azure AD Verifiable Credentials
- Deploy one of the samples and verify that work with the sample VCs
- Deploy your Azure AD B2C tenant and create your B2C test user
- Create your VC credentials that uses your B2C tenant for issuance of VCs
- Edit and upload the B2C Custom Policies in the [policies](./policies) folder
- Reconfigure the sample to use your B2C credentials
 
## Deploy your Azure AD Verifiable Credentials

To deploy your Azure AD Verifiable Credentials environment, you can either follow the tutorial in the documentation [https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant](https://docs.microsoft.com/en-us/azure/active-directory/verifiable-credentials/verifiable-credentials-configure-tenant) or use the ARM template provided in this github repo [ARM](/ARM).

## Deploy one of the samples and verify that work with the sample VCs

Pick a sample here [here](/#about-these-samples) of your prefered language and follow the respective instructions for getting it to work. It is important that you get the sample to work before you go any further since it will be easier to troubleshoot if you know that the sample works with your Azure AD Verifiable Credentials deployment.

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

**Rules file**
```json
{
  "vc": {
    "type": [ "<NameOfYourCredential>" ]
  },
  "validityInterval": 2592000,
  "attestations": {
    "idTokens": [
      {
        "mapping": {
          "displayName": { "claim": "name" },
          "sub": { "claim": "sub" },
          "tid": { "claim": "tid" },
          "username": { "claim": "email" },
          "lastName": { "claim": "family_name" },
          "firstName": { "claim": "given_name" }
        },
        "configuration": "https://yourtenant.b2clogin.com/yourtenant.onmicrosoft.com/B2C_1A_signup_signin/v2.0/.well-known/openid-configuration",
        "client_id": "<your-app-id>",
        "scope": "openid",
        "redirect_uri": "vcclient://openid"
      }
    ]
  }
}
```

**Display file**
```json
{
    "default": {
      "locale": "en-US",
      "card": {
        "title": "<NameOfYourCredential>",
        "issuedBy": "<yourtenant>",
        "backgroundColor": "#B8CEC1",
        "textColor": "#ffffff",
        "logo": {
          "uri": "https://yourstorageaccount.blob.core.windows.net/vcimages/logo.png",
          "description": "<yourtenant> Logo"
        },
        "description": "Use your verified credential card to prove you are a B2C user."
      },
      "consent": {
        "title": "Do you want to get your B2C VC card?",
        "instructions": "Sign in with your account to get your card."
      },
      "claims": {
        "vc.credentialSubject.firstName": {
          "type": "String",
          "label": "First name"
        },
        "vc.credentialSubject.lastName": {
          "type": "String",
          "label": "Last name"
        },
        "vc.credentialSubject.sub": {
          "type": "String",
          "label": "sub"
        },
        "vc.credentialSubject.tid": {
          "type": "String",
          "label": "tid"
        },
        "vc.credentialSubject.displayName": {
          "type": "String",
          "label": "displayName"
        },
        "vc.credentialSubject.username": {
          "type": "String",
          "label": "username"
        }
      }
    }
  }
```

## Configure and upload the B2C Custom Policies

The policies for the B2V+VC integration are B2C Custom Policies with custom html, which is needed to generate the QR code. You therefor need to first upload the html files to your Azure Storage Account and then edit and upload the xml policy files.

| File   | Description |
| -------- | ----------- |
| TrustFrameworkExtensionsVC.xml | Extensions for VC's to the TrustFrameworkExtensions from the Starter Pack |
| SignUpOrSignInVC.xml | Standard Signup/Signin B2C policy but with Verifiable Credentials added as a claims rpovider option (button) |
| SigninVC.xml | Policy lets you signin to your B2C account via scanning the QR code and present your VC |
| SigninVCMFA.xml | Policy that uses VCs as a MFA after you've signed in with userid/password |

### Deploy the custom html

-  You can use the same storage account that you use for your VC credentials, but create a new container because you need to CORS enable it as explained [here](https://docs.microsoft.com/en-us/azure/active-directory-b2c/customize-ui-with-html?pivots=b2c-user-flow#2-create-an-azure-blob-storage-account). If you create a new storage account, you should perform step 2 through 3.1. Note that you can select `LRS` for Replication as `RA-GRS` is a bit overkill.
- Upload the file `selfAsserted.html` to the container in the Azure Storage.
- Copy the full url to the file and test that you can access them in a browser. If it fails, the B2C UX will not work either. If it works, you need to update the [TrustFrameworkExtensionsVC.xml](.\policies\TrustFrameworkExtensionsVC.xml) file as the `LoadUri` reference.

### Edit and upload the B2C Custom Policies

Do search and replace in all the xml files in [policies](.\policies) folder for:

- `yourtenant.onmicrosoft.com` to the real name of your B2C tenant, like `contoso.onmicrosoft.com`
 
Then do the following changes to the [TrustFrameworkExtensionsVC.xml](.\policies\TrustFrameworkExtensionsVC.xml) file:

- Find `LoadUri` and replace the value of the url for `selfAsserted.html` that you uploaded in the previous step. 
- two places where `VCServiceUrl` references your deployment of the samples, like `https://df4a-256-714-401-356.ngrok.io/api/verifier`
- one place where `ServiceUrl` references your deployment of the samples, like `https://df4a-256-714-401-356.ngrok.io/api/verifier`

Upload the xml policy files to your B2C tenant starting with TrustFrameworkExtensionsVC.xml first. Note that you already should have uploaded the TrustFrameworkBase.xml and trustFrameworkExtensions.xml in a previous step. 

A tip here, if you use `ngrok`, is to start it and leave it running so that the hostname doesn't change after you have uploaded the B2C policy files.

## Reconfigure the sample to use your B2C credentials

Regardless which language you picked for your sample, you need to update the `issuance_request_config.json` file and the `presentation_request_config.json` file and change the `type` attribute to match the name of your VC credential.  

## Testing

Steps:

1. Sign up for a B2C local account if you haven't done so already
1. Run the sample and issue yourself a VC. You should be asked to signin to your B2C tenant in the Authenticator.
1. Run the `B2C_1A_signin_VC` policy, scan the QR code and signin to your B2C account using your VC. 

![B2C+VC jwt token](/ReadmeFiles/b2c-vc-jwt-token.png)

## Notes & ideas for further enhancements

- There is no authentication in the B2C REST API configuration in TrustFrameworkExtensionsVC.xml in the `REST-VC-GetAuthResult` TechnicalProfile. You should consider adding this.
- Issuance of VCs based on a user profile could be implemented in an webapp that lets the user sign in to B2C, where the app then uses the claims in B2C's id_token and pass it to the Request API. For inspiration how that could be done in aspnet, please see [this](https://github.com/cljung/did-samples/tree/main/vc-onboarding) github repo
- B2C signup policy could also make use of a VC in that way that you could present arbitrary VC and let the verifier pick up any usefull claims, like firstname, lastname, etc. This would make the signup journey more smooth from a user perspective