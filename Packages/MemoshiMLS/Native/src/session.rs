// Copyright 2026 Memoshi contributors. SPDX-License-Identifier: Apache-2.0
use crate::{credential::{binding_payload, cipher, decode_identity, BoundCredential,
    DeviceIdentityProvider, NativeCredential, SUITE}, guarded, storage::{HostStorage,
    StoredData, MAX_KEY_PACKAGES, RETAINED_EPOCHS}, NativeError};
use mls_rs::{client_builder::{BaseConfig, WithCryptoProvider, WithGroupStateStorage,
    WithIdentityProvider, WithKeyPackageRepo}, group::{CommitEffect, ContentType, ReceivedMessage},
    mls_rules::{CommitOptions, DefaultMlsRules, EncryptionOptions}, CipherSuiteProvider,
    Client, Group, MlsMessage, MlsMessageDescription};
use mls_rs_core::{crypto::SignatureSecretKey, group::GroupContext,
    mls_rs_codec::{MlsDecode, MlsEncode}, protocol_version::ProtocolVersion};
use mls_rs_crypto_cryptokit::CryptoKitProvider;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet, HashMap}, sync::{Arc, Mutex}};
use zeroize::Zeroizing;

const MAX_MESSAGE: usize = 16 * 1024 * 1024;
const MAX_SNAPSHOT: usize = 64 * 1024 * 1024;
const MAX_MEMBERS: usize = 64;
type StoredConfig = WithGroupStateStorage<HostStorage, WithKeyPackageRepo<HostStorage, BaseConfig>>;
type MemoshiConfig = WithCryptoProvider<CryptoKitProvider,
    WithIdentityProvider<DeviceIdentityProvider, StoredConfig>>;
type MemoshiGroup = Group<MemoshiConfig>;
type MemoshiClient = Client<MemoshiConfig>;

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct NativeGroupInfo {
    pub group_id: Vec<u8>,
    pub epoch: u64,
    pub members: Vec<NativeCredential>,
    pub member_leaf_indices: HashMap<String, u32>,
    pub group_context: Vec<u8>,
    pub is_active: bool,
}
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct NativeStagedCommit {
    pub base_epoch: u64,
    pub target_epoch: u64,
    pub commit: Vec<u8>,
    pub welcome: Option<Vec<u8>>,
    pub members: Vec<NativeCredential>,
    pub member_leaf_indices: HashMap<String, u32>,
    pub group_context: Vec<u8>,
}
#[derive(Clone, uniffi::Record)]
pub struct NativeOrderedCommit {
    pub base_epoch: u64,
    pub target_epoch: u64,
    pub commit: Vec<u8>,
    pub members: Vec<NativeCredential>,
    pub member_leaf_indices: HashMap<String, u32>,
    pub group_context: Vec<u8>,
}
#[derive(uniffi::Record)]
pub struct NativeSealedMessage {
    pub ciphertext: Vec<u8>,
    pub group_epoch: u64,
}
#[derive(uniffi::Record)]
pub struct NativeOpenedMessage {
    pub plaintext: Vec<u8>,
    pub authenticated_data: Vec<u8>,
    pub sender: NativeCredential,
    pub group_epoch: u64,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct RosterEntry { index: u32, credential: NativeCredential }

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    version: u8,
    credential: NativeCredential,
    signer: Zeroizing<Vec<u8>>,
    mls_public_key: Vec<u8>,
    identity_signature: Vec<u8>,
    storage: StoredData,
    pending: Option<NativeStagedCommit>,
    rosters: BTreeMap<u64, Vec<RosterEntry>>,
    removed: Option<NativeGroupInfo>,
}

struct State {
    credential: NativeCredential,
    signer: SignatureSecretKey,
    mls_public_key: Vec<u8>,
    identity_signature: Option<Vec<u8>>,
    storage: HostStorage,
    client: Option<MemoshiClient>,
    group: Option<MemoshiGroup>,
    pending: Option<NativeStagedCommit>,
    rosters: BTreeMap<u64, Vec<RosterEntry>>,
    removed: Option<NativeGroupInfo>,
}

#[derive(uniffi::Object)]
pub struct NativeSession { inner: Mutex<State> }

