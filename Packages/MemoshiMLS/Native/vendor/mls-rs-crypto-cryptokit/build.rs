// Memoshi build adapter for the pinned upstream CryptoKit provider.
// Does not install tools or alter global Swift/Cargo configuration.
use std::{env, path::PathBuf, process::Command};

fn output(command: &mut Command) -> Vec<u8> {
    let result = command.output().expect("Apple toolchain could not be launched");
    if !result.status.success() {
        eprintln!("{}", String::from_utf8_lossy(&result.stderr));
        panic!("Apple toolchain command failed");
    }
    result.stdout
}

fn main() {
    let target = env::var("TARGET").expect("Cargo target required");
    let (sdk, triple) = match target.as_str() {
        "aarch64-apple-darwin" => ("macosx", "arm64-apple-macosx27.0"),
        "aarch64-apple-ios" => ("iphoneos", "arm64-apple-ios27.0"),
        "aarch64-apple-ios-sim" => ("iphonesimulator", "arm64-apple-ios27.0-simulator"),
        _ => panic!("MemoshiMLS supports only the declared Apple arm64 targets"),
    };
    let sdk_path = String::from_utf8(output(Command::new("xcrun").args([
        "--sdk", sdk, "--show-sdk-path",
    ]))).expect("SDK path encoding");
    let sdk_path = sdk_path.trim();
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output required"));
    let sources = PathBuf::from("cryptokit-bridge/Sources/cryptokit-bridge");
    let mut compile = Command::new("xcrun");
    compile.args(["--sdk", sdk, "swiftc", "-emit-library", "-static", "-parse-as-library",
        "-module-name", "MemoshiCryptoKitBridge", "-swift-version", "5", "-O",
        "-target", triple, "-sdk", sdk_path]);
    for file in ["cryptokit-bridge.swift", "aead.swift", "kdf.swift", "kem.swift", "random.swift", "sig.swift"] {
        let path = sources.join(file);
        println!("cargo:rerun-if-changed={}", path.display());
        compile.arg(path);
    }
    compile.arg("-o").arg(out_dir.join("libmemoshi_cryptokit_bridge.a"));
    output(&mut compile);

    let info: serde_json::Value = serde_json::from_slice(&output(Command::new("xcrun").args([
        "--sdk", sdk, "swiftc", "-print-target-info", "-target", triple, "-sdk", sdk_path,
    ]))).expect("Swift target metadata required");
    for path in info["paths"]["runtimeLibraryPaths"].as_array().expect("Swift runtime paths required") {
        println!("cargo:rustc-link-search=native={}", path.as_str().expect("Swift runtime path"));
    }
    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=memoshi_cryptokit_bridge");
    println!("cargo:rustc-link-lib=dylib=swiftCore");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=framework=CryptoKit");
    println!("cargo:rustc-link-lib=framework=Security");
    println!("cargo:rerun-if-env-changed=DEVELOPER_DIR");
}
