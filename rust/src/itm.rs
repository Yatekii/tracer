use anyhow::Result;
use probe_rs::{
    architecture::arm::{
        component::Dwt,
        memory::PeripheralType,
        swo::{Decoder, ExceptionAction, ExceptionType, TimestampDataRelation, TracePacket},
        SwoConfig,
    },
    MemoryInterface, Probe, Session,
};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, path::PathBuf, sync::Arc};
use std::{
    collections::VecDeque,
    fs::{File, OpenOptions},
    sync::Mutex,
};
use std::{
    ffi::CString,
    io::{BufReader, Read},
};
use svd::{Device, Interrupt};
use svd_parser as svd;

#[derive(Deserialize)]
#[allow(unused)]
struct Config {
    output_file: PathBuf,
    duration: Option<u64>,
    baud: Option<u32>,
    isr_mapping: HashMap<usize, String>,
    svd: Option<String>,
}

#[derive(Serialize)]
#[allow(unused)]
#[repr(C)]
pub enum InstantEventType {
    #[serde(rename = "g")]
    Global,
    #[serde(rename = "p")]
    Process,
    #[serde(rename = "t")]
    Thread,
}

#[derive(Serialize)]
#[serde(tag = "ph")]
#[allow(unused)]
#[repr(C)]
pub enum TraceEvent {
    #[serde(rename = "B")]
    DurationEventBegin {
        pid: usize,
        tid: String,
        ts: f64,
        name: String,
        args: Option<HashMap<String, String>>,
    },
    #[serde(rename = "E")]
    DurationEventEnd {
        pid: usize,
        tid: String,
        ts: f64,
        name: String,
    },
    #[serde(rename = "X")]
    CompleteEvent {
        pid: usize,
        tid: usize,
        ts: f64,
        dur: f64,
        name: String,
    },
    #[serde(rename = "I")]
    InstantEvent {
        pid: usize,
        tid: String,
        ts: f64,
        name: String,
        s: InstantEventType,
    },
}

#[repr(C)]
pub struct Interval {
    start: u64,
    end: u64,
    isr: CString,
}