fn bounded(bytes: &[u8]) -> Result<(), NativeError> {
    if bytes.is_empty() || bytes.len() > MAX_MESSAGE { Err(NativeError::InvalidInput) } else { Ok(()) }
}
fn next_epoch(epoch: u64) -> Result<u64, NativeError> { epoch.checked_add(1).ok_or(NativeError::EpochMismatch) }
fn roster(group: &MemoshiGroup) -> Result<Vec<RosterEntry>, NativeError> {
    let mut seen = BTreeSet::new();
    let mut members = Vec::new();
    for member in group.roster().members_iter() {
        let credential = decode_identity(&member.signing_identity)?.device;
        if !seen.insert(credential.device_id.clone()) || members.len() >= MAX_MEMBERS {
            return Err(NativeError::AuthenticationFailed);
        }
        members.push(RosterEntry { index: member.index, credential });
    }
    Ok(members)
}
fn sorted(mut members: Vec<NativeCredential>) -> Result<Vec<NativeCredential>, NativeError> {
    if members.is_empty() || members.len() > MAX_MEMBERS { return Err(NativeError::InvalidInput); }
    for member in &members { member.validate()?; }
    members.sort_by(|a, b| a.device_id.cmp(&b.device_id));
    if members.windows(2).any(|pair| pair[0].device_id == pair[1].device_id) {
        return Err(NativeError::AuthenticationFailed);
    }
    Ok(members)
}
fn members(group: &MemoshiGroup) -> Result<Vec<NativeCredential>, NativeError> {
    sorted(roster(group)?.into_iter().map(|entry| entry.credential).collect())
}
fn leaf_indices(group: &MemoshiGroup) -> Result<HashMap<String, u32>, NativeError> {
    Ok(roster(group)?.into_iter().map(|entry| (entry.credential.device_id, entry.index)).collect())
}
fn encoded_context(group: &MemoshiGroup) -> Result<Vec<u8>, NativeError> {
    group.context().mls_encode_to_vec().map_err(|_| NativeError::NativeFailure)
}
fn group_info(group: &MemoshiGroup) -> Result<NativeGroupInfo, NativeError> {
    Ok(NativeGroupInfo { group_id: group.group_id().to_vec(), epoch: group.context().epoch,
        members: members(group)?, member_leaf_indices: leaf_indices(group)?,
        group_context: encoded_context(group)?, is_active: true })
}
fn prospective_info(group: &MemoshiGroup) -> Result<NativeGroupInfo, NativeError> {
    let mut prospective = group.clone();
    prospective.apply_pending_commit().map_err(|_| NativeError::NativeFailure)?;
    group_info(&prospective)
}
fn build_client(state: &State) -> Result<MemoshiClient, NativeError> {
    let cert = BoundCredential { version: 1, device: state.credential.clone(),
        mls_signing_public_key: state.mls_public_key.clone(),
        identity_signature: state.identity_signature.clone().ok_or(NativeError::InvalidState)? };
    let rules = DefaultMlsRules::new().with_commit_options(CommitOptions::new()
        .with_path_required(true).with_ratchet_tree_extension(true)
        .with_single_welcome_message(true).with_allow_external_commit(false))
        .with_encryption_options(EncryptionOptions::new(true, Default::default()));
    Ok(Client::builder().key_package_repo(state.storage.clone())
        .group_state_storage(state.storage.clone())
        .crypto_provider(CryptoKitProvider::with_enabled_cipher_suites(vec![SUITE]))
        .identity_provider(DeviceIdentityProvider)
        .signing_identity(cert.signing_identity()?, state.signer.clone(), SUITE)
        .mls_rules(rules).build())
}
fn check_order(group: &MemoshiGroup, commit: &NativeOrderedCommit) -> Result<MlsMessage, NativeError> {
    if commit.base_epoch != group.context().epoch || commit.target_epoch != next_epoch(commit.base_epoch)? {
        return Err(NativeError::EpochMismatch);
    }
    bounded(&commit.commit)?;
    bounded(&commit.group_context)?;
    let target = GroupContext::mls_decode_exhaustive(&commit.group_context)
        .map_err(|_| NativeError::AuthenticationFailed)?;
    if target.protocol_version != ProtocolVersion::MLS_10 || target.cipher_suite != SUITE
        || target.group_id != group.group_id() || target.epoch != commit.target_epoch {
        return Err(NativeError::AuthenticationFailed);
    }
    let message = MlsMessage::from_bytes(&commit.commit).map_err(|_| NativeError::InvalidMessage)?;
    match message.description() {
        MlsMessageDescription::PrivateProtocolMessage { group_id, epoch_id, content_type: ContentType::Commit }
            if group_id == group.group_id() && epoch_id == commit.base_epoch => (),
        _ => return Err(NativeError::InvalidMessage),
    }
    sorted(commit.members.clone())?;
    if commit.member_leaf_indices.len() != commit.members.len()
        || !commit.members.iter().all(|m| commit.member_leaf_indices.contains_key(&m.device_id))
        || commit.member_leaf_indices.values().collect::<BTreeSet<_>>().len() != commit.members.len() {
        return Err(NativeError::AuthenticationFailed);
    }
    Ok(message)
}

