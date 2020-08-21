

# Verifiable Credentials Verifier Website

This folder contains a sample website written in NodeJS that verifies a verifiable credential. All code for the website is contained in `app.js`. Essentially, this website does three things:

1. It generates a QR code and displays it in a browser.
2. It generates a credential presentation request, which is sent to Microsoft Authenticator after the QR code is scanned.
3. It receives the requested credential from Authenticator and validates it.

See our [documentation](https://aka.ms/didfordevs) for a more detailed explanation of the credential presentation and verification process.

There are two ways to run this code sample. 

- Run the code as-is. The sample is set up to request a Credential Ninja Card. 
- Change the code to request a different verifiable credential.


## Running the sample 

Follow these steps to run the sample using a pre-configured Verified Credential Ninja card on your local machine.

1. Clone this repository and `cd` to this `verifier` directory.
2. Run `npm install` to install all dependencies for the verifier website.
3. Proceed with each step below to configure and run the website.

### Issue a verifiable credential.

Before you can use the verifier sample, you'll first need to issue a verifiable credential to Authenticator. If you haven't done so already, head on over to the  `../issuer` sample first, and then return to this verifier sample.

### Connect Authenticator to your local Node server

When you run the sample website, your android device will need to be able to communicate with your Node server via HTTPS requests. Setting this up can be a bit tricky - you have a few options to choose from:

1. You can deploy the Node server to the cloud, so that Authenticator can communicate with it over the public internet.
2. You can connect your android device to your machine via USB and configure the network settings appropriately.
3. You can connect your android device to the same wifi network as your machine, and communicate over the LAN.
4. You can expose your local machine over the public internet using a tool like ngrok.

We recommend the last option. Here are the steps we used to do so:

1. Go to [ngrok.com/](https://ngrok.com/) and create an account.
2. Follow the instructions to install and configure ngrok.
3. Start ngrok, exposing your server, which uses port 8082 by default:

```
ngrok http 8082
```

4. Copy the `https://` URL output by ngrok. In the `verifier/app.js` file, update the `host` variable to its value.


### Run the website

Finally, you're ready to run the website on your local machine:

```bash
node ./app.js
```

Once the site is up and running, navigate to the site in a browser using the ngrok URL.

### Using the website

To request and validate a verifiable credential, run the website and navigate to the homepage. Then:

1. Click the button to display a QR code (or a deep link on mobile browsers).
2. In Authenticator, open the QR scanner.
3. Approve the request in Authenticator.    

## Modifying the code to use your issuer and verifier

If you've created your own issuer following our [documentation](https://aka.ms/didfordevs), you can edit the code to use your issuer and verifier.

1. In `app.js`, update the `credentialType` value for your verifiable credential.
2. In `app.js`, update the `issuerDid` value to the expected DID of the issuer of the verifiable credential you expect.
3. In `app.js`, optionally update the `client` values to reflect your verifier website.
4. In `didconfig.json`, update all values to use your Azure Key Vault.
6. Run `node ./generate.js` to generate a new DID for your website and create keys in your Key Vault. 

More instructions on using the VC SDK to request and verify verifiable credentials can be found in our [documentation](https://aka.ms/didfordevs).