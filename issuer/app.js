// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

////////////// Node packages
var express = require('express')
var session = require('express-session')
var base64url = require('base64url')
var secureRandom = require('secure-random');

//////////////// Verifiable Credential SDK
var { ClientSecretCredential } = require('@azure/identity');
var { CryptoBuilder, 
      LongFormDid, 
      RequestorBuilder,
      KeyReference,
      KeyUse
    } = require('verifiablecredentials-verification-sdk-typescript');


////////// Verifier's DID configuration values
const config = require('./issuer_config/didconfig.json')

////////// Load the VC SDK with the verifier's DID and Key Vault details
const kvCredentials = new ClientSecretCredential(config.azTenantId, config.azClientId, config.azClientSecret);
const signingKeyReference = new KeyReference(config.kvSigningKeyId, 'key');
const recoveryKeyReference = new KeyReference(config.kvRecoveryKeyId, 'key');
var crypto = new CryptoBuilder()
    .useSigningKeyReference(signingKeyReference)
    .useRecoveryKeyReference(recoveryKeyReference)
    .useKeyVault(kvCredentials, config.kvVaultUri)
    .build();

// BUGBUG: This website current does not use the same issuer DID that was 
// generated in Azure Portal. Instead, it generates a new set of keys 
// in Key Vault and a new DID on each run.
(async () => {
  crypto = await crypto.generateKey(KeyUse.Signature, 'signing');
  crypto = await crypto.generateKey(KeyUse.Signature, 'recovery');
  const did = await new LongFormDid(crypto).serialize();
  crypto.builder.useDid(did);
})();

/////////// Set the expected values for the Verifiable Credential
const credential = 'https://portableidentitycards.azure-api.net/v1.0/9c59be8b-bd18-45d9-b9d9-082bc07c094f/portableIdentities/contracts/Ninja%20Card';
const credentialType = 'VerifiedCredentialNinja';

//////////// Main Express server function
// Note: You'll want to update the hostname and port values for your setup.
const app = express()
const port = 8081
const host = 'https://207320b70e33.ngrok.io'

// Serve static files out of the /public directory
app.use(express.static('public'))

// Set up a simple server side session store.
// The session store will briefly cache issuance requests
// to facilitate QR code scanning.
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

// Generate an issuance request, cache it on the server,
// and return a reference to the issuance reqeust. The reference
// will be displayed to the user on the client side as a QR code.
app.get('/issue-request', async (req, res) => {

  // Construct a request to issue a verifiable credential 
  // using the verifiable credential issuer service
  const requestBuilder = new RequestorBuilder({
    attestation: {
      presentations: [
        { 
          credentialType: credentialType, 
          contracts: [credential], 
        }
      ]
    }
  }, crypto).allowIssuance();

  // Cache the issue request on the server
  req.session.issueRequest = await requestBuilder.build().create();
  
  // Return a reference to the issue request that can be encoded as a QR code
  var requestUri = encodeURIComponent(`${host}/issue-request.jwt?id=${req.session.id}`);
  var issueRequestReference = 'openid://vc/?request_uri=' + requestUri;
  res.send(issueRequestReference);

})


// When the QR code is scanned, Authenticator will dereference the
// issue request to this URL. This route simply returns the cached
// issue request to Authenticator.
app.get('/issue-request.jwt', async (req, res) => {

  // Look up the issue reqeust by session ID
  sessionStore.get(req.query.id, (error, session) => {
    res.send(session.issueRequest.request);
  })

})

// start server
app.listen(port, () => console.log(`Example app listening on port ${port}!`))