impl State {
    fn client(&self) -> Result<&MemoshiClient, NativeError> { self.client.as_ref().ok_or(NativeError::InvalidState) }
    fn group(&self) -> Result<&MemoshiGroup, NativeError> { self.group.as_ref().ok_or(NativeError::InvalidState) }
    fn group_mut(&mut self) -> Result<&mut MemoshiGroup, NativeError> { self.group.as_mut().ok_or(NativeError::InvalidState) }
    fn remember_roster(&mut self) -> Result<(), NativeError> {
        let group = self.group()?;
        let epoch = group.context().epoch;
        let roster = roster(group)?;
        self.rosters.insert(epoch, roster);
        while self.rosters.len() > RETAINED_EPOCHS + 1 { self.rosters.pop_first(); }
        Ok(())
    }
    fn store(&mut self) -> Result<(), NativeError> {
        if let Some(group) = &mut self.group {
            group.write_to_storage().map_err(|_| NativeError::StorageFailure)?;
        }
        Ok(())
    }
    fn snapshot(&mut self) -> Result<Vec<u8>, NativeError> {
        self.store()?;
        let snapshot = Snapshot { version: 1, credential: self.credential.clone(),
            signer: Zeroizing::new(self.signer.as_bytes().to_vec()), mls_public_key: self.mls_public_key.clone(),
            identity_signature: self.identity_signature.clone().ok_or(NativeError::InvalidState)?,
            storage: self.storage.snapshot()?, pending: self.pending.clone(), rosters: self.rosters.clone(),
            removed: self.removed.clone() };
        let bytes = serde_json::to_vec(&snapshot).map_err(|_| NativeError::StorageFailure)?;
        if bytes.len() > MAX_SNAPSHOT { return Err(NativeError::StorageFailure); }
        Ok(bytes)
    }
    fn install_commit(&mut self, mut candidate: MemoshiGroup, effect: CommitEffect,
        ordered: &NativeOrderedCommit) -> Result<NativeGroupInfo, NativeError> {
        let approved = sorted(ordered.members.clone())?;
        match effect {
            CommitEffect::NewEpoch(_) => {
                if candidate.context().epoch != ordered.target_epoch || members(&candidate)? != approved
                    || leaf_indices(&candidate)? != ordered.member_leaf_indices
                    || encoded_context(&candidate)? != ordered.group_context {
                    return Err(NativeError::AuthenticationFailed);
                }
                candidate.write_to_storage().map_err(|_| NativeError::StorageFailure)?;
                self.group = Some(candidate);
                self.pending = None;
                self.remember_roster()?;
                group_info(self.group()?)
            }
            CommitEffect::Removed { new_epoch, .. } => {
                // Removed clients do not possess the new epoch's secrets. Erase all old
                // ratchets now; an offline former member still cannot decrypt future data.
                let mut remaining = members(&candidate)?;
                remaining.retain(|m| m.device_id != self.credential.device_id);
                let mut indices = leaf_indices(&candidate)?;
                indices.remove(&self.credential.device_id);
                if new_epoch.epoch != ordered.target_epoch || approved != remaining
                    || indices != ordered.member_leaf_indices {
                    return Err(NativeError::AuthenticationFailed);
                }
                // A removed client cannot authenticate the new epoch's confirmation
                // tag/context: upstream intentionally does not give it those secrets.
                // Preserve the authenticated authority record only as an INACTIVE
                // tombstone, never as a native-active context or Welcome anchor.
                let info = NativeGroupInfo { group_id: candidate.group_id().to_vec(),
                    epoch: ordered.target_epoch, members: approved,
                    member_leaf_indices: indices, group_context: ordered.group_context.clone(),
                    is_active: false };
                self.group = None;
                self.pending = None;
                self.rosters.clear();
                self.storage.erase()?;
                self.removed = Some(info.clone());
                Ok(info)
            }
            _ => Err(NativeError::InvalidMessage),
        }
    }
}

