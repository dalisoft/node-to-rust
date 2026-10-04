use std::path::PathBuf;

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error(transparent)]
    EngineError(#[from] wasmtime_provider::errors::Error),
    #[error(transparent)]
    WapcError(#[from] wapc::errors::Error),
    #[error("Could not read file {0}: {1}")]
    FileNotReadable(PathBuf, String),
}
