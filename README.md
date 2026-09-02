# 4-Port Packet Switch with ACL Filtering (Verilog)

A small FSM-based RTL model of the core job a network switch does: look at
an incoming packet, decide which of 4 output ports it goes to, and drop it
if its source violates a basic filter rule (ACL-style).

## Files
- `packet_switch.v` — the switch/filter module (4-state FSM)
- `packet_switch_tb.v` — self-checking testbench: 5 test cases + 2 always-on
  protocol assertions

## How it works

**Packet interface:** each packet is a 2-bit destination address, a 2-bit
source address, and a payload, presented together with `in_valid`.

**Filter:** a `blocklist` register, one bit per source address. If a
packet's source is blocked, it's dropped instead of forwarded.

**FSM (4 states):**
1. `IDLE` — waits for `in_valid`, latches the packet fields on accept
2. `CHECK` — looks up the latched source address against `blocklist`
3. `FORWARD` — drives the packet onto the correct one-hot output port
4. `DROP` — source was blocked; packet is discarded and `pkt_dropped` is
   asserted instead

Design vs. verification are split across states on purpose — real switch
pipelines stage lookup, filter, and forward as separate cycles so the
datapath can run at higher clock speed. This mirrors that structure in
miniature.

## Verification approach

The testbench is self-checking, not just waveform-and-eyeball:
- A `pass_count` / `fail_count` scoreboard, with a final summary line and
  a nonzero exit (`$fatal`) if anything fails — so pass/fail is a fact,
  not something you read off a screen
- 5 directed test cases: normal forward, filtered source (dropped),
  unblocked source (forwards normally), and two back-to-back packets with
  zero gap between them (checks the FSM re-arms `IDLE` correctly instead
  of dropping the next packet)
- 2 concurrent-style checks running every clock cycle, independent of any
  specific test: `pkt_dropped` and `pkt_forwarded` can never both be high,
  and `out_valid` must be exactly one-hot whenever a packet is forwarded

**I deliberately broke the design once to confirm the assertions actually
catch bugs, not just pass silently** — forced `out_valid` to go high on
all 4 ports instead of one-hot. The directed tests still passed (they only
check the destination port's own bit), but both assertions fired
immediately and flagged the exact cycle. Reverted after confirming it.
This is also why the assertions are there at all: some bug classes won't
show up in directed testing alone.

**Bug found and fixed during development:** the first version of the
testbench sampled DUT outputs one clock cycle too late — by the time it
checked `pkt_forwarded`/`out_valid`, the FSM had already cycled back to
`IDLE` and cleared them, so every test failed even though the design was
correct. Fixed by trimming one wait cycle in the `send_packet` task so
sampling happens while state is still `FORWARD`/`DROP`. Worth
understanding if asked — it's a common off-by-one when testing
FSM-driven RTL, and a good example of a verification bug vs. a design bug.

## How to run it yourself (do this before the interview)

```
sudo apt install iverilog gtkwave      # one-time install
iverilog -g2012 -o sim packet_switch.v packet_switch_tb.v
vvp sim
gtkwave packet_switch.vcd              # optional, view waveforms
```

Expected output: `SUMMARY: 5 passed, 0 failed` / `RESULT: ALL TESTS PASSED`.

Or paste both files into [EDA Playground](https://www.edaplayground.com/)
with Icarus Verilog as the simulator (enable "Open EPWave after run" for
waveforms) — no install needed.

## Synthesis

Run in Vivado (Flow Navigator → Run Synthesis) after adding both files as
non-simulation/simulation sources respectively. Fill in after running:
- **Fmax / timing:** _[add from Vivado timing summary]_
- **Resource utilization:** _[add LUT/FF counts from Vivado utilization report]_

## What to say about it in an interview

- "I modeled the core datapath of a network switch — address-based
  forwarding plus ACL-style filtering — as a 4-state FSM in Verilog, with
  design split from verification: lookup/filter (`CHECK`) is a separate
  stage from the forwarding action (`FORWARD`), the way real switch
  pipelines stage packet processing across cycles."
- "The testbench is self-checking with a pass/fail scoreboard, not just
  waveform inspection — 5 directed tests plus 2 assertions that run every
  cycle checking protocol invariants like one-hot output selection."
- "I actually caught a timing bug during development — the testbench was
  sampling outputs one cycle after the FSM had already returned to IDLE.
  I traced it by hand through the state transitions and fixed it."
- "I validated the assertions were doing real work, not just decoration,
  by deliberately breaking the one-hot output logic and confirming the
  assertions caught it immediately while the directed tests missed it."

**If asked what you'd add next:** per-port queuing/buffering for when an
output port is busy, a CAM-based address lookup instead of a fixed
blocklist register, and back-pressure handling.

## Resume bullet (suggested)

**4-Port Packet Switch with ACL Filtering — Verilog**
- Designed an FSM-based RTL module modeling address-based packet
  forwarding and ACL-style filtering across 4 output ports
- Built a self-checking testbench (5 test cases, pass/fail scoreboard) plus
  2 concurrent assertions checking protocol invariants every cycle;
  validated assertion coverage by injecting a deliberate bug and confirming
  it was caught
- Found and fixed a testbench timing bug through manual FSM cycle tracing
- Synthesized in Vivado: _[Fmax] MHz, [LUT/FF count] utilization_