impl NativeSession {
    fn with<T>(&self, operation: impl FnOnce(&mut State) -> Result<T, NativeError>) -> Result<T, NativeError> {
        guarded(|| {
            let mut state = self.inner.lock().map_err(|_| NativeError::NativeFailure)?;
            operation(&mut state)
        })
    }
}

#[uniffi::export]
impl NativeSession {
    #[uniffi::constructor]
    pub fn new(credential: NativeCredential) -> Result<Arc<Self>, NativeError> {
        guarded(|| {
            credential.validate()?;
            let (signer, public) = cipher()?.signature_key_generate().map_err(|_| NativeError::NativeFailure)?;
            Ok(Arc::new(Self { inner: Mutex::new(State { credential, signer,
                mls_public_key: public.to_vec(), identity_signature: None,
                storage: HostStorage::default(), client: None, group: None, pending: None,
                rosters: BTreeMap::new(), removed: None }) }))
        })
    }

    #[uniffi::constructor]
    pub fn restore(secret_state: Vec<u8>, expected_credential: NativeCredential) -> Result<Arc<Self>, NativeError> {
        guarded(|| {
            let bytes = Zeroizing::new(secret_state);
            expected_credential.validate()?;
            if bytes.is_empty() || bytes.len() > MAX_SNAPSHOT { return Err(NativeError::InvalidInput); }
            let snapshot: Snapshot = serde_json::from_slice(&bytes).map_err(|_| NativeError::InvalidInput)?;
            if snapshot.version != 1 || snapshot.credential != expected_credential
                || snapshot.signer.len() != 64 || snapshot.mls_public_key.len() != 32
                || snapshot.rosters.len() > RETAINED_EPOCHS + 1 {
                return Err(NativeError::AuthenticationFailed);
            }
            let signer = SignatureSecretKey::new(snapshot.signer.to_vec());
            let derived = cipher()?.signature_key_derive_public(&signer).map_err(|_| NativeError::AuthenticationFailed)?;
            if derived.as_ref() != snapshot.mls_public_key.as_slice() { return Err(NativeError::AuthenticationFailed); }
            let storage = HostStorage::restored(snapshot.storage)?;
            let mut state = State { credential: snapshot.credential, signer, mls_public_key: snapshot.mls_public_key,
                identity_signature: Some(snapshot.identity_signature), storage,
                client: None, group: None, pending: snapshot.pending, rosters: snapshot.rosters,
                removed: snapshot.removed };
            let client = build_client(&state)?;
            if let Some(group_id) = state.storage.snapshot()?.group_id {
                if state.removed.is_some() { return Err(NativeError::InvalidState); }
                let group = client.load_group(&group_id).map_err(|_| NativeError::InvalidInput)?;
                if decode_identity(group.current_member_signing_identity().map_err(|_| NativeError::AuthenticationFailed)?)?.device
                    != state.credential || group.has_pending_commit() != state.pending.is_some() {
                    return Err(NativeError::AuthenticationFailed);
                }
                if let Some(pending) = &state.pending {
                    if pending.base_epoch != group.context().epoch || pending.target_epoch != next_epoch(pending.base_epoch)? {
                        return Err(NativeError::EpochMismatch);
                    }
                }
                state.group = Some(group);
                state.remember_roster()?;
            } else if state.pending.is_some() { return Err(NativeError::InvalidState); }
            state.client = Some(client);
            Ok(Arc::new(Self { inner: Mutex::new(state) }))
        })
    }

