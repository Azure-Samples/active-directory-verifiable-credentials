// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

// Verifiable Credentials Verifier Sample

////////////// Node packages
var http = require('http');
var fs = require('fs');
var path = require('path');
var express = require('express')
var session = require('express-session')
var bodyParser = require('body-parser')
var base64url = require('base64url')
var secureRandom = require('secure-random');

//////////////// Verifiable Credential SDK
var { ClientSecretCredential } = require('@azure/identity');
var { CryptoBuilder, 
      RequestorBuilder, 
      ValidatorBuilder,
      KeyReference
    } = require('verifiablecredentials-verification-sdk-typescript');

/////////// Verifier's client details
const client = {
  client_name: 'Sample Verifier',
  logo_uri: 'https://storagebeta.blob.core.windows.net/static/ninja-icon.png',
  tos_uri: 'https://www.microsoft.com/servicesagreement',
  client_purpose: 'To check if you know how to use verifiable credentials.'
}

////////// Verifier's DID configuration values
const config = require('./didconfig.json')
if (!config.did) {
  throw new Error('Make sure you run the DID generation script before starting the server.')
}

////////// Load the VC SDK with the verifier's DID and Key Vault details
const kvCredentials = new ClientSecretCredential(config.azTenantId, config.azClientId, config.azClientSecret);
const signingKeyReference = new KeyReference(config.kvSigningKeyId, 'key');
const recoveryKeyReference = new KeyReference(config.kvRecoveryKeyId, 'key');
var crypto = new CryptoBuilder()
    .useSigningKeyReference(signingKeyReference)
    .useRecoveryKeyReference(recoveryKeyReference)
    .useKeyVault(kvCredentials, config.kvVaultUri)
    .useDid(config.did)
    .build();

/////////// Set the expected values for the Verifiable Credential
const credentialType = 'VerifiedCredentialNinja';
const issuerDid = ['did:ion:EiAQ8DKCI3WmQnab84lohz6-JODQOwV9-esWesruBLq54Q?-ion-initial-state=eyJkZWx0YV9oYXNoIjoiRWlCN0R1dEdZNG5NTWJtY2RXcDZLVDhjY2ZoVVBDSVlWVFEwUmkyUWtDXzNXUSIsInJlY292ZXJ5X2NvbW1pdG1lbnQiOiJFaURrT0tUQ2duUWIxWmg3ZTZsWGVXOGJGdmFqLTB2Y0wxcXRrel9ZdjMwZUxnIn0.eyJ1cGRhdGVfY29tbWl0bWVudCI6IkVpRHlDYXFGMFpENllFbmFCaUJjZkgyT3h0dHhyd1ZxaFZ4Wjg0Q1lNNUVpQ0EiLCJwYXRjaGVzIjpbeyJhY3Rpb24iOiJyZXBsYWNlIiwiZG9jdW1lbnQiOnsicHVibGljX2tleXMiOlt7ImlkIjoic2lnX2IxNDIzZGU5IiwidHlwZSI6IkVjZHNhU2VjcDI1NmsxVmVyaWZpY2F0aW9uS2V5MjAxOSIsImp3ayI6eyJrdHkiOiJFQyIsImNydiI6InNlY3AyNTZrMSIsIngiOiJPWlVueGMtRnBScS1JZjd3YWN6VUoxejdIdEpSTEF6UDViR1lGU250TlVJIiwieSI6Ikl1Q2c2ZHJ1bm84WjkxX2MwYVhvdnRfWVV0THBNQl9OMy11azZhcVU3YmsifSwicHVycG9zZSI6WyJhdXRoIiwiZ2VuZXJhbCJdfV19fV19'];

//////////// Main Express server function
// Note: You'll want to update the host and port values for your setup.
const app = express()
const port = 8082

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
  const clientId = `https://${req.hostname}/presentation-response`;

  const requestBuilder = new RequestorBuilder({
    clientName: client.client_name,
    clientId: clientId,
    redirectUri: clientId,
    logoUri: client.logo_uri,
    tosUri: client.tos_uri,
    client_purpose: client.client_purpose,
    presentationDefinition: {
      input_descriptors: [{
          schema: {
              uri: [credentialType],
          }
      }]
  }
},  crypto)
    .useNonce(nonce)
    .useState(state);

  // Cache the issue request on the server
  req.session.presentationRequest = await requestBuilder.build().create();
  
  // Return a reference to the presentation request that can be encoded as a QR code
  var requestUri = encodeURIComponent(`https://${req.hostname}/presentation-request.jwt?id=${req.session.id}`);
  var presentationRequestReference = 'openid://vc/?request_uri=' + requestUri;
  res.send(presentationRequestReference);

})


// When the QR code is scanned, Authenticator will dereference the
// presentation request to this URL. This route simply returns the cached
// presentation request to Authenticator.
app.get('/presentation-request.jwt', async (req, res) => {

  // Look up the issue reqeust by session ID
  sessionStore.get(req.query.id, (error, session) => {
    res.send(session.presentationRequest.request);
  })

})


// Once the user approves the presentation request,
// Authenticator will present the credential back to this server
// at this URL. We can verify the credential and extract its contents
// to verify the user is a Verified Credential Ninja.
var parser = bodyParser.urlencoded({ extended: false });
app.post('/presentation-response', parser, async (req, res) => {

  // Set up the Verifiable Credentials SDK to validate all signatures
  // and claims in the credential presentation.
  const clientId = `https://${req.hostname}/presentation-response`

  // Validate the credential presentation and extract the credential's attributes.
  // If this check succeeds, the user is a Verified Credential Ninja.
  // Log a message to the console indicating successful verification of the credential.
  const validator = new ValidatorBuilder(crypto)
    .useTrustedIssuersForVerifiableCredentials({[credentialType]: issuerDid})
    .useAudienceUrl(clientId)
    .build();

  const validationResult = await validator.validate(req.body.id_token);
  
  if (!validationResult.result) {
      console.error(`Validation failed: ${validationResult.detailedError}`);
      return res.send()
  }

  var verifiedCredential = validationResult.validationResult.verifiableCredentials[credentialType].decodedToken;
  console.log(`${verifiedCredential.vc.credentialSubject.firstName} ${verifiedCredential.vc.credentialSubject.lastName} is a Verified Credential Ninja!`);

  // Store the successful presentation in session storage
  sessionStore.get(req.body.state, (error, session) => {

    session.verifiedCredential = verifiedCredential;
    sessionStore.set(req.body.state, session, (error) => {
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

// start server
app.listen(port, () => console.log(`Example app listening on port ${port}!`))
