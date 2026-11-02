# Real-Time Audio Spectrum Analyzer on FPGA

A complete audio DSP chain in pure Verilog for the **Digilent Nexys A7-100T**: the on-board PDM microphone is decimated, filtered, windowed, run through a 1024-point FFT, and drawn as a live log-scale spectrum on a VGA monitor.

[![Demo video](https://img.youtube.com/vi/uDEAQ-_7Y-Q/maxresdefault.jpg)](https://youtu.be/uDEAQ-_7Y-Q)

```
 PDM mic ─► CIC decimator ─► gain ─► 127-tap FIR ─► Hann window ─► 1024-pt FFT ─► log magnitude ─► VGA
 2.5 MHz     N=4, R=64      x1..x8   LPF/HPF/BPF                    radix-2 DIT                    640x480@60
            39.0625 kHz
```

Everything runs from a single 100 MHz clock with no MMCM and no clock-domain crossings. The design is deliberately **area-optimized**: one multiplier for the whole FIR and one butterfly for the whole FFT.

## Features

- On-board ADMP421 PDM microphone front end with a 4th-order CIC decimator (2.5 MHz to 39.0625 kHz, 16-bit)
- Selectable 127-tap FIR filter: bypass, 3 kHz low-pass, 3 kHz high-pass, 2-5 kHz band-pass
- 1024-point radix-2 FFT with Hann window, Q1.15 fixed point, 1/2 scaling per stage
- Multiplier-free magnitude (alpha-max-beta-min) and log2 (leading-one plus 4-bit fraction)
- Fast-attack / slow-decay smoothing for a stable display
- 640x480 VGA plot with 6 dB grid lines, freeze, and 2x zoom
- 16-LED level meter, 1 LED per 6 dB
- Testbenches for the FFT, the full mic-to-FFT chain, and VGA timing
- One-command Vivado project creation

## Hardware

| Item | Details |
|---|---|
| Board | Digilent Nexys A7-100T (XC7A100T-1CSG324C) |
| Tool | Vivado 2020.x or newer |
| Language | Verilog-2001 |
| Peripherals used | On-board PDM mic, VGA port, switches SW0-SW5, 16 LEDs, CPU RESET button |

For the Nexys A7-50T, change the part at the top of `create_project.tcl` to `xc7a50tcsg324-1`.

## Quick start

1. Clone the repository somewhere with a short path (for example `C:/fpga/`).
2. Open Vivado and, in the **Tcl Console**, run:
   ```tcl
   cd C:/fpga/audio-dsp-fpga
   source create_project.tcl
   ```
   Or from a terminal: `vivado -source create_project.tcl`.
   This creates `vivado_project/audio_dsp_spectrum.xpr` with all sources, constraints, ROM files, and testbenches. Set `run_flow` to `1` in the script to also run synthesis, implementation, and bitstream generation.
3. Run **Synthesis**, **Implementation**, then **Generate Bitstream**.
4. Connect the board by USB and a monitor to the VGA port, then use **Open Hardware Manager**, **Auto Connect**, **Program Device**.
5. Speak, clap, or whistle near the board.

## Controls

| Control | Function |
|---|---|
| `SW[1:0]` | FIR mode: `00` bypass, `01` low-pass 3 kHz, `10` high-pass 3 kHz, `11` band-pass 2-5 kHz |
| `SW[2]` | Freeze the displayed spectrum |
| `SW[3]` | Zoom: 0-9.8 kHz at 2 px/bin (off: 0-19.5 kHz at 1 px/bin) |
| `SW[5:4]` | Input gain x1 / x2 / x4 / x8 (saturating) |
| `LED[15:0]` | Log-scale level meter, 1 LED per 6 dB |
| `CPU RESET` | Active-low reset |

Display scale: bin width is 39062.5 / 1024 = **38.15 Hz**, about 38 spectra per second (non-overlapping frames). Vertically, 24 px equals one octave of magnitude (6 dB).

## Repository layout

```
.
├── rtl/
│   ├── audio_spectrum_top.v   Top level, gain stage, LED meter
│   ├── pdm_cic.v              PDM clock generator + 4th-order CIC decimator
│   ├── fir_seq.v              Time-multiplexed 127-tap FIR, 4 coefficient sets
│   ├── fft1024.v              Capture RAM, Hann window, FFT engine, magnitude + log2
│   ├── spec_store.v           Spectrum RAM with attack/decay smoothing
│   └── vga_spectrum.v         640x480 timing and spectrum renderer
├── mem/                       ROM init files: twiddles, Hann window, FIR coefficients
├── scripts/gen_mem.py         Regenerates the .mem files (pure Python, no numpy)
├── constraints/
│   └── nexys_a7_100t.xdc      Pin assignments and clock
├── tb/                        tb_fft.v, tb_chain.v, tb_vga.v
└── create_project.tcl         Builds the Vivado project
```

## Design notes

**FIR: one multiplier instead of 127.** At 39.0625 kHz there are 2560 clock cycles per sample, but a 127-tap filter needs only 128 MACs. A single DSP48 is time-multiplexed through a 4-stage pipeline (address, RAM read, multiply, accumulate) with a 40-bit accumulator, Q1.15 coefficients, and round-plus-saturate on output.

**FFT: one butterfly, in-place.** A single radix-2 butterfly (4 real DSP48 multipliers) works on a 1024x32 block RAM. Each butterfly takes 9 clocks, so a full FFT is about 46k clocks (0.46 ms) against 26 ms available to collect a frame. The work RAM is a simple dual-port RAM (one write port, one read port), which Vivado maps cleanly to block RAM; operands are read one after another and results written one after another. For more throughput, pipeline the butterfly to 1 result per clock or move to radix-4. The address logic is already separate from the arithmetic.

**Fixed point.** Q1.15 throughout, with 1/2 scaling per FFT stage and rounding instead of truncation. The CIC uses wrap-around arithmetic with exact bit growth (2 + 4 * log2(64) = 26 bits). A bin-centered tone of amplitude A gives |X| = A/4.

**Cheap log magnitude.** No CORDIC or square root: |X| is approximated as `max + 3/8 * min` (about +/-1 dB), then converted with a leading-one detector plus a 4-bit fraction (about +/-0.09 octave worst case).

**VGA without an MMCM.** The 25 MHz pixel rate is a 1-in-4 clock enable on the 100 MHz clock, so there is no clock-domain crossing. The 25.000 MHz pixel clock (instead of 25.175 MHz) gives a 59.5 Hz refresh, which monitors accept.

## Simulation

The `.mem` files are read relative to the working directory, so run from `mem/`.

**Vivado:** the default simulation top is `tb_fft`. Set `tb_chain` or `tb_vga` as top for the others, then **Run Simulation**, **Run Behavioral Simulation**, and look for `PASSED` in the Tcl console. `tb_chain` needs about 3 M clocks, so allow a few minutes.

**Icarus Verilog:**
```bash
cd mem
iverilog -g2005 -o /tmp/fft.vvp ../rtl/fft1024.v ../tb/tb_fft.v && vvp /tmp/fft.vvp
iverilog -g2005 -P tb_chain.MODE=1 -o /tmp/chain.vvp \
    ../rtl/pdm_cic.v ../rtl/fir_seq.v ../rtl/fft1024.v ../tb/tb_chain.v && vvp /tmp/chain.vvp
```

| Testbench | What it checks |
|---|---|
| `tb_fft` | Two bin-centered tones (bins 100 and 300) give peaks at the right bins and the expected level; prints `FFT TEST PASSED` |
| `tb_chain` | Sigma-delta mic model with 1 kHz + 6 kHz tones through CIC, FIR, FFT. Bypass shows both tones; the 3 kHz low-pass removes the 6 kHz tone |
| `tb_vga` | hsync is 800 px with a 96 px pulse; vsync is 525 lines with a 2-line pulse |

To regenerate the ROM files: `python3 scripts/gen_mem.py`.

## Status

- Behavioral simulation covers the FFT, the full mic-to-FFT chain, and VGA timing.
- **Synthesis, timing closure, and on-board behavior have not been verified yet.** Rough estimate: about 6 DSP48, 6-8 BRAM, 1-2k LUTs. Check the utilization and timing reports after your first build, and please open an issue with anything that looks off.

## Troubleshooting

| Symptom | Try |
|---|---|
| Flat or noisy spectrum, no response to sound | Mic data phase. In `pdm_cic.v` the data is sampled late in the clock-low phase (`CLK_DIV/2 - 1`). Try `m_lrsel = 1'b1` in the top level and sample just before the falling edge (`pdm_en <= (div_cnt == CLK_DIV-1)`) |
| Signal too weak or too strong | Adjust `SW[5:4]`. The display floor is about |X| = 1 |
| Monitor reports "out of range" | Unlikely at 25.000 MHz, but you can swap in a 25.175 MHz MMCM clock for the pixel clock |
| Blank region at the far left | By design: bins 0-2 are hidden because the mic has a DC offset (`DC_BINS` in `fft1024.v`) |

## License

Add a license of your choice (MIT is a common default for hobby projects) as a `LICENSE` file and name it here.