    pub fn binding_payload(&self) -> Result<Vec<u8>, NativeError> {
        self.with(|s| binding_payload(&s.credential, &s.mls_public_key))
    }
    pub fn certify(&self, identity_signature: Vec<u8>) -> Result<(), NativeError> {
        self.with(|s| {
            if s.client.is_some() || s.identity_signature.is_some() { return Err(NativeError::InvalidState); }
            let cert = BoundCredential { version: 1, device: s.credential.clone(),
                mls_signing_public_key: s.mls_public_key.clone(), identity_signature };
            cert.validate()?;
            s.identity_signature = Some(cert.identity_signature);
            s.client = Some(build_client(s)?);
            Ok(())
        })
    }
    pub fn create_group(&self, group_id: Vec<u8>) -> Result<NativeGroupInfo, NativeError> {
        self.with(|s| {
            if group_id.is_empty() || group_id.len() > 256 || s.group.is_some() || s.removed.is_some() {
                return Err(NativeError::InvalidState);
            }
            let group = s.client()?.create_group_with_id(group_id, Default::default(), Default::default(), None)
                .map_err(|_| NativeError::NativeFailure)?;
            s.group = Some(group);
            s.remember_roster()?;
            s.store()?;
            group_info(s.group()?)
        })
    }
    pub fn generate_key_package(&self) -> Result<Vec<u8>, NativeError> {
        self.with(|s| {
            if s.removed.is_some() || s.storage.package_count()? >= MAX_KEY_PACKAGES { return Err(NativeError::InvalidState); }
            s.client()?.generate_key_package_message(Default::default(), Default::default(), None)
                .map_err(|_| NativeError::NativeFailure)?.to_bytes().map_err(|_| NativeError::NativeFailure)
        })
    }
    pub fn join(&self, welcome: Vec<u8>, expected_group_id: Vec<u8>, expected_epoch: u64) -> Result<NativeGroupInfo, NativeError> {
        self.with(|s| {
            if s.group.is_some() || s.removed.is_some() { return Err(NativeError::InvalidState); }
            bounded(&welcome)?;
            let message = MlsMessage::from_bytes(&welcome).map_err(|_| NativeError::InvalidMessage)?;
            if message.cipher_suite() != Some(SUITE) { return Err(NativeError::InvalidMessage); }
            let (group, _) = s.client()?.join_group(None, &message, None).map_err(|_| NativeError::AuthenticationFailed)?;
            if group.group_id() != expected_group_id || group.context().epoch != expected_epoch {
                return Err(NativeError::EpochMismatch);
            }
            // Validate the complete signed roster before installing or deleting the one-use KeyPackage.
            let info = group_info(&group)?;
            if !info.members.iter().any(|m| m == &s.credential) { return Err(NativeError::AuthenticationFailed); }
            s.group = Some(group);
            s.remember_roster()?;
            s.store()?;
            Ok(info)
        })
    }
    pub fn info(&self) -> Result<NativeGroupInfo, NativeError> {
        self.with(|s| match &s.removed { Some(info) => Ok(info.clone()), None => group_info(s.group()?) })
    }
    pub fn snapshot(&self) -> Result<Vec<u8>, NativeError> { self.with(State::snapshot) }
    pub fn pending_commit(&self) -> Result<Option<NativeStagedCommit>, NativeError> { self.with(|s| Ok(s.pending.clone())) }

