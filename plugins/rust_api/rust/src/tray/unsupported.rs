use crate::api::tray::{TrayEvent, TraySpec};
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::SseCodec;

/// The Rust tray is Linux-only for now; the other desktops keep the Flutter
/// `tray` plugin until their backends land.
pub fn set(_spec: TraySpec) -> Result<(), String> {
    Err("the Rust tray is not implemented on this platform yet".into())
}

pub fn hide() -> Result<(), String> {
    Ok(())
}

pub fn set_title(_title: String) -> Result<(), String> {
    Ok(())
}

pub fn listen(_sink: StreamSink<TrayEvent, SseCodec>) -> Result<(), String> {
    Ok(())
}
