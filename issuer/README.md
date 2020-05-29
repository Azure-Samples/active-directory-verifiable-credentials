## Steps to run issuer sample using pre-configured Verified Credential Ninja card on your local machine

1. `npm install`
2. Join the Microsoft Authenticator beta program, available to join via the Play Store.
3. Download Microsoft Authenticator beta from the Play Store onto an android device.
4. Somehow connect Authenticator to connect to the local Node server. Several options:
    - Run Authenticator in an emulator on your machine.
    - Deploy the Node server to the cloud.
    - Expose your local machine over the public web via a proxy.
    - Connect your android device to your machine via USB, and configure the network settings appropriately.
    - Connect your android device to the same wifi network as your machine. Steps:
        - Generate a self-signed certificate. See `certs/ssl.conf` for instructions.
        - Use the appropriate local IP address or hostname when generating the certificate.
        - Install the certificate as a trusted certificate on your android device in Settings --> Security --> Encryption & Credentials.
        - Create firewall rules to allow inbound HTTP requests to your Node server over the appropriate port.
        - Update the `app.js` file with the correct `hostname` and `port` for your setup.
        - This will allow Authenticator to communicate with the Node server running on your machine using the wifi network while still using SSL.
5. `node app.js`. Navigate to the home page and click the button to display a QR code.
6. Open Authenticator, and add an account. Choose "Other account", and scan the QR code.
7. Follow the instructions to receive yoru Verified Credential Ninja card.