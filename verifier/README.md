

# Verifiable Credentials Issuer Website

This folder contains a sample website written in NodeJS that verifies a verifiable credential. All code for the website is contained in `app.js`. Essentially, this website does three things:

1. It generates a QR code and displays it in a browser.
2. It generates a credential presentation request, which is sent to Microsoft Authenticator after the QR code is scanned.
3. It receives the requested credential from Authenticator and validates it.

See our [documentation](https://aka.ms/didfordevs) for a more detailed explanation of the credential presentation and verification process.

There are two ways to run this code sample. 

- Run the code as-is. The sample is set up to request a Credential Ninja Card. 
- Change the code to request a different verifiable credential.


## Run the sample 

Follow these steps to run the sample using a pre-configured Verified Credential Ninja card on your local machine.

1. Clone this repository and `cd` to this `verifier` directory.
2. Run `npm install` to install all dependencies for the issuer website.
3. Run `node ./app.js` to start the website.

### Issue a verifiable credential.

To run this website, you'll need to first issue a verifiable credential to Authenticator. Run the `../issuer` sample first, and then return to this verifier sample.

### Connecting Authenticator to your local Node server

Your android device will need to be able to communicate with your Node server via HTTPS requests. Setting this up can be a bit tricky - you have a few options to choose from:
Your android device will need to be able to communicate with your Node server via HTTPS requests. Setting this up can be a bit tricky - you have a few options to choose from:

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

4. Copy the `https://` URL output by ngrok. Copy its value into the `host` variable in `app.js`.
5. Run the website, and navigate to the site in a browser usign the ngrok URL.

### Using the website

To issue a verifiable credential, run the website and navigate to the homepage. Then:

1. Click the button to display a QR code.
2. In Authenticator, open the QR scanner.
3. Approve the request in Authenticator.    

## Modifying the code to use your issuer

If you've created your own issuer following our [documentation](https://aka.ms/didfordevs), you can edit the code in `app.js` to use your issuer.

1. Update the `credentialType` value for your verifiable credential.
2. Update the `issuerDid` value to the expected DID of the issuer of the verifiable credential you expect.
3. Optionally, update the `client` values to reflect your verifier website.

More instructions on using the VC SDK to request and verify verifiable credentials can be found in our [documentation](https://aka.ms/didfordevs).