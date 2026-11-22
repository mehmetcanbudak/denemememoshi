// Copyright 2026 Memoshi contributors. SPDX-License-Identifier: Apache-2.0
// RFC 9420 is implemented by pinned mls-rs, never by this adapter.
mod credential;
mod session;
mod storage;

pub use credential::NativeCredential;
pub use session::{NativeGroupInfo, NativeOpenedMessage, NativeOrderedCommit, NativeSealedMessage,
    NativeSession, NativeStagedCommit};

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, Copy, thiserror::Error, uniffi::Error)]
pub enum NativeError {
    #[error("invalid MLS input")]
    InvalidInput,
    #[error("MLS operation is not valid in the current state")]
    InvalidState,
    #[error("MLS device authentication failed")]
    AuthenticationFailed,
    #[error("MLS authority epoch does not match")]
    EpochMismatch,
    #[error("MLS message is invalid, stale, or already consumed")]
    InvalidMessage,
    #[error("MLS state storage failed")]
    StorageFailure,
    #[error("native MLS operation failed")]
    NativeFailure,
}

impl mls_rs_core::error::IntoAnyError for NativeError {}

// No upstream error strings, panic payloads, credentials, or secrets cross the FFI.
fn guarded<T>(operation: impl FnOnce() -> Result<T, NativeError>) -> Result<T, NativeError> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(operation))
        .unwrap_or(Err(NativeError::NativeFailure))
}
