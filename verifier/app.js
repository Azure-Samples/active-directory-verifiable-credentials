// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

////////////// Node packages
var http = require('http');
var https = require('https');
var fs = require('fs');
var path = require('path');
var express = require('express')
var session = require('express-session')
var bodyParser = require('body-parser')
var base64url = require('base64url')
var secureRandom = require('secure-random');

//////////////// Verifiable Credential SDK
var { CryptoBuilder, 
      LongFormDid, 
      RequestorBuilder, 
      ValidatorBuilder
    } = require('verifiablecredentials-verification-sdk-typescript');


//////////// Main Express server function
// Note: You'll want to update the hostname and port values for your setup.
const app = express()
const port = 8082
const hostname = '192.168.1.4'

/////////// OpenID Connect Client Registration
const client = {
  client_name: 'Sample Verifier',
  logo_uri: 'https://storagebeta.blob.core.windows.net/static/ninja-icon.png',
  tos_uri: 'https://www.microsoft.com/servicesagreement',
  client_purpose: 'To check if you know how to use verifiable credentials.'
}

/////////// Verifiable Credential configuration values
const credentialType = 'VerifiedCredentialNinja';
const issuerDid = 'did:ion:EiARML0CG8vUJHoKPBIVU-PiP4d2umBpzJD-yB9nOavQgA?-ion-initial-state=eyJkZWx0YV9oYXNoIjoiRWlCUTlwSHdpY2RMU0E4TS11ejYwdE94aXJ1UTRRaXp5UEtQRnpNUm5ITEowQSIsInJlY292ZXJ5X2tleSI6eyJrdHkiOiJFQyIsImNydiI6InNlY3AyNTZrMSIsIngiOiJMdS1iUk5RQ3MtYTNIUWNWMDJwOHVoRUpxQWJaS1lOVVBmN29DYk84bnhBIiwieSI6IlFMQ0QxOUZpS09xQkFXeV9GWk1QcmdiZlV1c0RGQ0xUZ190MDV6SzZIVVEifSwicmVjb3ZlcnlfY29tbWl0bWVudCI6IkVpREtCY2dFUU9kanhXa2Z6SEMyc2s5UWVkQ1VJcFdqQU5QSWVzc29xT3gyY2cifQ.eyJ1cGRhdGVfY29tbWl0bWVudCI6IkVpRGhpZUp5SzMtQTZHM0tKVElGaWxZcThPM09NOGtMTWVEZ3J2RTdkcnJOOWciLCJwYXRjaGVzIjpbeyJhY3Rpb24iOiJyZXBsYWNlIiwiZG9jdW1lbnQiOnsicHVibGljS2V5cyI6W3siaWQiOiJzaWdfZDc0ODViNjYiLCJ0eXBlIjoiRWNkc2FTZWNwMjU2azFWZXJpZmljYXRpb25LZXkyMDE5IiwiandrIjp7Imt0eSI6IkVDIiwiY3J2Ijoic2VjcDI1NmsxIiwieCI6IkFaTEZycC1NNzUtVl9MT2RlSXJKaTlYQUFmd3QwbkZYbDFCNDVBRElWTUUiLCJ5IjoiUU5OLTlVTjN2X2ZUV0JFQ1NwcVJyOS00S01JempDdkpsMHZVNjhjYVRlayJ9LCJ1c2FnZSI6WyJvcHMiLCJhdXRoIiwiZ2VuZXJhbCJdfV19fV19';

/////////// Load credentials for issuer organization from Key Vault
// TODO: Update this sample to use Key Vault when bug is fixed

/////////// Load credentials for issuer organization from file
// TODO: Update this sample to use same long form DID on every app start

////////// Generate a new ION long form DID to be used by this website
const did = '';
const signingKeyReference = 'sign';
const crypto = new CryptoBuilder(did, signingKeyReference).build();
(async () => {
  const longForm = new LongFormDid(crypto);
  const longFormDid = await longForm.create(signingKeyReference);
  crypto.builder.did = longFormDid;
})();



// Serve static files out of the /public directory
app.use(express.static('public'))

// Set up a simple server side session store.
// The session store will briefly cache presentation requests
// to facilitate QR code scanning, and store presentation responses
// so they can be retrieved by the browser.
var sessionStore = new session.MemoryStore();
app.use(session({
  secret: 'cookie-secret-key',
  resave: false,
  saveUninitialized: true,
  store: sessionStore
}))

// Serve index.html as the home page
app.get('/', function (req, res) { 
  res.sendFile('public/index.html', {root: __dirname})
})

