// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

// Verifiable Credentials Issuer Sample

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


////////// Issuer's DID configuration values
const config = require('./didconfig.json')

////////// Load the VC SDK with the Issuer's DID and Key Vault details
const kvCredentials = new ClientSecretCredential(config.azTenantId, config.azClientId, config.azClientSecret);
const signingKeyReference = new KeyReference(config.kvSigningKeyId, 'key', config.kvRemoteSigningKeyId);

var crypto = new CryptoBuilder()
    .useSigningKeyReference(signingKeyReference)
    .useKeyVault(kvCredentials, config.kvVaultUri)
    .useDid(config.did)
    .build();

/////////// Set the expected values for the Verifiable Credential
const credential = 'https://beta.did.msidentity.com/v1.0/3c32ed40-8a10-465b-8ba4-0b1e86882668/verifiableCredential/contracts/VerifiedCredentialExpert';
const credentialType = ['VerifiedCredentialExpert'];

//////////// Main Express server function
// Note: You'll want to update port values for your setup.
const app = express()
const port = process.env.PORT || 8081;

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

// echo function so you can test deployment
app.get("/echo",
    function (req, res) {
        res.status(200).json({
            'date': new Date().toISOString(),
            'api': req.protocol + '://' + req.hostname + req.originalUrl,
            'Host': req.hostname,
            'x-forwarded-for': req.headers['x-forwarded-for'],
            'x-original-host': req.headers['x-original-host'],
            'issuerDid': config.did,
            'credentialType': credentialType,
            'credential': credential
            });
    }
);

// Serve index.html as the home page
app.get('/', function (req, res) { 
  res.sendFile('public/index.html', {root: __dirname})
})

// Generate an issuance request, cache it on the server,
// and return a reference to the issuance request. The reference
// will be displayed to the user on the client side as a QR code.
app.get('/issue-request', async (req, res) => {

  // Construct a request to issue a verifiable credential 
  // using the verifiable credential issuer service
  const requestBuilder = new RequestorBuilder({
    presentationDefinition: {
      input_descriptors: [
        {
          id: "expert",
          schema: {
            uri: credentialType,
          },
          issuance: [
            {
              manifest: credential
            }
          ]
        }
      ]
    }
  }, crypto).allowIssuance();

  // Cache the issue request on the server
  req.session.issueRequest = await requestBuilder.build().create();
  
  // Return a reference to the issue request that can be encoded as a QR code
  var requestUri = encodeURIComponent(`https://${req.hostname}/issue-request.jwt?id=${req.session.id}`);
  var issueRequestReference = 'openid://vc/?request_uri=' + requestUri;
  res.send(issueRequestReference);

})


// When the QR code is scanned, Authenticator will dereference the
// issue request to this URL. This route simply returns the cached
// issue request to Authenticator.
app.get('/issue-request.jwt', async (req, res) => {

  // Look up the issue request by session ID
  sessionStore.get(req.query.id, (error, session) => {
    res.send(session.issueRequest.request);
  })

})

// start server
app.listen(port, () => console.log(`Example issuer app listening on port ${port}!`))