    pub fn stage_add(&self, key_package: Vec<u8>, authenticated_credential: NativeCredential,
        expected_epoch: u64) -> Result<NativeStagedCommit, NativeError> {
        self.with(|s| {
            authenticated_credential.validate()?;
            bounded(&key_package)?;
            if s.pending.is_some() || s.group()?.context().epoch != expected_epoch { return Err(NativeError::EpochMismatch); }
            let message = MlsMessage::from_bytes(&key_package).map_err(|_| NativeError::InvalidMessage)?;
            let package = message.as_key_package().ok_or(NativeError::InvalidMessage)?;
            if package.cipher_suite != SUITE || decode_identity(package.signing_identity())?.device != authenticated_credential {
                return Err(NativeError::AuthenticationFailed);
            }
            let mut roster = members(s.group()?)?;
            if roster.iter().any(|m| m.device_id == authenticated_credential.device_id) { return Err(NativeError::AuthenticationFailed); }
            roster.push(authenticated_credential);
            let roster = sorted(roster)?;
            let mut staged_group = s.group()?.clone();
            let output = staged_group.commit_builder().add_member(message).map_err(|_| NativeError::InvalidMessage)?
                .build().map_err(|_| NativeError::AuthenticationFailed)?;
            if output.welcome_messages.len() != 1 { return Err(NativeError::NativeFailure); }
            let prospective = prospective_info(&staged_group)?;
            if prospective.members != roster { return Err(NativeError::AuthenticationFailed); }
            let staged = NativeStagedCommit { base_epoch: expected_epoch, target_epoch: next_epoch(expected_epoch)?,
                commit: output.commit_message.to_bytes().map_err(|_| NativeError::NativeFailure)?,
                welcome: Some(output.welcome_messages[0].to_bytes().map_err(|_| NativeError::NativeFailure)?),
                members: prospective.members, member_leaf_indices: prospective.member_leaf_indices,
                group_context: prospective.group_context };
            s.group = Some(staged_group);
            s.pending = Some(staged.clone());
            s.store()?;
            Ok(staged)
        })
    }
    pub fn stage_remove(&self, device_id: String, expected_epoch: u64) -> Result<NativeStagedCommit, NativeError> {
        self.with(|s| {
            if s.pending.is_some() || s.group()?.context().epoch != expected_epoch { return Err(NativeError::EpochMismatch); }
            // MLS does not allow a committer to remove itself; another paired device does so.
            if device_id == s.credential.device_id { return Err(NativeError::InvalidInput); }
            let entry = roster(s.group()?)?.into_iter().find(|m| m.credential.device_id == device_id)
                .ok_or(NativeError::InvalidInput)?;
            let mut approved = members(s.group()?)?;
            approved.retain(|m| m.device_id != device_id);
            let mut staged_group = s.group()?.clone();
            let output = staged_group.commit_builder().remove_member(entry.index).map_err(|_| NativeError::InvalidInput)?
                .build().map_err(|_| NativeError::NativeFailure)?;
            let prospective = prospective_info(&staged_group)?;
            if prospective.members != approved { return Err(NativeError::AuthenticationFailed); }
            let staged = NativeStagedCommit { base_epoch: expected_epoch, target_epoch: next_epoch(expected_epoch)?,
                commit: output.commit_message.to_bytes().map_err(|_| NativeError::NativeFailure)?, welcome: None,
                members: prospective.members, member_leaf_indices: prospective.member_leaf_indices,
                group_context: prospective.group_context };
            s.group = Some(staged_group);
            s.pending = Some(staged.clone());
            s.store()?;
            Ok(staged)
        })
    }
    pub fn stage_update(&self, expected_epoch: u64) -> Result<NativeStagedCommit, NativeError> {
        self.with(|s| {
            if s.pending.is_some() || s.group()?.context().epoch != expected_epoch { return Err(NativeError::EpochMismatch); }
            let approved = members(s.group()?)?;
            let mut staged_group = s.group()?.clone();
            let output = staged_group.commit(Vec::new()).map_err(|_| NativeError::NativeFailure)?;
            let prospective = prospective_info(&staged_group)?;
            if prospective.members != approved { return Err(NativeError::AuthenticationFailed); }
            let staged = NativeStagedCommit { base_epoch: expected_epoch, target_epoch: next_epoch(expected_epoch)?,
                commit: output.commit_message.to_bytes().map_err(|_| NativeError::NativeFailure)?, welcome: None,
                members: prospective.members, member_leaf_indices: prospective.member_leaf_indices,
                group_context: prospective.group_context };
            s.group = Some(staged_group);
            s.pending = Some(staged.clone());
            s.store()?;
            Ok(staged)
        })
    }
    pub fn accept_pending_commit(&self, ordered: NativeOrderedCommit) -> Result<NativeGroupInfo, NativeError> {
        self.with(|s| {
            check_order(s.group()?, &ordered)?;
            let pending = s.pending.as_ref().ok_or(NativeError::InvalidState)?;
            if pending.commit != ordered.commit || sorted(pending.members.clone())? != sorted(ordered.members.clone())?
                || pending.member_leaf_indices != ordered.member_leaf_indices
                || pending.group_context != ordered.group_context {
                return Err(NativeError::AuthenticationFailed);
            }
            let mut candidate = s.group()?.clone();
            let result = candidate.apply_pending_commit().map_err(|_| NativeError::InvalidMessage)?;
            s.install_commit(candidate, result.effect, &ordered)
        })
    }
    pub fn apply(&self, ordered: NativeOrderedCommit) -> Result<NativeGroupInfo, NativeError> {
        self.with(|s| {
            let message = check_order(s.group()?, &ordered)?;
            // Copy only for this authenticated state transition: a rejected commit must not
            // consume ratchets, replace a staged proposal, or install an unapproved roster.
            let mut candidate = s.group()?.clone();
            let ReceivedMessage::Commit(result) = candidate.process_incoming_message(message)
                .map_err(|_| NativeError::InvalidMessage)? else { return Err(NativeError::InvalidMessage); };
            if result.is_external { return Err(NativeError::AuthenticationFailed); }
            s.install_commit(candidate, result.effect, &ordered)
        })
    }
    pub fn discard_pending_commit(&self) -> Result<(), NativeError> {
        self.with(|s| { s.group_mut()?.clear_pending_commit(); s.pending = None; s.store() })
    }
    pub fn seal(&self, plaintext: Vec<u8>, authenticated_data: Vec<u8>) -> Result<NativeSealedMessage, NativeError> {
        self.with(|s| {
            if plaintext.len() > MAX_MESSAGE - 65536 || authenticated_data.len() > 4096 { return Err(NativeError::InvalidInput); }
            if s.pending.is_some() { return Err(NativeError::InvalidState); }
            let epoch = s.group()?.context().epoch;
            let message = s.group_mut()?.encrypt_application_message(&plaintext, authenticated_data)
                .map_err(|_| NativeError::NativeFailure)?;
            let ciphertext = message.to_bytes().map_err(|_| NativeError::NativeFailure)?;
            s.store()?;
            Ok(NativeSealedMessage { ciphertext, group_epoch: epoch })
        })
    }
    pub fn open(&self, ciphertext: Vec<u8>) -> Result<NativeOpenedMessage, NativeError> {
        self.with(|s| {
            bounded(&ciphertext)?;
            let message = MlsMessage::from_bytes(&ciphertext).map_err(|_| NativeError::InvalidMessage)?;
            let epoch = match message.description() {
                MlsMessageDescription::PrivateProtocolMessage { group_id, epoch_id, content_type: ContentType::Application }
                    if group_id == s.group()?.group_id() => epoch_id,
                _ => return Err(NativeError::InvalidMessage),
            };
            let mut candidate = s.group()?.clone();
            let ReceivedMessage::ApplicationMessage(application) = candidate.process_incoming_message(message)
                .map_err(|_| NativeError::InvalidMessage)? else { return Err(NativeError::InvalidMessage); };
            let sender = s.rosters.get(&epoch).and_then(|roster| roster.iter().find(|m| m.index == application.sender_index))
                .ok_or(NativeError::AuthenticationFailed)?.credential.clone();
            // The sender index is epoch-relative. Never resolve an old message with today's
            // roster (an index can have been reused after remove/add).
            if !members(&candidate)?.contains(&sender) { return Err(NativeError::AuthenticationFailed); }
            let result = NativeOpenedMessage { plaintext: application.data().to_vec(),
                authenticated_data: application.authenticated_data.clone(), sender, group_epoch: epoch };
            candidate.write_to_storage().map_err(|_| NativeError::StorageFailure)?;
            s.group = Some(candidate);
            Ok(result)
        })
    }
    pub fn export_secret(&self, label: Vec<u8>, context: Vec<u8>, length: u32) -> Result<Vec<u8>, NativeError> {
        self.with(|s| {
            if label.is_empty() || label.len() > 255 || context.len() > 4096 || length == 0 || length > 4096 {
                return Err(NativeError::InvalidInput);
            }
            Ok(s.group()?.export_secret(&label, &context, length as usize)
                .map_err(|_| NativeError::NativeFailure)?.as_bytes().to_vec())
        })
    }
    pub fn delete_exporter(&self) -> Result<(), NativeError> {
        self.with(|s| { s.group_mut()?.delete_exporter(); s.store() })
    }
}