// Generate an presentation request, cache it on the server,
// and return a reference to the issuance reqeust. The reference
// will be displayed to the user on the client side as a QR code.
app.get('/presentation-request', async (req, res) => {

  // Construct a request to issue a verifiable credential 
  // using the verifiable credential issuer service
  state = req.session.id;
  const nonce = base64url.encode(Buffer.from(secureRandom.randomUint8Array(10)));
  const clientId = `${req.protocol}://${hostname}:${port}/presentation-response`;

  const requestBuilder = new RequestorBuilder({
    crypto: crypto,
    clientName: client.client_name,
    clientId: clientId,
    redirectUri: clientId,
    logoUri: client.logo_uri,
    tosUri: client.tos_uri,
    client_purpose: client.client_purpose,
    attestation: {
      presentations: [
        { 
          credentialType: credentialType, 
          required: true
        }
      ]
    }
  }).useNonce(nonce)
    .useState(state)
    .allowIssuance(false)
    .useVerifiablePresentationExpiry(10);

  // Cache the issue request on the server
  req.session.presentationRequest = await requestBuilder.build().create();
  
  // Return a reference to the presentation request that can be encoded as a QR code
  var requestUri = encodeURIComponent(`${req.protocol}://${hostname}:${port}/presentation-request.jwt?id=${req.session.id}`);
  var presentationRequestReference = 'openid://?request_uri=' + requestUri + '&client_id=' +  clientId;
  res.send(presentationRequestReference);

})


// When the QR code is scanned, Authenticator will dereference the
// presentation request to this URL. This route simply returns the cached
// presentation request to Authenticator.
app.get('/presentation-request.jwt', async (req, res) => {

  // Look up the issue reqeust by session ID
  sessionStore.get(req.query.id, (error, session) => {
    console.log(session.presentationRequest.request)
    res.send(session.presentationRequest.request);
  })

})


// Once the user approves the presentation request,
// Authenticator will present the credential back to this server
// at this URL. We can verify the credential and extract its contents
// to verify the user is a Verified Credential Ninja.
var parser = bodyParser.urlencoded({ extended: false });
app.post('/presentation-response', parser, async (req, res) => {

  // Temporary fix to get state value while not exposed
  // in SDK or in reqeust body
  var tokenParts = req.body.id_token.split('.')
  var decodedBody = base64url.decode(tokenParts[1])
  var payload = JSON.parse(decodedBody)
  var state = payload.state
    
  // Set up the Verifiable Credentials SDK to validate all signatures
  // and claims in the credential presentation.
  const clientId = `${req.protocol}://${hostname}:${port}/presentation-response`

  // Validate the credential presentation and extract the credential's attributes.
  // If this check succeeds, the user is a Verified Credential Ninja.
  // Log a message to the console indicating successful verification of the credential.
  const validator = new ValidatorBuilder(crypto)
    .useTrustedIssuersForVerifiableCredentials([issuerDid])
    .useAudienceUrl(clientId)
    .build();

  const validationResult = await validator.validate(req.body.id_token);
  
  if (!validationResult.result) {
      console.error(`Validation failed: ${validationResult.detailedError}`);
      return res.send()
  }

  var verifiedCredential = validationResult.validationResult.verifiableCredentials[credentialType];
  console.log(`${verifiedCredential.vc.credentialSubject.firstName} ${verifiedCredential.vc.credentialSubject.lastName} is a Verified Credential Ninja!`);

  // Store the successful presentation in session storage
  sessionStore.get(state, (error, session) => {

    session.verifiedCredential = verifiedCredential;
    sessionStore.set(state, session, (error) => {
      res.send();
    });
  })
})


// Checks to see if the server received a successful presentation
// of a Verified Credential Ninja card. Updates the browser UI with
// a successful message if the user is a verified ninja.
app.get('/presentation-response', async (req, res) => {

  // If a credential has been received, display the contents in the browser
  if (req.session.verifiedCredential) {

    presentedCredential = req.session.verifiedCredential;
    req.session.verifiedCredential = null;
    return res.send(`Congratulations, ${presentedCredential.vc.credentialSubject.firstName} ${presentedCredential.vc.credentialSubject.lastName} is a Verified Credential Ninja!`)  
  }

  // If no credential has been received, just display an empty message
  res.send('')

})

// To test this issuer with Authenticator, your server will need to
// use SSL. Here, we've used a self-signed cert and configured our
// mobile device to trust this certificate.
var privateKey  = fs.readFileSync('certs/510-stratford.key', 'utf8');
var certificate = fs.readFileSync('certs/510-stratford.crt', 'utf8');
var credentials = {key: privateKey, cert: certificate};
var httpsServer = https.createServer(credentials, app);

// start server
httpsServer.listen(port, () => console.log(`Example app listening on port ${port}!`))