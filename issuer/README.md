

# Verifiable Credentials Issuer Website

This folder contains a sample website written in NodeJS that issues a verifiable credential. All code for the website is contained in `app.js`. Essentially, this website does two things:

1. It generates a QR code and displays it in a browser.
2. It generates a credential issuance request, which is sent to Microsoft Authenticator after the QR code is scanned. Authenticator then communicates with a cloud issuer service to issue the verifiable credential.

See our [documentation](https://aka.ms/didfordevs) for a more detailed explanation of the credential issuance process.

There are two ways to run this code sample. 

- Run the code as-is. The sample is set up to issue anyone a Credential Ninja Card, using a issuer in the cloud run by Microsoft. 
- Set up your own issuer, and change the code to use that issuer to issue a verifiable credential. Our [documentation](https://aka.ms/didfordevs) describes how to set up your own issuer.


## Running the sample 

Follow these steps to run the sample using a pre-configured Verified Credential Ninja card on your local machine.

1. Clone this repository and `cd` to this `issuer` directory.
2. Run `npm install` to install all dependencies for the issuer website.

### Installing Microsoft Authenticator.

To run this sample, you'll need Microsoft Authenticator installed on an android device. Please follow [the instructions on our documentation](https://didproject.azurewebsites.net/docs/authenticator.html) to install Microsoft Authenticator.

### Connecting Authenticator to your local Node server

When you run the sample website, your android device will need to be able to communicate with your Node server via HTTPS requests. Setting this up can be a bit tricky - you have a few options to choose from:

1. You can deploy the Node server to the cloud, so that Authenticator can communicate with it over the public internet.
2. You can connect your android device to your machine via USB and configure the network settings appropriately.
3. You can connect your android device to the same wifi network as your machine, and communicate over the LAN.
4. You can expose your local machine over the public internet using a tool like ngrok.

We recommend the last option. Here are the steps we used to do so:

1. Go to [ngrok.com/](https://ngrok.com/) and create an account.
2. Follow the instructions to install and configure ngrok.
3. Start ngrok, exposing your server, which uses port 8081 by default:

```
ngrok http 8081
```

### Run the website

Finally, you're ready to run the website on your local machine:

```bash
node ./app.js
```

Once the site is up and running, navigate to the site in a browser using the secure ngrok URL, like `https://2ebe3ce0095c.ngrok.io/`.

### Using the website

To issue a verifiable credential, run the website and navigate to the homepage. Then:

1. Click the button to display a QR code (or a deep link on mobile browsers).
2. In Authenticator, add an account and choose **Other account**. Scan the QR code.
3. Follow the instructions to receive your verifiable credential.

## Modifying the code to use your issuer

If you've created your own issuer following our [documentation](https://aka.ms/didfordevs), you can edit the code to use your issuer.

1. In `issuer/app.js`, update the `credential` and `credentialType` values for your verifiable credential.
2. In `issuer/issuer_config/didconfig.json`, update all values to use your Azure Key Vault instance.

More instructions on using the VC SDK to issue verifiable credentials can be found in our [documentation](https://aka.ms/didfordevs).