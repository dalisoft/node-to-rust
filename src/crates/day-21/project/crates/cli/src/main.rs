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

    /// The operation to invoke in the WASM file.
    pub(crate) operation: String,

    /// The data to pass to the operation
    pub(crate) data: String,
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

fn run(options: CliOptions) -> anyhow::Result<String> {
    let module = Module::from_file(&options.file_path)?;
    info!("Module loaded");

    let bytes = rmp_serde::to_vec(&options.data)?;
    let result = module.run(&options.operation, &bytes)?;
    let unpacked: String = rmp_serde::from_slice(&result)?;

    Ok(unpacked)
}
