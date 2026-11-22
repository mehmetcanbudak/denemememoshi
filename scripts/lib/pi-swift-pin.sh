# Memoshi's Pi_Swift pin (D134). This file is the one place that names it; every other
# mention must agree, and scripts/check-prerequisites.sh checks the ones that matter.
#
# Packages/MemoshiCore/Package.swift uses Pi_Swift by path, from PI_SWIFT_CHECKOUT: a clean
# clone that scripts/check-prerequisites.sh creates from ../Pi_Swift and checks out at
# PI_SWIFT_REVISION. SwiftPM cannot pin this commit by revision: its manifest depends on the
# local package Vendor/SwiftBashParser, and SwiftPM refuses a local package dependency under
# a revision requirement. Read by shell (`source`) and by scripts/release.py.
PI_SWIFT_TAG=slice-2.2
PI_SWIFT_REVISION=56d6fc89ebb039ad1b5e9128c8b12131d92d0cbe
PI_SWIFT_CHECKOUT=../Pi_Swift-slice-2.2
