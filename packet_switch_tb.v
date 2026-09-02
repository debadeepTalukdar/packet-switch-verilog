// =============================================================
// packet_switch_tb.v
// Self-checking testbench: sends packets through the switch,
// exercises normal forwarding, ACL filtering, and back-to-back
// packet timing. Tracks pass/fail automatically and reports a
// final summary. Includes immediate assertions monitoring
// protocol-level invariants every cycle.
//
// Run (Icarus Verilog, -g2012 needed for assertion support):
//   iverilog -g2012 -o sim packet_switch.v packet_switch_tb.v
//   vvp sim
// =============================================================
`timescale 1ns/1ps

module packet_switch_tb;

    localparam PAYLOAD_WIDTH = 13;
    localparam NUM_PORTS     = 4;

    reg clk, rst_n;
    reg in_valid;
    reg [1:0] in_dest_addr, in_src_addr;
    reg [PAYLOAD_WIDTH-1:0] in_payload;
    reg [NUM_PORTS-1:0] blocklist;

    wire [NUM_PORTS-1:0] out_valid;
    wire [PAYLOAD_WIDTH-1:0] out_payload;
    wire [1:0] out_dest_addr;
    wire pkt_dropped, pkt_forwarded;

    // ---- scoreboard ----
    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT (device under test)
    packet_switch #(
        .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
        .NUM_PORTS(NUM_PORTS)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid),
        .in_dest_addr(in_dest_addr),
        .in_src_addr(in_src_addr),
        .in_payload(in_payload),
        .blocklist(blocklist),
        .out_valid(out_valid),
        .out_payload(out_payload),
        .out_dest_addr(out_dest_addr),
        .pkt_dropped(pkt_dropped),
        .pkt_forwarded(pkt_forwarded)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // -----------------------------------------------------------
    // Protocol-level checks — run every clock edge, independent
    // of any individual test case. These catch bugs a directed
    // test might not be specifically looking for.
    // -----------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // pkt_dropped and pkt_forwarded must never both be high
            assert (!(pkt_dropped && pkt_forwarded))
                else begin
                    $display("ASSERTION FAIL: pkt_dropped and pkt_forwarded both high at t=%0t", $time);
                    fail_count = fail_count + 1;
                end

            // when forwarding, out_valid must be one-hot (exactly one bit set)
            if (pkt_forwarded) begin
                assert ($countones(out_valid) == 1)
                    else begin
                        $display("ASSERTION FAIL: out_valid not one-hot during forward, out_valid=%b at t=%0t", out_valid, $time);
                        fail_count = fail_count + 1;
                    end
            end

            // when not forwarding, no output port should be asserted
            if (!pkt_forwarded) begin
                assert (out_valid == {NUM_PORTS{1'b0}})
                    else begin
                        $display("ASSERTION FAIL: out_valid nonzero while not forwarding, out_valid=%b at t=%0t", out_valid, $time);
                        fail_count = fail_count + 1;
                    end
            end
        end
    end

    // Task: send one packet and wait for the FSM to resolve it.
    //
    // Timing note (this was a real bug in the first draft of this
    // testbench — worth understanding, it's an easy off-by-one to
    // make with FSM-driven DUTs): the DUT moves IDLE->CHECK on the
    // same posedge that latches in_valid, then CHECK->FORWARD/DROP
    // on the *next* posedge, then FORWARD/DROP->IDLE on the posedge
    // after that. FORWARD/DROP outputs are only valid for that one
    // cycle. Waiting one negedge too many samples outputs after the
    // FSM has already snapped back to IDLE and cleared them.
    task send_packet(input [1:0] dest, input [1:0] src, input [PAYLOAD_WIDTH-1:0] data);
        begin
            @(negedge clk);
            in_valid     = 1'b1;
            in_dest_addr = dest;
            in_src_addr  = src;
            in_payload   = data;
            @(negedge clk);
            in_valid = 1'b0;              // state is now CHECK
            @(negedge clk);                // state is now FORWARD/DROP - sample here
        end
    endtask

    // Self-checking result reporter — every test case funnels through
    // this so pass/fail is tracked consistently, not just printed.
    task report(input condition, input string test_name);
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("PASS: %s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s", test_name);
            end
        end
    endtask

    initial begin
        // Init
        clk = 0; rst_n = 0;
        in_valid = 0; in_dest_addr = 0; in_src_addr = 0; in_payload = 0;
        blocklist = 4'b0000; // nothing blocked initially

        #12 rst_n = 1; // release reset

        // ---- Test 1: normal forward, src=1 -> dest=2 ----
        send_packet(2'd2, 2'd1, 13'h0AB);
        #1;
        report(pkt_forwarded && out_valid[2] && out_payload == 13'h0AB,
               "Test1_normal_forward_src1_to_dest2");

        // ---- Test 2: block source addr 3, then send from src=3 ----
        blocklist = 4'b1000; // block source port 3
        send_packet(2'd0, 2'd3, 13'h1FF);
        #1;
        report(pkt_dropped && !pkt_forwarded,
               "Test2_blocked_source_dropped");

        // ---- Test 3: unblocked src=0 still forwards normally ----
        send_packet(2'd3, 2'd0, 13'h2CD);
        #1;
        report(pkt_forwarded && out_valid[3],
               "Test3_unblocked_source_forwards");

        // ---- Test 4: back-to-back packets, zero gap between them ----
        // Confirms IDLE correctly re-arms immediately after a packet
        // resolves, instead of dropping/missing the next one.
        blocklist = 4'b0000;
        send_packet(2'd1, 2'd2, 13'h111);
        #1;
        report(pkt_forwarded && out_valid[1] && out_payload == 13'h111,
               "Test4a_back_to_back_first_packet");

        send_packet(2'd0, 2'd2, 13'h222);
        #1;
        report(pkt_forwarded && out_valid[0] && out_payload == 13'h222,
               "Test4b_back_to_back_second_packet_immediately_after");

        #10;
        $display("----------------------------------------");
        $display("SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        $display("----------------------------------------");
        if (fail_count > 0) begin
            $display("RESULT: FAILURE");
            $fatal(1);
        end else begin
            $display("RESULT: ALL TESTS PASSED");
        end
        $finish;
    end

    // Optional waveform dump for viewing in GTKWave
    initial begin
        $dumpfile("packet_switch.vcd");
        $dumpvars(0, packet_switch_tb);
    end

endmodule
