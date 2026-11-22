#include "CMemoshiSecurity.h"
#include <Security/SecCode.h>
#include <Security/SecRequirement.h>
#include <bsm/libbsm.h>
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int runtimeException(CFStringRef key) {
  return CFStringHasPrefix(key, CFSTR("com.apple.security.cs.")) ||
      CFEqual(key, CFSTR("com.apple.security.get-task-allow")) ||
      CFEqual(key, CFSTR("get-task-allow")) ||
      CFEqual(key, CFSTR("dynamic-codesigning")) ||
      CFEqual(key, CFSTR("com.apple.private.security.clear-library-validation")) ||
      CFEqual(key, CFSTR("com.apple.private.cs.debugger"));
}

static void checkEntitlement(const void *key, const void *value, void *context) {
  int *valid = context;
  if (CFGetTypeID(key) != CFStringGetTypeID() ||
      (runtimeException(key) && value != kCFBooleanFalse)) {
    *valid = 0;
  }
}

int MMSSigningInformationIsHardened(CFDictionaryRef information) {
  CFTypeRef flags = CFDictionaryGetValue(information, kSecCodeInfoFlags);
  CFTypeRef dynamic = CFDictionaryGetValue(information, kSecCodeInfoStatus);
  CFTypeRef team = CFDictionaryGetValue(information, kSecCodeInfoTeamIdentifier);
  CFTypeRef identifier = CFDictionaryGetValue(information, kSecCodeInfoIdentifier);
  CFTypeRef certificates = CFDictionaryGetValue(information, kSecCodeInfoCertificates);
  CFTypeRef cms = CFDictionaryGetValue(information, kSecCodeInfoCMS);
  uint32_t bits = 0;
  uint32_t dynamicBits = 0;
  if (flags == NULL || CFGetTypeID(flags) != CFNumberGetTypeID() ||
      dynamic == NULL || CFGetTypeID(dynamic) != CFNumberGetTypeID() ||
      !CFNumberGetValue(flags, kCFNumberSInt32Type, &bits) ||
      !CFNumberGetValue(dynamic, kCFNumberSInt32Type, &dynamicBits) ||
      !(bits & kSecCodeSignatureRuntime) || (bits & kSecCodeSignatureAdhoc) ||
      !(dynamicBits & kSecCodeStatusValid) || (dynamicBits & kSecCodeStatusDebugged) ||
      team == NULL || CFGetTypeID(team) != CFStringGetTypeID() ||
      CFStringGetLength(team) == 0 ||
      identifier == NULL || CFGetTypeID(identifier) != CFStringGetTypeID() ||
      CFStringGetLength(identifier) == 0 ||
      certificates == NULL || CFGetTypeID(certificates) != CFArrayGetTypeID() ||
      CFArrayGetCount(certificates) == 0 ||
      cms == NULL || CFGetTypeID(cms) != CFDataGetTypeID() || CFDataGetLength(cms) == 0) {
    return 0;
  }
  CFTypeRef entitlements = CFDictionaryGetValue(information, kSecCodeInfoEntitlementsDict);
  if (entitlements == NULL) {
    return CFDictionaryGetValue(information, kSecCodeInfoEntitlements) == NULL;
  }
  if (CFGetTypeID(entitlements) != CFDictionaryGetTypeID()) return 0;
  int valid = 1;
  CFDictionaryApplyFunction(entitlements, checkEntitlement, &valid);
  return valid;
}

static OSStatus copyValidatedInformation(
    SecCodeRef code, CFStringRef text, CFDictionaryRef *information) {
  SecRequirementRef requirement = NULL;
  OSStatus status = SecRequirementCreateWithString(text, kSecCSDefaultFlags, &requirement);
  if (status != errSecSuccess) return status;
  status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
  if (status == errSecSuccess) {
    /* SecCode.h explicitly permits a Code or StaticCode here. Its C declaration
     * uses SecStaticCodeRef; the documented dynamic case needs this C-only cast. */
    status = SecCodeCopySigningInformation(
        (SecStaticCodeRef)code, kSecCSSigningInformation | kSecCSDynamicInformation,
        information);
  }
  if (status == errSecSuccess) {
    status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
    if (status == errSecSuccess && !MMSSigningInformationIsHardened(*information)) {
      status = errSecAuthFailed;
    }
    if (status != errSecSuccess && *information != NULL) {
      CFRelease(*information);
      *information = NULL;
    }
  }
  CFRelease(requirement);
  return status;
}

OSStatus MMSCopySelfSigningInformation(CFDictionaryRef *information) {
  *information = NULL;
  if (getuid() != geteuid()) return errSecAuthFailed;
  SecCodeRef code = NULL;
  OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &code);
  if (status == errSecSuccess) {
    status = copyValidatedInformation(code, CFSTR("anchor apple generic"), information);
    CFRelease(code);
  }
  return status;
}

OSStatus MMSCopyPeerGuest(
    int socketFD, uint32_t *uid, int *systemError, SecCodeRef *code) {
  *code = NULL;
  *systemError = 0;
  *uid = UINT32_MAX;
  uid_t peerUID;
  gid_t peerGID;
  if (getpeereid(socketFD, &peerUID, &peerGID) != 0) {
    *systemError = errno;
    return errSecAuthFailed;
  }
  if (getuid() != geteuid() || peerUID != geteuid()) return errSecAuthFailed;

  audit_token_t token = {0};
  socklen_t size = sizeof(token);
  if (getsockopt(socketFD, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) != 0) {
    *systemError = errno;
    return errSecAuthFailed;
  }
  if (size != sizeof(token) || audit_token_to_euid(token) != peerUID ||
      audit_token_to_ruid(token) != peerUID) {
    memset_s(&token, sizeof(token), 0, sizeof(token));
    return errSecAuthFailed;
  }
  CFDataRef audit = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&token, sizeof(token));
  memset_s(&token, sizeof(token), 0, sizeof(token));
  if (audit == NULL) return errSecAllocate;
  const void *keys[] = {kSecGuestAttributeAudit};
  const void *values[] = {audit};
  CFDictionaryRef attributes = CFDictionaryCreate(
      kCFAllocatorDefault, keys, values, 1,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFRelease(audit);
  if (attributes == NULL) return errSecAllocate;
  OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, code);
  CFRelease(attributes);
  if (status == errSecSuccess) *uid = (uint32_t)peerUID;
  return status;
}

OSStatus MMSCopyGuestSigningInformation(
    SecCodeRef code, CFStringRef requirement, CFDictionaryRef *information) {
  *information = NULL;
  return copyValidatedInformation(code, requirement, information);
}

int MMSConstantTimeEqual(const uint8_t *left, const uint8_t *right, size_t count) {
  volatile uint8_t difference = 0;
  for (size_t index = 0; index < count; ++index) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
