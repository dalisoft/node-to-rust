use std::path::PathBuf;

use clap::Parser;
use my_lib::Module;

#[macro_use]
extern crate log;

#[derive(Parser)]
#[command(
    name = "wasm-runner",
    about = "Sample project from https://vino.dev/blog/node-to-rust-day-1-rustup/"
)]
struct CliOptions {
    /// The WebAssembly file to load.
    pub(crate) file_path: PathBuf,
}

fn main() {
    env_logger::init();
    debug!("Initialized logger");

    let options = CliOptions::parse();

    match Module::from_file(&options.file_path) {
        Ok(_) => {
            info!("Module loaded");
        }
        Err(e) => {
            error!("Module failed to load: {}", e);
        }
    }
}
