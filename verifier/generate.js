// This script generates an unpublished long-form DID, storing private keys in Azure Key Vault.
// Key Vault details are provided in ./didconfig.json.
// You should only need to run this script once to generate your verifier's DID and its keys.
const fs = require('fs');
const crypt = require('crypto');
const config = require('./didconfig.json');

//////////////// Load DID packages
var { ClientSecretCredential } = require('@azure/identity');
var { CryptoBuilder, 
      LongFormDid,
      KeyReference,
      KeyUse
    } = require('verifiablecredentials-verification-sdk-typescript');

///////////////// Generate random key IDs to use with default key vault instances
config.kvSigningKeyId = crypt.randomBytes(8).toString('hex');
config.kvRecoveryKeyId = crypt.randomBytes(8).toString('hex');
config.kvUpdateKeyId = crypt.randomBytes(8).toString('hex');

///////////////// Setup the crypto class from the VC SDK
const kvCredentials = new ClientSecretCredential(config.azTenantId, config.azClientId, config.azClientSecret);
const signingKeyReference = new KeyReference(config.kvSigningKeyId, 'key');
const recoveryKeyReference = new KeyReference(config.kvRecoveryKeyId, 'key');
const updateKeyReference = new KeyReference(config.kvUpdateKeyId, 'key');
var crypto = new CryptoBuilder()
    .useSigningKeyReference(signingKeyReference)
    .useRecoveryKeyReference(recoveryKeyReference)
    .useUpdateKeyReference(updateKeyReference)
    .useKeyVault(kvCredentials, config.kvVaultUri)
    .build();

(async () => {

/////////////// Generate the necessary keys in Azure Key Vault, and generate a DID.
crypto = await crypto.generateKey(KeyUse.Signature, 'signing');
crypto = await crypto.generateKey(KeyUse.Signature, 'recovery');
crypto = await crypto.generateKey(KeyUse.Signature, 'update');
const did = await new LongFormDid(crypto).serialize();

////////////// Store the DID back in the config file, where it will be used by ./app.js
config.did = did;
const data = JSON.stringify(config, null, 4);
await fs.writeFile('./didconfig.json', data, function () {});

})();