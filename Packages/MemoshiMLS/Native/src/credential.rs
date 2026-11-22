// Copyright 2026 Memoshi contributors. SPDX-License-Identifier: Apache-2.0
use crate::NativeError;
use mls_rs::{CipherSuite, CipherSuiteProvider, CryptoProvider, ExtensionList};
use mls_rs_core::{crypto::SignaturePublicKey, identity::{BasicCredential, CredentialType,
    IdentityProvider, MemberValidationContext, SigningIdentity}, time::MlsTime};
use mls_rs_crypto_cryptokit::{CryptoKitCipherSuite, CryptoKitProvider};
use serde::{Deserialize, Serialize};

pub(crate) const SUITE: CipherSuite = CipherSuite::CURVE25519_AES128;
pub(crate) const MAX_CREDENTIAL: usize = 4096;

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
#[serde(deny_unknown_fields)]
pub struct NativeCredential {
    pub device_id: String,
    pub signing_public_key: Vec<u8>,
    pub agreement_public_key: Vec<u8>,
}

impl NativeCredential {
    pub(crate) fn validate(&self) -> Result<(), NativeError> {
        if self.device_id.is_empty() || self.device_id.len() > 128
            || !self.device_id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
            || self.signing_public_key.len() != 32 || self.agreement_public_key.len() != 32 {
            return Err(NativeError::InvalidInput);
        }
        Ok(())
    }
}

pub(crate) fn cipher() -> Result<CryptoKitCipherSuite, NativeError> {
    CryptoKitProvider::with_enabled_cipher_suites(vec![SUITE])
        .cipher_suite_provider(SUITE).ok_or(NativeError::NativeFailure)
}

// A device-only Noise Ed25519 identity certifies the separately generated MLS key.
// It is stable for the local client lifetime and travels inside its BasicCredential.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct BoundCredential {
    pub version: u8,
    pub device: NativeCredential,
    pub mls_signing_public_key: Vec<u8>,
    pub identity_signature: Vec<u8>,
}

pub(crate) fn binding_payload(device: &NativeCredential, mls_key: &[u8]) -> Result<Vec<u8>, NativeError> {
    device.validate()?;
    if mls_key.len() != 32 { return Err(NativeError::InvalidInput); }
    let mut bytes = b"memoshi.mls.device-credential.v1\0".to_vec();
    bytes.extend_from_slice(&(device.device_id.len() as u32).to_be_bytes());
    bytes.extend_from_slice(device.device_id.as_bytes());
    bytes.extend_from_slice(&device.signing_public_key);
    bytes.extend_from_slice(&device.agreement_public_key);
    bytes.extend_from_slice(mls_key);
    Ok(bytes)
}

impl BoundCredential {
    pub(crate) fn validate(&self) -> Result<(), NativeError> {
        if self.version != 1 || self.identity_signature.len() != 64 {
            return Err(NativeError::AuthenticationFailed);
        }
        let payload = binding_payload(&self.device, &self.mls_signing_public_key)?;
        cipher()?.verify(&SignaturePublicKey::new(self.device.signing_public_key.clone()),
            &self.identity_signature, &payload).map_err(|_| NativeError::AuthenticationFailed)
    }

    pub(crate) fn signing_identity(&self) -> Result<SigningIdentity, NativeError> {
        self.validate()?;
        let encoded = serde_json::to_vec(self).map_err(|_| NativeError::InvalidInput)?;
        Ok(SigningIdentity::new(BasicCredential::new(encoded).into_credential(),
            SignaturePublicKey::new(self.mls_signing_public_key.clone())))
    }
}

pub(crate) fn decode_identity(identity: &SigningIdentity) -> Result<BoundCredential, NativeError> {
    let basic = identity.credential.as_basic().ok_or(NativeError::AuthenticationFailed)?;
    if basic.identifier.len() > MAX_CREDENTIAL { return Err(NativeError::InvalidInput); }
    let cert: BoundCredential = serde_json::from_slice(&basic.identifier)
        .map_err(|_| NativeError::AuthenticationFailed)?;
    if identity.signature_key.as_ref() != cert.mls_signing_public_key.as_slice() {
        return Err(NativeError::AuthenticationFailed);
    }
    cert.validate()?;
    Ok(cert)
}

#[derive(Clone, Debug)]
pub(crate) struct DeviceIdentityProvider;

impl IdentityProvider for DeviceIdentityProvider {
    type Error = NativeError;

    fn validate_member(&self, identity: &SigningIdentity, _: Option<MlsTime>,
        _: MemberValidationContext<'_>) -> Result<(), Self::Error> {
        decode_identity(identity).map(|_| ())
    }
    fn validate_external_sender(&self, _: &SigningIdentity, _: Option<MlsTime>,
        _: Option<&ExtensionList>) -> Result<(), Self::Error> {
        // Memoshi admits a device only through authenticated pairing and an ordered Add.
        Err(NativeError::AuthenticationFailed)
    }
    fn identity(&self, identity: &SigningIdentity, _: &ExtensionList) -> Result<Vec<u8>, Self::Error> {
        Ok(decode_identity(identity)?.device.device_id.into_bytes())
    }
    fn valid_successor(&self, predecessor: &SigningIdentity, successor: &SigningIdentity,
        _: &ExtensionList) -> Result<bool, Self::Error> {
        Ok(decode_identity(predecessor)? == decode_identity(successor)?)
    }
    fn supported_types(&self) -> Vec<CredentialType> {
        vec![BasicCredential::credential_type()]
    }
}
