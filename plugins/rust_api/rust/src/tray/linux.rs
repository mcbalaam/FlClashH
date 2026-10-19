use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Mutex, OnceLock};
use std::thread;

use ksni::blocking::{Handle, TrayMethods};
use ksni::menu::{CheckmarkItem, MenuItem, RadioGroup, RadioItem, StandardItem};
use ksni::{Icon, Status, Tray};

use crate::api::tray::{TrayEvent, TrayEventKind, TrayItem, TrayItemKind, TraySpec};
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::SseCodec;

static SINK: Mutex<Option<StreamSink<TrayEvent, SseCodec>>> = Mutex::new(None);
static COMMANDS: OnceLock<Sender<Command>> = OnceLock::new();

enum Command {
    Set(TraySpec),
    Hide,
    SetTitle,
}

fn emit(kind: TrayEventKind, id: i32) {
    if let Ok(guard) = SINK.lock() {
        if let Some(sink) = guard.as_ref() {
            let _ = sink.add(TrayEvent { kind, id });
        }
    }
}

fn label_of(item: &TrayItem) -> String {
    match item.detail.as_deref() {
        Some(detail) if !detail.is_empty() => format!("{}  ({})", item.label, detail),
        _ => item.label.clone(),
    }
}

fn icon_of(spec: &TraySpec) -> Vec<Icon> {
    if spec.icon_rgba.is_empty() || spec.icon_width == 0 || spec.icon_height == 0 {
        return Vec::new();
    }
    let mut data = Vec::with_capacity(spec.icon_rgba.len());
    for pixel in spec.icon_rgba.chunks_exact(4) {
        data.push(pixel[3]);
        data.push(pixel[0]);
        data.push(pixel[1]);
        data.push(pixel[2]);
    }
    vec![Icon {
        width: spec.icon_width as i32,
        height: spec.icon_height as i32,
        data,
    }]
}

fn build_menu(spec: &TraySpec) -> Vec<MenuItem<LinuxTray>> {
    let mut menu: Vec<MenuItem<LinuxTray>> = Vec::new();
    let mut radios: Vec<&TrayItem> = Vec::new();

    for item in &spec.items {
        if item.kind == TrayItemKind::Radio {
            radios.push(item);
            continue;
        }
        if !radios.is_empty() {
            menu.push(radio_group(std::mem::take(&mut radios)));
        }
        match item.kind {
            TrayItemKind::Separator => menu.push(MenuItem::Separator),
            TrayItemKind::Status => menu.push(
                StandardItem {
                    label: item.label.clone(),
                    icon_name: "media-record".into(),
                    enabled: false,
                    ..Default::default()
                }
                .into(),
            ),
            TrayItemKind::Checkbox => {
                let id = item.id;
                menu.push(
                    CheckmarkItem {
                        label: label_of(item),
                        enabled: item.enabled,
                        checked: item.checked,
                        activate: Box::new(move |_tray: &mut LinuxTray| {
                            emit(TrayEventKind::ItemSelected, id);
                        }),
                        ..Default::default()
                    }
                    .into(),
                );
            }
            _ => {
                let id = item.id;
                menu.push(
                    StandardItem {
                        label: label_of(item),
                        enabled: item.enabled,
                        activate: Box::new(move |_tray: &mut LinuxTray| {
                            emit(TrayEventKind::ItemSelected, id);
                        }),
                        ..Default::default()
                    }
                    .into(),
                );
            }
        }
    }
    if !radios.is_empty() {
        menu.push(radio_group(radios));
    }
    menu
}

fn radio_group(items: Vec<&TrayItem>) -> MenuItem<LinuxTray> {
    let ids: Vec<i32> = items.iter().map(|item| item.id).collect();
    let selected = items.iter().position(|item| item.checked).unwrap_or(0);
    let options = items
        .iter()
        .map(|item| RadioItem {
            label: label_of(item),
            enabled: item.enabled,
            ..Default::default()
        })
        .collect();
    RadioGroup {
        selected,
        select: Box::new(move |_tray: &mut LinuxTray, index: usize| {
            if let Some(id) = ids.get(index) {
                emit(TrayEventKind::ItemSelected, *id);
            }
        }),
        options,
    }
    .into()
}

struct LinuxTray {
    spec: TraySpec,
    visible: bool,
}

impl Tray for LinuxTray {
    const MENU_ON_ACTIVATE: bool = false;

    fn id(&self) -> String {
        "flclash".into()
    }

    fn title(&self) -> String {
        self.spec.tool_tip.clone()
    }

    fn status(&self) -> Status {
        if self.visible {
            Status::Active
        } else {
            Status::Passive
        }
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        icon_of(&self.spec)
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        emit(TrayEventKind::Activate, 0);
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        build_menu(&self.spec)
    }
}

fn ensure_service() -> Result<&'static Sender<Command>, String> {
    if let Some(sender) = COMMANDS.get() {
        return Ok(sender);
    }
    let (sender, receiver) = mpsc::channel();
    COMMANDS
        .set(sender)
        .map_err(|_| "tray service already started".to_string())?;
    thread::Builder::new()
        .name("tray".into())
        .spawn(move || run(receiver))
        .map_err(|error| format!("Failed to start the tray thread: {error}"))?;
    COMMANDS
        .get()
        .ok_or_else(|| "tray service failed to start".to_string())
}

fn run(receiver: Receiver<Command>) {
    let mut handle: Option<Handle<LinuxTray>> = None;
    while let Ok(command) = receiver.recv() {
        match command {
            Command::Set(spec) => match handle.as_ref() {
                Some(existing) => {
                    let _ = existing.update(move |tray: &mut LinuxTray| {
                        tray.visible = spec.visible;
                        tray.spec = spec;
                    });
                }
                None => {
                    let tray = LinuxTray {
                        visible: spec.visible,
                        spec,
                    };
                    if let Ok(spawned) = tray.spawn() {
                        handle = Some(spawned);
                    }
                }
            },
            Command::Hide => {
                if let Some(existing) = handle.as_ref() {
                    let _ = existing.update(|tray: &mut LinuxTray| tray.visible = false);
                }
            }
            Command::SetTitle => {}
        }
    }
}

pub fn set(spec: TraySpec) -> Result<(), String> {
    ensure_service()?
        .send(Command::Set(spec))
        .map_err(|error| format!("Failed to reach the tray service: {error}"))
}

pub fn hide() -> Result<(), String> {
    ensure_service()?
        .send(Command::Hide)
        .map_err(|error| format!("Failed to reach the tray service: {error}"))
}

pub fn set_title(title: String) -> Result<(), String> {
    let _ = title;
    ensure_service()?
        .send(Command::SetTitle)
        .map_err(|error| format!("Failed to reach the tray service: {error}"))
}

pub fn listen(sink: StreamSink<TrayEvent, SseCodec>) -> Result<(), String> {
    *SINK
        .lock()
        .map_err(|error| format!("Tray sink lock poisoned: {error}"))? = Some(sink);
    Ok(())
}
