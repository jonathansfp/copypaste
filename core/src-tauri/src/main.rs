// Sem janela de console no Windows.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    copypaste_lib::run();
}
