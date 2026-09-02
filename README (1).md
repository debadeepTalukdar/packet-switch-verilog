# 4-Port Packet Switch with ACL Filtering (Verilog)

A small FSM-based RTL model of the core job a network switch performs:
inspect an incoming packet, route it to the correct output port, and drop
it if the source violates a filter rule (basic ACL-style filtering).

## Files
- `packet_switch.v` — switch/filter module (4-state FSM)
- `packet_switch_tb.v` — self-checking testbench (5 test cases + 2 always-on
  protocol assertions)

## Design overview

**Packet interface:** each packet is a 2-bit destination address, a 2-bit
source address, and a payload, presented together on `in_valid`.

**Filter:** a `blocklist` register, one bit per source address. If a
packet's source is blocked, it is dropped instead of forwarded.

**FSM (4 states):**
1. `IDLE` — waits for `in_valid`, latches the packet fields on accept
2. `CHECK` — checks the latched source address against `blocklist`
3. `FORWARD` — drives the packet onto the correct one-hot output port
4. `DROP` — source was blocked; packet is discarded and `pkt_dropped` is
   asserted instead

Lookup/filter and forwarding are separate states rather than combined into
one cycle, mirroring how real switch pipelines stage packet processing
(lookup, filter, forward) across separate cycles to run at higher clock
speed.

## Verification

The testbench is self-checking rather than relying on waveform inspection:
- A `pass_count` / `fail_count` scoreboard, with a final summary and a
  nonzero exit (`$fatal`) on any failure
- 5 directed test cases: normal forward, filtered source (dropped),
  unblocked source (forwards normally), and two back-to-back packets with
  no gap between them (checks the FSM re-arms `IDLE` correctly)
- 2 assertions running every clock cycle, independent of any specific
  test: `pkt_dropped` and `pkt_forwarded` are never both high, and
  `out_valid` is exactly one-hot whenever a packet is forwarded

The assertions were validated by deliberately breaking the one-hot output
logic during development (forcing `out_valid` high on all 4 ports) and
confirming both assertions caught it immediately, while the directed
tests -- which only check the destination port's own bit -- missed it.
The design was then reverted to the correct version before this commit.

An earlier version of the testbench had a timing bug: it sampled DUT
outputs one clock cycle too late, after the FSM had already returned to
`IDLE` and cleared its outputs, causing every test to fail against a
correct design. Fixed by trimming one wait cycle in the `send_packet`
task so sampling happens while state is still `FORWARD`/`DROP`.

## Running it

```
iverilog -g2012 -o sim packet_switch.v packet_switch_tb.v
vvp sim
gtkwave packet_switch.vcd   # optional, view waveforms
```

Expected: `SUMMARY: 5 passed, 0 failed` / `RESULT: ALL TESTS PASSED`.

Also runnable on [EDA Playground](https://www.edaplayground.com/) with
Icarus Verilog selected as the simulator -- no local install needed.

## Possible extensions
Per-port queuing/buffering for when an output port is busy, a CAM-based
address lookup in place of the fixed blocklist register, and
back-pressure handling.