#[derive(Serialize)]
#[allow(non_snake_case)]
struct Trace {
    traceEvents: Vec<TraceEvent>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimeStamp {
    pub tc: TimestampDataRelation,
    pub ts: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TracePackets {
    pub packets: Vec<TracePacket>,
    pub timestamp: TimeStamp,
}

#[repr(C)]
pub struct Tracer {
    session: Arc<Mutex<Session>>,
    packets: Arc<Mutex<VecDeque<TracePackets>>>,
    bundled_packets: Vec<TracePacket>,
    decoder: Decoder,
    events: Arc<Mutex<Vec<Interval>>>,
    timestamp: f64,
    last_timestamp: TimeStamp,
    device: Option<Device>,
}

impl Tracer {
    pub fn new() -> Self {
        pretty_env_logger::init();

        let reader = BufReader::new(
            OpenOptions::new()
                .read(true)
                .open("probe-rs/examples/trace_config.json")
                .unwrap(),
        );
        let config: Config = serde_json::from_reader(reader).unwrap();

        let xml = &mut String::new();
        let svd = config
            .svd
            .map(|f| {
                File::open(f)?.read_to_string(xml)?;
                svd::parse(xml)
            })
            .transpose()
            .unwrap();

        // let duration = std::time::Duration::from_millis(config.duration.unwrap_or(u64::MAX));
        let t = std::time::Instant::now();

        // Get a list of all available debug probes.
        let probes = Probe::list_all();

        // Use the first probe found.
        let probe = probes[0].open().unwrap();

        // Attach to a chip.
        let mut session = probe.attach("stm32f407").unwrap();

        // Create a new SwoConfig with a system clock frequency of 16MHz
        let baud = config.baud.unwrap_or(1_000_000);
        println!("Using {} baud.", baud);
        let cfg = SwoConfig::new(16_000_000)
            .set_baud(baud)
            .set_continuous_formatting(false);

        session.setup_swv(&cfg).unwrap();

        {
            let components = session.get_arm_components().unwrap();
            let mut core = session.core(0).unwrap();
            let dwt = components
                .iter()
                .find_map(|component| component.find_component(PeripheralType::Dwt))
                .unwrap();
            let mut dwt = Dwt::new(&mut core, dwt);
            dwt.enable_exception_trace().unwrap();
        }

        let mut timestamp: f64 = 0.0;

        Self {
            session: Arc::new(Mutex::new(session)),
            bundled_packets: Vec::new(),
            packets: Arc::new(Mutex::new(VecDeque::<TracePackets>::new())),
            decoder: Decoder::new(),
            events: Arc::new(Mutex::new(Vec::new())),
            timestamp: 0.0,
            device: svd,
            last_timestamp: TimeStamp {
                ts: 0,
                tc: TimestampDataRelation::Sync,
            },
        }
    }

    /// Stores a new packed in the to be emitted packets vector.
    /// The stored packets are only actually emitted when `timestamp()` is called
    /// or `force_pull()` is used.
    ///
    /// This method tries to join packets of the same type at the same timestamp.
    fn emit(&mut self, packet: TracePacket) {
        // If we are working on an ITM data packet, we try to fuse it with the last one
        // if they match.
        if let TracePacket::Instrumentation {
            port: new_port,
            payload: add_payload,
        } = packet
        {
            if let Some(last) = self.bundled_packets.last_mut() {
                if let TracePacket::Instrumentation { port, payload } = last {
                    if *port == new_port {
                        // We have an existing packet in the queue which also matches the old packet
                        // so we extend the existing packet.
                        payload.extend(add_payload);
                        return;
                    }
                }
            }

            // If we can run until here, we could not extend our existing packet,
            // so we add a new one.
            self.bundled_packets.push(TracePacket::Instrumentation {
                port: new_port,
                payload: add_payload,
            });
        } else {
            self.bundled_packets.push(packet);
        }
    }

    /// Pulls the next packet from the decoder.
    /// If there is an unfinished packet and no finished ones, the unfinished packet is returned.
    /// This is intended to be called at the end of a tracing procedure to finish up.
    // pub fn force_pull(&mut self) -> Option<TracePackets> {
    //     self.pull().or_else(|| {
    //         if !self.bundled_packets.is_empty() {
    //             self.timestamp(self.last_timestamp.clone());
    //         }
    //         self.packets.pop_front()
    //     })
    // }

    fn timestamp(&mut self, timestamp: TimeStamp) {
        let mut packets = self.packets.lock().unwrap();
        packets.push_back(TracePackets {
            packets: self.bundled_packets.drain(..).collect(),
            timestamp: timestamp.clone(),
        });
        self.last_timestamp = timestamp;
    }

    pub fn poll(&mut self) -> Result<()> {
        let bytes = {
            let mut session = self.session.lock().unwrap();
            session.read_swo()?
        };

        self.decoder.feed(bytes);

        while let Ok(Some(packet)) = self.decoder.pull() {
            match packet {
                TracePacket::LocalTimestamp1 { ts, data_relation } => self.timestamp(TimeStamp {
                    ts: ts as usize,
                    tc: data_relation,
                }),
                p => self.emit(p),
            }
        }

        let mut packets = self.packets.lock().unwrap();
        let mut events = self.events.lock().unwrap();

        while let Some(TracePackets {
            packets,
            timestamp: TimeStamp { tc, ts },
        }) = packets.pop_front()
        {
            log::debug!("Timestamp packet: tc={:?} ts={}", tc, ts);
            let mut time_delta: f64 = ts as f64;
            // Divide by core clock frequency to go from ticks to seconds.
            time_delta /= 16_000_000.0;
            self.timestamp += time_delta;

            for packet in packets {
                match packet {
                    TracePacket::ExceptionTrace { exception, action } => {
                        println!("{:?} {:?}", action, exception);
                        match exception {
                            ExceptionType::ExternalInterrupt(0) => {
                                events.push(TraceEvent::DurationEventBegin {
                                    pid: 1,
                                    tid: "Priority 999".to_string(),
                                    ts: self.timestamp * 1000.0,
                                    name: "Main".to_string(),
                                    args: None,
                                });
                            }
                            ExceptionType::ExternalInterrupt(n) => {
                                let n = n as u32 - 16;
                                let isr = get_isr(&self.device, n);
                                let mut args = HashMap::new();
                                let name = isr
                                    .map(|i| {
                                        i.description.as_ref().map(|d| {
                                            args.insert("description".to_string(), d.clone())
                                        });
                                        i.name.clone()
                                    })
                                    .unwrap_or_else(|| "Unknown ISR".to_string());
                                let priority = {
                                    let mut session = self.session.lock().unwrap();
                                    let mut core = session.core(0)?;

                                    core.read_word_8(0xE000E400 + ((n / 4) * 4) + 3 - (n % 4))?
                                };
                                match action {
                                    ExceptionAction::Entered => {
                                        // Interrupt main.
                                        events.push(TraceEvent::DurationEventEnd {
                                            pid: 1,
                                            tid: "Priority 999".to_string(),
                                            ts: self.timestamp * 1000.0,
                                            name: "Main".to_string(),
                                        });
                                        events.push(TraceEvent::DurationEventBegin {
                                            pid: 1,
                                            tid: format!("Priority {}", priority),
                                            ts: self.timestamp * 1000.0,
                                            name,
                                            args: Some(args),
                                        });
                                    }
                                    ExceptionAction::Exited => {
                                        events.push(TraceEvent::DurationEventEnd {
                                            pid: 1,
                                            tid: format!("Priority {}", priority),
                                            ts: self.timestamp * 1000.0,
                                            name,
                                        });
                                    }
                                    ExceptionAction::Returned => continue,
                                }
                            }
                            _ => (),
                        }
                    }
                    TracePacket::Instrumentation { port, payload } => {
                        // First decode the string data from the stimuli.
                        let payload = String::from_utf8_lossy(&payload);
                        println!("{:?}", payload);
                        events.push(TraceEvent::InstantEvent {
                            pid: 1,
                            tid: "4".to_string(),
                            ts: self.timestamp * 1000.0,
                            name: payload.to_string(),
                            s: InstantEventType::Global,
                        })
                    }
                    _ => {
                        log::warn!("Trace packet: {:?}", packet);
                    }
                }
                log::debug!("{}", self.timestamp);
            }
        }

        Ok(())
    }

    pub fn events(&self) -> Arc<Mutex<Vec<Interval>>> {
        self.events.clone()
    }
}

fn get_isr(device: &Option<Device>, number: u32) -> Option<&Interrupt> {
    device.as_ref().and_then(|device| {
        for peripheral in &device.peripherals {
            for interrupt in &peripheral.interrupt {
                if interrupt.value == number {
                    return Some(interrupt);
                }
            }
        }
        return None;
    })
}
