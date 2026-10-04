use std::{fs, path::PathBuf};

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

    /// The operation to invoke in the WASM file.
    pub(crate) operation: String,

    /// The path to the JSON data to use as input.
    pub(crate) json_path: PathBuf,
}

fn main() {
    env_logger::init();
    debug!("Initialized logger");

    let options = CliOptions::parse();

    match run(options) {
        Ok(output) => {
            println!("{}", output);
            info!("Done");
        }
        Err(e) => {
            error!("Module failed to load: {}", e);
            std::process::exit(1);
        }
    };
}

fn run(options: CliOptions) -> anyhow::Result<serde_json::Value> {
    let module = Module::from_file(&options.file_path)?;
    info!("Module loaded");

    let json = fs::read_to_string(options.json_path)?;
    let data: serde_json::Value = serde_json::from_str(&json)?;
    debug!("Data: {:?}", data);

    let bytes = rmp_serde::to_vec(&data)?;

    debug!("Running  {} with payload: {:?}", options.operation, bytes);
    let result = module.run(&options.operation, &bytes)?;
    let unpacked: serde_json::Value = rmp_serde::from_slice(&result)?;

    Ok(unpacked)
}
