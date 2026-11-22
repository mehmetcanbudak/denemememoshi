// Copyright 2026 Memoshi contributors. SPDX-License-Identifier: Apache-2.0
// Memory-only backing store. The Swift host encrypts/fsyncs the complete snapshot.
use crate::NativeError;
use mls_rs_core::{group::{EpochRecord, GroupState, GroupStateStorage},
    key_package::{KeyPackageData, KeyPackageStorage}};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fmt, sync::{Arc, Mutex, MutexGuard}};
use zeroize::Zeroizing;

pub(crate) const RETAINED_EPOCHS: usize = 3;
pub(crate) const MAX_KEY_PACKAGES: usize = 32;

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct StoredData {
    pub group_id: Option<Vec<u8>>,
    pub group_state: Option<Zeroizing<Vec<u8>>>,
    pub epochs: BTreeMap<u64, Zeroizing<Vec<u8>>>,
    pub key_packages: Vec<StoredPackage>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct StoredPackage {
    pub id: Vec<u8>,
    pub data: KeyPackageData,
}

#[derive(Clone, Default)]
pub(crate) struct HostStorage(Arc<Mutex<StoredData>>);

impl fmt::Debug for HostStorage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str("HostStorage(<redacted>)") }
}

impl HostStorage {
    pub fn restored(data: StoredData) -> Result<Self, NativeError> {
        if data.epochs.len() > RETAINED_EPOCHS || data.key_packages.len() > MAX_KEY_PACKAGES
            || data.group_id.is_some() != data.group_state.is_some() {
            return Err(NativeError::InvalidInput);
        }
        Ok(Self(Arc::new(Mutex::new(data))))
    }
    fn lock(&self) -> Result<MutexGuard<'_, StoredData>, NativeError> {
        self.0.lock().map_err(|_| NativeError::StorageFailure)
    }
    pub fn snapshot(&self) -> Result<StoredData, NativeError> { Ok(self.lock()?.clone()) }
    pub fn package_count(&self) -> Result<usize, NativeError> { Ok(self.lock()?.key_packages.len()) }
    pub fn erase(&self) -> Result<(), NativeError> { *self.lock()? = StoredData::default(); Ok(()) }
}

impl KeyPackageStorage for HostStorage {
    type Error = NativeError;
    fn delete(&mut self, id: &[u8]) -> Result<(), Self::Error> {
        self.lock()?.key_packages.retain(|p| p.id != id);
        Ok(())
    }
    fn insert(&mut self, id: Vec<u8>, pkg: KeyPackageData) -> Result<(), Self::Error> {
        let mut data = self.lock()?;
        if data.key_packages.iter().any(|p| p.id == id) || data.key_packages.len() >= MAX_KEY_PACKAGES {
            return Err(NativeError::InvalidState);
        }
        data.key_packages.push(StoredPackage { id, data: pkg });
        Ok(())
    }
    fn get(&self, id: &[u8]) -> Result<Option<KeyPackageData>, Self::Error> {
        Ok(self.lock()?.key_packages.iter().find(|p| p.id == id).map(|p| p.data.clone()))
    }
}

impl GroupStateStorage for HostStorage {
    type Error = NativeError;
    fn state(&self, group_id: &[u8]) -> Result<Option<Zeroizing<Vec<u8>>>, Self::Error> {
        let data = self.lock()?;
        Ok(if data.group_id.as_deref() == Some(group_id) { data.group_state.clone() } else { None })
    }
    fn epoch(&self, group_id: &[u8], epoch_id: u64) -> Result<Option<Zeroizing<Vec<u8>>>, Self::Error> {
        let data = self.lock()?;
        Ok(if data.group_id.as_deref() == Some(group_id) { data.epochs.get(&epoch_id).cloned() } else { None })
    }
    fn write(&mut self, state: GroupState, inserts: Vec<EpochRecord>, updates: Vec<EpochRecord>) -> Result<(), Self::Error> {
        let mut data = self.lock()?;
        if data.group_id.as_deref().is_some_and(|id| id != state.id) {
            return Err(NativeError::InvalidState);
        }
        data.group_id = Some(state.id);
        data.group_state = Some(state.data);
        for record in inserts { data.epochs.insert(record.id, record.data); }
        for record in updates {
            if let Some(epoch) = data.epochs.get_mut(&record.id) { *epoch = record.data; }
        }
        while data.epochs.len() > RETAINED_EPOCHS { data.epochs.pop_first(); }
        Ok(())
    }
    fn max_epoch_id(&self, group_id: &[u8]) -> Result<Option<u64>, Self::Error> {
        let data = self.lock()?;
        Ok(if data.group_id.as_deref() == Some(group_id) { data.epochs.last_key_value().map(|(id, _)| *id) } else { None })
    }
}
