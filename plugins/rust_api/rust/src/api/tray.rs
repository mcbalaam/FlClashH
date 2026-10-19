use crate::frb_generated::StreamSink;
use crate::tray;
use flutter_rust_bridge::for_generated::SseCodec;
use flutter_rust_bridge::frb;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayItemKind {
    Action,
    Checkbox,
    Radio,
    Status,
    Separator,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayItem {
    pub id: i32,
    pub kind: TrayItemKind,
    pub label: String,
    pub detail: Option<String>,
    pub enabled: bool,
    pub checked: bool,
    pub connected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraySpec {
    pub tool_tip: String,
    pub title: String,
    pub visible: bool,
    pub icon_width: u32,
    pub icon_height: u32,
    pub icon_rgba: Vec<u8>,
    pub items: Vec<TrayItem>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayEventKind {
    Activate,
    MenuRequested,
    ItemSelected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TrayEvent {
    pub kind: TrayEventKind,
    pub id: i32,
}

#[frb]
pub fn tray_set(spec: TraySpec) -> Result<(), String> {
    tray::set(spec)
}

#[frb]
pub fn tray_hide() -> Result<(), String> {
    tray::hide()
}

#[frb]
pub fn tray_set_title(title: String) -> Result<(), String> {
    tray::set_title(title)
}

#[frb]
pub fn tray_events(sink: StreamSink<TrayEvent, SseCodec>) -> Result<(), String> {
    tray::listen(sink)
}
