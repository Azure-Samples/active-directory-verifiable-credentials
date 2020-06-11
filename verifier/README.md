## Steps to run verifier sample using pre-configured Verified Credential Ninja card on your local machine

1. Run the issuer sample to get your Verified Credential Ninja card.
2. `npm install`
3. Use the same approach you used in the issuer sample to connect your mobile device to your local machine.
4. `node app.js`. Navigate to the home page and click the button to display a QR code.
5. Open Authenticator, and click the QR scanning button on the Cards tab. Scan the QR code.
6. Approve the request to prove you are a Verified Credential Ninja!

## Setup

Explain how to prepare the sample once the user clones or downloads the repository. The section should outline every step necessary to install dependencies and set up any settings (for example, API keys and output folders).

## Running the sample

Outline step-by-step instructions to execute the sample and see its output. Include steps for executing the sample from the IDE, starting specific services in the Azure portal or anything related to the overall launch of the code.







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

1. You can deploy the Node server to the cloud, so that Authenticator can communicate with it over the public internet.
2. You can expose your local machine over the public internet using a proxy tool.
3. You can connect your android device to your machine via USB and configure the network settings appropriately.
4. You can connect your android device to the same wifi network as your machine, and communicate over the LAN.

We recommend the last option. Here are the steps we used to do so:

1. Modify the contents of the `./certs/ssl.conf` file to reflect your local environment. Replace the IP addresses with the local IP address of your machine on the wifi network. Optionally, replace the DNS name with the host name of your local machine.
2. Generate a self-signed certificate using Open SSL and the `./certs/ssl.conf` file:

```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./certs/server.key -out ./certs/server.crt -config ./certs/ssl.conf
```

3. Install the `.crt` file onto your android device. Go to **Settings** --> **Security** --> **Encryption & Credentials**, and install the certificate as a trusted certificate on your android device.
4. If necessary, modify your machine's firewall rules to allow inbound HTTPS requests.
5. If necessary, update the `hostname` and `port` in the `app.js` file to the correct values for your environment.

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