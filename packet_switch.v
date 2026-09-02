// =============================================================
// packet_switch.v
// A simple 4-port packet switch with address-based routing
// and ACL-style filtering (mimics core switch/router behavior)
// =============================================================
//
// PACKET INTERFACE (separate fields, sampled together on in_valid):
//   in_dest_addr [1:0]      -> which of the 4 output ports (0-3)
//   in_src_addr  [1:0]      -> source port, checked against blocklist
//   in_payload   [PAYLOAD_WIDTH-1:0] -> data carried by the packet
//   in_valid                -> packet fields are valid this cycle
//
// FILTER: a blocklist register (one bit per source address). If a
// packet's source addr matches a blocked address, it is dropped
// instead of forwarded.
//
// FSM STATES:
//   IDLE    -> waiting for valid packet, latches fields on accept
//   CHECK   -> check latched source addr against filter rule
//   FORWARD -> drive packet onto the selected output port (one-hot)
//   DROP    -> discard packet (filtered), assert drop flag
// =============================================================

module packet_switch #(
    parameter PAYLOAD_WIDTH = 13,
    parameter NUM_PORTS     = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Incoming packet interface
    input  wire                     in_valid,
    input  wire [1:0]               in_dest_addr,
    input  wire [1:0]               in_src_addr,
    input  wire [PAYLOAD_WIDTH-1:0] in_payload,

    // Filter configuration: bit i = 1 means source addr i is blocked
    input  wire [NUM_PORTS-1:0]     blocklist,

    // Output ports (one-hot valid + shared payload/addr bus per port)
    output reg  [NUM_PORTS-1:0]     out_valid,
    output reg  [PAYLOAD_WIDTH-1:0] out_payload,
    output reg  [1:0]               out_dest_addr,

    // Status flags
    output reg                      pkt_dropped,
    output reg                      pkt_forwarded
);

    // FSM state encoding
    localparam IDLE    = 2'b00;
    localparam CHECK   = 2'b01;
    localparam FORWARD = 2'b10;
    localparam DROP    = 2'b11;

    reg [1:0] state, next_state;

    // Latched packet fields (held stable across CHECK -> FORWARD/DROP)
    reg [1:0]               dest_addr_reg;
    reg [1:0]               src_addr_reg;
    reg [PAYLOAD_WIDTH-1:0] payload_reg;

    // -----------------------------------------------------------
    // State register
    // -----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // -----------------------------------------------------------
    // Next-state logic
    // -----------------------------------------------------------
    always @(*) begin
        case (state)
            IDLE:    next_state = in_valid ? CHECK : IDLE;
            CHECK:   next_state = blocklist[src_addr_reg] ? DROP : FORWARD;
            FORWARD: next_state = IDLE;
            DROP:    next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // -----------------------------------------------------------
    // Latch packet fields when accepted in IDLE
    // -----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dest_addr_reg <= 2'b00;
            src_addr_reg  <= 2'b00;
            payload_reg   <= {PAYLOAD_WIDTH{1'b0}};
        end else if (state == IDLE && in_valid) begin
            dest_addr_reg <= in_dest_addr;
            src_addr_reg  <= in_src_addr;
            payload_reg   <= in_payload;
        end
    end

    // -----------------------------------------------------------
    // Output logic (combinational, driven off current state)
    // -----------------------------------------------------------
    integer i;
    always @(*) begin
        out_valid     = {NUM_PORTS{1'b0}};
        out_payload   = {PAYLOAD_WIDTH{1'b0}};
        out_dest_addr = 2'b00;
        pkt_dropped   = 1'b0;
        pkt_forwarded = 1'b0;

        case (state)
            FORWARD: begin
                out_valid[dest_addr_reg] = 1'b1;   // one-hot select
                out_payload              = payload_reg;
                out_dest_addr            = dest_addr_reg;
                pkt_forwarded            = 1'b1;
            end
            DROP: begin
                pkt_dropped = 1'b1;
            end
            default: begin
                // IDLE / CHECK: no outputs driven
            end
        endcase
    end

endmodule
