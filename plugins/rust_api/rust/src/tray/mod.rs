#[cfg(target_os = "linux")]
mod linux;
#[cfg(not(target_os = "linux"))]
mod unsupported;

#[cfg(target_os = "linux")]
pub use linux::{hide, listen, set, set_title};
#[cfg(not(target_os = "linux"))]
pub use unsupported::{hide, listen, set, set_title};
