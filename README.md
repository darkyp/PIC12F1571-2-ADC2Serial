# PIC12F1571/PIC12F1572 4-Channel ADC to 200 kbps Serial Bridge

Cycle-exact MPASM assembly firmware for the **Microchip PIC12F1571/PIC12F1572** that turns an 8-pin microcontroller into a deterministic, low-noise **4-channel 10-bit ADC front-end** streaming over a **200 kbps software UART**. 
The MCU is clocked @ 32MHz using the internal 8MHz oscillator and the integrated 4xPLL.

Why the software serial? - because of the need for 4 ADC channels and the lack of full PPS crossbar on these MCUs (TX can not be routed to RA5). Further more the SW serial allows the code to run on the 12F1571 as well, that does not incorporate a HW EUSART.

## Why This Project Exists

While the **ESP32** packs plenty of Wi-Fi and processing power, its internal 12-bit ADC suffers from severe non-linearity, Wi-Fi radio noise, and RTOS jitter. Offloading analog acquisition to a dedicated **PIC12F1572** provides:
* Clean, monotonic 10-bit conversions isolated from RF/Wi-Fi transients.
* Zero-jitter, hardware-timed sampling intervals.
* Simple, transparent serial streaming into an ESP32 (as a UART-to-TCP bridge) or directly into a PC via a 3.3V USB-to-UART adapter.

### Example Application
This firmware was designed to monitor a **1.1 kW medical air compressor**:
* **2 Fast Channels @ 4 kHz:** AC mains voltage and motor current waveforms (for RMS, power factor, and harmonic analysis).
* **2 Slow Channels @ 15.625 Hz:** Outlet air pressure and compressor head temperature.

---

## Hardware & Pinout

The **PIC12F1572** runs on its internal **32 MHz** clock (`8 MHz HFINTOSC` + `4x PLL`, yielding `8 MIPS` / `125 ns` per instruction cycle) at **3.3V** for direct logic-level compatibility with an ESP32 or 3.3V USB-Serial adapter.

Because all four analog pins are utilized, the hardware EUSART TX cannot be routed to the remaining digital pin (`RA5`). Instead, `RA5` is driven by a cycle-exact, bit-banged software UART inside the main timer ISR.

| PIC12F1572 Pin | Function | Role in Project |
| :--- | :--- | :--- |
| **VDD (Pin 1)** | Power | `3.3V` (decoupled with `100 nF` ceramic cap) |
| **RA5 (Pin 2)** | Digital Output | **200 kbps Serial TX** (`8N1`, idle HIGH) |
| **RA4 / AN3 (Pin 3)** | Analog Input | **Slow Channel 2** (`15.625 Hz`) — e.g., Temperature |
| **RA3 / MCLR (Pin 4)** | Reset (`MCLRE_ON`) | Active-low reset (10 kΩ pull-up; optional ESP32 GPIO control) |
| **RA2 / AN2 (Pin 5)** | Analog Input | **Slow Channel 1** (`15.625 Hz`) — e.g., Pressure |
| **RA1 / AN1 (Pin 6)** | Analog Input | **Fast Channel 2** (`4 kHz`) — e.g., Current |
| **RA0 / AN0 (Pin 7)** | Analog Input | **Fast Channel 1** (`4 kHz`) — e.g., Voltage |
| **VSS (Pin 8)** | Ground | Common `GND` |

---

## Architecture & Timing Highlights

* **Single 200 kHz (`5.00 µs`) ISR State Machine:** Timer0 triggers every **40 instruction cycles** (`5.00 µs` at `8 MIPS`), stepping both the 200 kbps UART bit-banger (`1 bit = 5.00 µs`) and the ADC acquisition/conversion pipeline in lockstep.
* **Zero-Jitter Main Loop:** The main routine sits in an infinite 2-cycle `bra $` loop. Because the interrupted instruction is always 2 cycles, hardware interrupt entry latency is locked at a constant **4 cycles** with zero entry jitter.
* **Zero-Aperture-Jitter ADC Triggering:** Output pin updates (`PORTA`/`LATA`) and ADC channel/start writes (`ADCON0`) are pre-staged in shadow registers and committed at the exact same instruction offsets at the very top of the ISR.
* **Zero-Overhead Shadow Register Context:** Exploits the Enhanced Mid-Range hardware shadow registers (`W`, `BSR`, `FSR0`, `FSR1`) by preloading `TMR0` reload constants and register pointers prior to entering the main loop—eliminating bank-switching and reload setup overhead inside the ISR.

---

## Serial Protocol & Frame Format

* **Baud Rate:** `200,000 bps` (`200 kbps`)
* **Framing:** `8N1` (1 Start bit, 8 Data bits LSB-first, 1 Stop bit)
* **Byte Order:** **Little-Endian** (`ADRESL` first, followed by `ADRESH` masked to `0x00..0x03`)
* **Frame Rate:** `15.625 frames/sec` (`4000 Hz / 256 samples`)
* **Throughput:** `1,030 bytes/frame` × `15.625 fps` = **`16,093.75 bytes/sec`** (~80.5% utilization of the 200 kbps link, leaving natural inter-sample idle gaps for receiver resynchronization)

### Frame Layout (`1,030 Bytes` Total)

| Offset | Length | Field | Description |
| :--- | :--- | :--- | :--- |
| `0` | `2 bytes` | **Sync Header** | Fixed magic bytes: `0xFF`, `0xFE` |
| `2` | `2 bytes` | **Slow Channel 1 (`AN2`)** | 10-bit unsigned little-endian (`uint16_t`, `0..1023`) |
| `4` | `2 bytes` | **Slow Channel 2 (`AN3`)** | 10-bit unsigned little-endian (`uint16_t`, `0..1023`) |
| `6` | `1,024 bytes` | **256 Fast Sample Pairs** | 256 × `[Fast1 (AN0, uint16_t), Fast2 (AN1, uint16_t)]` |

### Why `0xFF 0xFE` Is Collision-Free
Every 10-bit ADC sample is transmitted in little-endian order as `[Low Byte: 0x00..0xFF]` followed by `[High Byte: 0x00..0x03]`. Because a `0xFF` byte can only occur as a low byte—and is **always** immediately followed by a high byte in the range `0x00..0x03`—the sequence `0xFF 0xFE` is mathematically impossible anywhere in the payload or across frame boundaries.

---

## Building & Flashing

1. **Toolchain:** Assemble with **MPASM (`mpasmx`)** via Microchip **MPLAB X IDE** (v5.35 or earlier, which includes `mpasmx`).
2. **Target Device:** `PIC12F1572`
3. **Configuration Fuses:**
   * Internal Oscillator (`_FOSC_INTOSC`), `4x PLL` enabled in software (`OSCCON = b'11110000'`)
   * Watchdog Timer disabled (`_WDTE_OFF`)
   * Master Clear enabled (`_MCLRE_ON`) — *note: disable `_CP_ON` / `_WRT_ALL` during development if debugging in-circuit.*
4. **Programmer:** Flash using PICkit 3, PICkit 4, or Snap.

---

## Quick PC / ESP32 Receiver Notes

* **ESP32 UART Bridge:** Increase the hardware UART RX ring buffer before calling `begin()` (e.g., `Serial2.setRxBufferSize(4096); Serial2.begin(200000, SERIAL_8N1, RX_PIN, -1);`) so Wi-Fi/TCP bursts do not overflow the default 256-byte buffer.
* **PC Direct Capture:** Standard FTDI, CP2102, and CH340 USB-UART adapters support `200000` baud directly.

---

## License

This project is open-source and available under the [MIT License](LICENSE).
