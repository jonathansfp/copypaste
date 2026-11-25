fn main() {
    // CP_CROSS_CHECK=1 lets you `cargo check --target x86_64-pc-windows-msvc` from another system
    // (where there is no Windows resource compiler). Normal builds ignore it.
    if std::env::var_os("CP_CROSS_CHECK").is_some() {
        let _ = std::panic::catch_unwind(tauri_build::build);
        return;
    }
    tauri_build::build()
}
