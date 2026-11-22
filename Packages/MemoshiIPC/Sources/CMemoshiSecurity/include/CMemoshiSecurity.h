#ifndef MEMOSHI_SECURITY_H
#define MEMOSHI_SECURITY_H

#include <CoreFoundation/CoreFoundation.h>
#include <Security/CSCommon.h>
#include <Security/SecBase.h>
#include <stdint.h>

CF_ASSUME_NONNULL_BEGIN

/* Every check validates a dynamic SecCodeRef, never a path or PID lookup. Returned objects
 * follow the Copy rule. No audit token crosses this ABI. */
OSStatus MMSCopySelfSigningInformation(
    CFDictionaryRef _Nullable * _Nonnull CF_RETURNS_RETAINED information);

/* The descriptor-bound half of a peer check, on the connection's own descriptor: the peer's
 * user, its audit token from that descriptor, and the running code the token selects. The
 * code is located, not yet validated. */
OSStatus MMSCopyPeerGuest(
    int socketFD, uint32_t *uid, int *systemError,
    SecCodeRef _Nullable * _Nonnull CF_RETURNS_RETAINED code);

/* The other half, which can be slow and may run on any thread: SecCodeCheckValidity against
 * the requirement, then the signing information and the hardened checks below. */
OSStatus MMSCopyGuestSigningInformation(
    SecCodeRef code, CFStringRef requirement,
    CFDictionaryRef _Nullable * _Nonnull CF_RETURNS_RETAINED information);

/* The signing-information half of the checks above, applied after the signature and the
 * requirement have validated: hardened runtime, not ad hoc, valid and not debugged, a team, an
 * identifier, certificates, a CMS blob, and no runtime-exception entitlement that is not false. */
int MMSSigningInformationIsHardened(CFDictionaryRef information);

/* Fixed-size caller-owned buffers; the comparison examines every byte. */
int MMSConstantTimeEqual(const uint8_t *left, const uint8_t *right, size_t count);

CF_ASSUME_NONNULL_END
#endif
