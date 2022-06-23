#![no_std]
#![no_main]

use core::cell::RefCell;

use esp32_hal::{
    clock::ClockControl,
    gpio::{Gpio0, IO},
    gpio_types::{Event, Input, Pin, PullDown},
    interrupt,
    pac::{self, Peripherals},
    prelude::*,
    Cpu,
    Delay,
    RtcCntl,
    Timer,
};
use panic_halt as _;
use xtensa_lx::mutex::{Mutex, SpinLockMutex};
use xtensa_lx_rt::entry;

static mut BUTTON: SpinLockMutex<RefCell<Option<Gpio0<Input<PullDown>>>>> =
    SpinLockMutex::new(RefCell::new(None));

#[entry]
fn main() -> ! {
    let peripherals = Peripherals::take().unwrap();
    let system = peripherals.DPORT.split();
    let clocks = ClockControl::boot_defaults(system.clock_control).freeze();

    // Disable the TIMG watchdog timer.
    let mut timer0 = Timer::new(peripherals.TIMG0);
    let mut rtc_cntl = RtcCntl::new(peripherals.RTC_CNTL);

    esp_println::println!("Hello esp_println!");

    // Disable MWDT and RWDT (Watchdog) flash boot protection
    timer0.disable();
    rtc_cntl.set_wdt_global_enable(false);

    // Set GPIO15 as an output, and set its state high initially.
    let io = IO::new(peripherals.GPIO, peripherals.IO_MUX);
    let mut led = io.pins.gpio15.into_push_pull_output();
    let mut button = io.pins.gpio0.into_pull_down_input();
    button.listen(Event::FallingEdge);

    unsafe {
        (&BUTTON).lock(|data| (*data).replace(Some(button)));
    }

    interrupt::vectored::enable_with_priority(Cpu::ProCpu, pac::Interrupt::GPIO, interrupt::vectored::Priority::Priority3).unwrap();

    led.set_high().unwrap();

    // Initialize the Delay peripheral, and use it to toggle the LED state in a
    // loop.
    let mut delay = Delay::new(&clocks);

    unsafe {
        xtensa_lx::interrupt::enable_mask(1 << 1);
    }

    loop {
        esp_println::println!("Interrupt - INTLEVEL: {}", xtensa_lx::interrupt::get_level());
        led.toggle().unwrap();
        delay.delay_ms(500u32);
    }
}

#[interrupt]
fn GPIO() {
    unsafe {
        esp_println::println!("GPIO Interrupt");
    
        (&BUTTON).lock(|data| {
            let mut button = data.borrow_mut();
            let button = button.as_mut().unwrap();
            button.clear_interrupt();
        });
    }
}
