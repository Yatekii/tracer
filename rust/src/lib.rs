mod itm;

use itm::{Interval, TraceEvent, Tracer};
use lazy_static::{self, __Deref};
use std::ffi::{c_void, CStr, CString};
use std::os::raw::c_char;

lazy_static::lazy_static! {
    static ref TRACER: Tracer = itm::Tracer::new();
}

#[no_mangle]
pub extern "C" fn rust_greeting(to: *const c_char) -> *mut c_char {
    let c_str = unsafe { CStr::from_ptr(to) };
    let recipient = match c_str.to_str() {
        Err(_) => "there",
        Ok(string) => string,
    };
    CString::new("Hello ".to_owned() + recipient)
        .unwrap()
        .into_raw()
}

#[no_mangle]
pub extern "C" fn rust_cstr_free(s: *mut c_char) {
    unsafe {
        if s.is_null() {
            return;
        }
        CString::from_raw(s)
    };
}

#[no_mangle]
pub extern "C" fn create() -> u64 {
    let mut tracer = Box::new(itm::Tracer::new());
    tracer.as_mut() as *mut Tracer as u64
}

#[no_mangle]
pub extern "C" fn poll(handle: u64) {
    let mut tracer = box_from_handle(handle);
    tracer.poll().unwrap();
}

#[no_mangle]
pub extern "C" fn events(handle: u64) -> *const Interval {
    let tracer = box_from_handle(handle);
    let events = tracer.events();
    let events = events.lock().unwrap();
    let events = events.deref();
    return events.as_slice().as_ptr();
}

fn box_from_handle(handle: u64) -> Box<Tracer> {
    unsafe { Box::from_raw(handle as *mut Tracer) }
}
