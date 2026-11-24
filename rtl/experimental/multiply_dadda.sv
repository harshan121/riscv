`timescale 1ns/1ps
`default_nettype none

package dadda_compensation;

    function automatic logic [127:0] make_compensation();
        logic [127:0] comp;
        int sign_col;

        comp = '0;

        for (int i = 0; i < 33; i++) begin
            sign_col = 65 + 2 * i;

            if (sign_col < 128) begin
                comp = comp - (128'd1 << sign_col);
            end
        end

        return comp;
    endfunction

    localparam logic [127:0] SIGN_COMP = make_compensation();

endpackage


package dadda_plan_pkg;

    localparam int WIDTH  = 128;
    localparam int ROWS   = 34;
    localparam int STAGES = 8;
    localparam int MAX42  = ROWS / 4;

    typedef logic [$clog2(ROWS + 1) - 1:0] count_t;

    typedef struct packed {
        logic valid;
        count_t [STAGES:0][WIDTH:0] height;
        count_t [STAGES-1:0][WIDTH-1:0] req_height;
        count_t [STAGES-1:0][WIDTH-1:0] n_42;
        count_t [STAGES-1:0][WIDTH-1:0] n_fa;
        count_t [STAGES-1:0][WIDTH-1:0] n_ha;
        count_t [STAGES-1:0][WIDTH-1:0] incoming;
        count_t [STAGES-1:0][WIDTH-1:0] links_in;
    } plan_t;

    function automatic int dadda_target(input int stage);
        case (stage)
            0: return 28;
            1: return 19;
            2: return 13;
            3: return 9;
            4: return 6;
            5: return 4;
            6: return 3;
            7: return 2;
            default: return 2;
        endcase
    endfunction

    function automatic int first_group(input int col);
        return (col > 65) ? (col - 64) / 2 : 0;
    endfunction

    function automatic int last_group(input int col);
        return (col / 2 > 32) ? 32 : col / 2;
    endfunction

    function automatic int initial_height(input int col);
        return last_group(col)
             - first_group(col)
             + 1
             + int'((col % 2 == 0) && (col <= 64))
             + int'(dadda_compensation::SIGN_COMP[col]);
    endfunction

    function automatic plan_t calc_fa_ha_index();
        plan_t p;

        int target;
        int h;
        int ordinary_in;
        int lateral_in;
        int leftover_links;
        int remainder;
        int needed_ha;
        int out_height;
        int cost;
        int best_cost;
        int best42;
        int bestfa;
        int bestha;
        int bestheight;

        p = '0;
        p.valid = 1'b1;

        for (int col = 0; col < WIDTH; col++) begin
            p.height[0][col] = count_t'(initial_height(col));
        end

        for (int st = 0; st < STAGES; st++) begin
            target = dadda_target(st);
            ordinary_in = 0;
            lateral_in = 0;

            for (int col = 0; col < WIDTH; col++) begin
                h = int'(p.height[st][col]);

                p.incoming[st][col] = count_t'(ordinary_in);
                p.links_in[st][col] = count_t'(lateral_in);
                p.req_height[st][col] = count_t'(target);

                best_cost = 100000;
                best42 = 0;
                bestfa = 0;
                bestha = 0;
                bestheight = 0;

                for (int q = 0; q <= h / 4; q++) begin
                    for (int f = 0; f <= (h - 4 * q) / 3; f++) begin
                        leftover_links = (lateral_in > q) ? lateral_in - q : 0;
                        remainder = h - 4 * q - 3 * f;

                        out_height = ordinary_in
                                   + h
                                   - 3 * q
                                   - 2 * f
                                   + leftover_links;

                        needed_ha = (out_height > target)
                                  ? out_height - target
                                  : 0;

                        if (2 * needed_ha <= remainder) begin
                            cost = 2 * q + f + needed_ha;

                            if ((cost < best_cost)
                                || ((cost == best_cost) && (q > best42))) begin
                                best_cost = cost;
                                best42 = q;
                                bestfa = f;
                                bestha = needed_ha;
                                bestheight = out_height - needed_ha;
                            end
                        end
                    end
                end

                if (best_cost == 100000) begin
                    p.valid = 1'b0;
                end

                p.n_42[st][col] = count_t'(best42);
                p.n_fa[st][col] = count_t'(bestfa);
                p.n_ha[st][col] = count_t'(bestha);
                p.height[st + 1][col] = count_t'(bestheight);

                ordinary_in = best42 + bestfa + bestha;
                lateral_in = best42;
            end

            p.height[st + 1][WIDTH] = count_t'(ordinary_in + lateral_in);
        end

        return p;
    endfunction

endpackage


module fulladder (
    input  logic a,
    input  logic b,
    input  logic c,
    output logic o,
    output logic co
);

    assign o = a ^ b ^ c;
    assign co = (a & b) | (b & c) | (c & a);

endmodule


module halfadder (
    input  logic a,
    input  logic b,
    output logic o,
    output logic co
);

    assign o = a ^ b;
    assign co = a & b;

endmodule


module four_two_comp (
    input  logic a,
    input  logic b,
    input  logic c,
    input  logic d,
    input  logic cin,
    output logic s,
    output logic cout_1,
    output logic cout_2
);

    logic s_i;

    fulladder fa1 (
        .a  (a),
        .b  (b),
        .c  (c),
        .o  (s_i),
        .co (cout_1)
    );

    fulladder fa2 (
        .a  (d),
        .b  (s_i),
        .c  (cin),
        .o  (s),
        .co (cout_2)
    );

endmodule


module kogge_stone_128 (
    input  logic [127:0] a,
    input  logic [127:0] b,
    input  logic         sub,
    output logic [127:0] sum,
    output logic         cout
);

    genvar i;
    genvar level;

    logic [127:0] g [7:0];
    logic [127:0] p [7:0];
    logic [127:0] b_eff;

    assign b_eff = b ^ {128{sub}};

    assign p[0][127:0] = a ^ b_eff;
    assign g[0][127:1] = a[127:1] & b_eff[127:1];

    assign g[0][0] = (a[0] & b_eff[0])
                    | (sub & (a[0] ^ b_eff[0]));

    generate
        for (level = 1; level <= 7; level++) begin : kogge_stone_gen_prop
            for (i = 0; i < 128; i++) begin : kogge_stone_prefix
                if (i < (1 << (level - 1))) begin : pass_through
                    assign g[level][i] = g[level - 1][i];
                    assign p[level][i] = p[level - 1][i];
                end
                else begin : prefix_combine
                    assign g[level][i] =
                        g[level - 1][i]
                        | (p[level - 1][i]
                           & g[level - 1][i - (1 << (level - 1))]);

                    assign p[level][i] =
                        p[level - 1][i]
                        & p[level - 1][i - (1 << (level - 1))];
                end
            end
        end
    endgenerate

    assign cout = g[7][127];
    assign sum = p[0] ^ {g[7][126:0], sub};

endmodule

module multiply (
    input  logic [63:0]  a,
    input  logic [63:0]  b,
    input  logic [1:0]   op,
    input  logic         clk,
    input  logic         reset,
    output logic [127:0] result
);

    import dadda_plan_pkg::*;

    localparam plan_t PLAN = calc_fa_ha_index();

    localparam logic [1:0] MUL    = 2'b00;
    localparam logic [1:0] MULH   = 2'b01;
    localparam logic [1:0] MULHSU = 2'b10;
    localparam logic [1:0] MULU   = 2'b11;

    // -------------------------------------------------------------------------
    // Signed / unsigned operand preparation
    // -------------------------------------------------------------------------
    logic [64:0] a_ext;
    logic [64:0] b_ext;

    always_comb begin
        a_ext = {1'b0, a};
        b_ext = {1'b0, b};

        case (op)
            MUL: begin
                a_ext = {1'b0, a};
                b_ext = {1'b0, b};
            end

            MULH: begin
                a_ext = {a[63], a};
                b_ext = {b[63], b};
            end

            MULHSU: begin
                a_ext = {a[63], a};
                b_ext = {1'b0, b};
            end

            MULU: begin
                a_ext = {1'b0, a};
                b_ext = {1'b0, b};
            end

            default: begin
                a_ext = {1'b0, a};
                b_ext = {1'b0, b};
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Radix-4 Booth recoding
    // -------------------------------------------------------------------------
    logic [65:0] partial_product [0:32];
    logic [32:0] correction_bit;

    wire [66:0] multiplicant = {a_ext[64], a_ext, 1'b0};
    wire [65:0] b_wide      = {b_ext[64], b_ext};

    generate
        for (genvar i = 0; i < 33; i++) begin : booth_loop
            wire [2:0] booth_bits = multiplicant[2*i +: 3];

            always_comb begin
                partial_product[i] = '0;
                correction_bit[i]  = 1'b0;

                case (booth_bits)
                    3'b000,
                    3'b111: begin
                        partial_product[i] = '0;
                    end

                    3'b001,
                    3'b010: begin
                        partial_product[i] = b_wide;
                    end

                    3'b011: begin
                        partial_product[i] = b_wide << 1;
                    end

                    3'b100: begin
                        partial_product[i] = ~(b_wide << 1);
                        correction_bit[i]  = 1'b1;
                    end

                    3'b101,
                    3'b110: begin
                        partial_product[i] = ~b_wide;
                        correction_bit[i]  = 1'b1;
                    end

                    default: begin
                        partial_product[i] = '0;
                        correction_bit[i]  = 1'b0;
                    end
                endcase

                // Compact sign-extension transformation.
                partial_product[i][65] = ~partial_product[i][65];
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Dadda heaps
    //
    // Stage 1: Booth + D0 + D1  => heap_1[0] .. heap_1[2]
    // Stage 2: D2 + D3 + D4     => heap_2[0] .. heap_2[3]
    // Stage 3: D5 + D6 + D7     => heap_3[0] .. heap_3[3]
    // -------------------------------------------------------------------------
    wire heap_1 [0:2][0:WIDTH-1][0:ROWS-1];
    wire heap_2 [0:3][0:WIDTH-1][0:ROWS-1];
    wire heap_3 [0:3][0:WIDTH-1][0:ROWS-1];

    logic pipe1_heap [0:WIDTH-1][0:ROWS-1];
    logic pipe2_heap [0:WIDTH-1][0:ROWS-1];

    // Lateral 4:2 compressor links. Each Dadda stage owns its own chain.
    wire link [0:STAGES-1][0:WIDTH][0:MAX42-1];

    // -------------------------------------------------------------------------
    // Initial Booth-bit allocation into heap_1[0]
    // -------------------------------------------------------------------------
    generate
        for (genvar col = 0; col < WIDTH; col++) begin : g_initial
            localparam int FIRST      = first_group(col);
            localparam int DATA_COUNT = last_group(col) - FIRST + 1;
            localparam bit HAS_CORR    = (col % 2 == 0) && (col <= 64);
            localparam bit HAS_COMP    = dadda_compensation::SIGN_COMP[col];

            for (genvar slot = 0; slot < ROWS; slot++) begin : g_slot
                if (slot < DATA_COUNT) begin : data_bit
                    localparam int GROUP_INDEX = FIRST + slot;
                    localparam int BIT_INDEX   = col - 2*GROUP_INDEX;

                    assign heap_1[0][col][slot] =
                        partial_product[GROUP_INDEX][BIT_INDEX];
                end
                else if (HAS_CORR && slot == DATA_COUNT) begin : correction
                    assign heap_1[0][col][slot] = correction_bit[col/2];
                end
                else if (HAS_COMP &&
                         slot == DATA_COUNT + int'(HAS_CORR)) begin : compensation
                    assign heap_1[0][col][slot] = 1'b1;
                end
                else begin : unused_bit
                    assign heap_1[0][col][slot] = 1'b0;
                end
            end
        end
    endgenerate

    // =========================================================================
    // PIPELINE STAGE 1: Booth + D0 + D1
    // =========================================================================
    generate
        for (genvar st = 0; st < 2; st++) begin : g_stage1
            localparam int GST = st;

            for (genvar k = 0; k < MAX42; k++) begin : g_start_link
                assign link[GST][0][k] = 1'b0;
            end

            for (genvar col = 0; col < WIDTH; col++) begin : g_column
                localparam int H         = int'(PLAN.height[GST][col]);
                localparam int Q         = int'(PLAN.n_42[GST][col]);
                localparam int F         = int'(PLAN.n_fa[GST][col]);
                localparam int A         = int'(PLAN.n_ha[GST][col]);
                localparam int INC       = int'(PLAN.incoming[GST][col]);
                localparam int LIN       = int'(PLAN.links_in[GST][col]);
                localparam int USED      = 4*Q + 3*F + 2*A;
                localparam int PASS      = H - USED;
                localparam int LEFT_LINK = (LIN > Q) ? LIN - Q : 0;
                localparam int NEXT_H    = int'(PLAN.height[GST+1][col]);

                wire [Q+F+A:0] ordinary_carry;

                for (genvar k = 0; k < MAX42; k++) begin : g_link
                    if (k >= Q) begin : inactive
                        assign link[GST][col+1][k] = 1'b0;
                    end
                end

                for (genvar k = 0; k < Q; k++) begin : g_42
                    four_two_comp comp (
                        .a      (heap_1[st][col][4*k]),
                        .b      (heap_1[st][col][4*k+1]),
                        .c      (heap_1[st][col][4*k+2]),
                        .d      (heap_1[st][col][4*k+3]),
                        .cin    (link[GST][col][k]),
                        .s      (heap_1[st+1][col][INC+k]),
                        .cout_1 (link[GST][col+1][k]),
                        .cout_2 (ordinary_carry[k])
                    );
                end

                for (genvar k = 0; k < F; k++) begin : g_fa
                    fulladder fa (
                        .a  (heap_1[st][col][4*Q + 3*k]),
                        .b  (heap_1[st][col][4*Q + 3*k + 1]),
                        .c  (heap_1[st][col][4*Q + 3*k + 2]),
                        .o  (heap_1[st+1][col][INC + Q + k]),
                        .co (ordinary_carry[Q+k])
                    );
                end

                for (genvar k = 0; k < A; k++) begin : g_ha
                    halfadder ha (
                        .a  (heap_1[st][col][4*Q + 3*F + 2*k]),
                        .b  (heap_1[st][col][4*Q + 3*F + 2*k + 1]),
                        .o  (heap_1[st+1][col][INC + Q + F + k]),
                        .co (ordinary_carry[Q+F+k])
                    );
                end

                assign ordinary_carry[Q+F+A] = 1'b0;

                for (genvar k = 0; k < Q+F+A; k++) begin : g_carry
                    if (col+1 < WIDTH) begin : retained
                        assign heap_1[st+1][col+1][k] = ordinary_carry[k];
                    end
                end

                for (genvar k = 0; k < PASS; k++) begin : g_pass
                    assign heap_1[st+1][col][INC + Q + F + A + k] =
                        heap_1[st][col][USED+k];
                end

                for (genvar k = 0; k < LEFT_LINK; k++) begin : g_end_link
                    assign heap_1[st+1][col][INC + Q + F + A + PASS + k] =
                        link[GST][col][Q+k];
                end

                for (genvar k = NEXT_H; k < ROWS; k++) begin : g_pad
                    assign heap_1[st+1][col][k] = 1'b0;
                end
            end
        end
    endgenerate

    // Stage-1 output register: heap after D1.
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < WIDTH; i++) begin
                for (int j = 0; j < ROWS; j++) begin
                    pipe1_heap[i][j] <= 1'b0;
                end
            end
        end
        else begin
            for (int i = 0; i < WIDTH; i++) begin
                for (int j = 0; j < ROWS; j++) begin
                    pipe1_heap[i][j] <= heap_1[2][i][j];
                end
            end
        end
    end

    // Registered stage-1 output becomes local heap level 0 of stage 2.
    generate
        for (genvar col = 0; col < WIDTH; col++) begin : g_pipe1_to_heap2_col
            for (genvar slot = 0; slot < ROWS; slot++) begin : g_pipe1_to_heap2_slot
                assign heap_2[0][col][slot] = pipe1_heap[col][slot];
            end
        end
    endgenerate

    // =========================================================================
    // PIPELINE STAGE 2: D2 + D3 + D4
    // =========================================================================
    generate
        for (genvar st = 0; st < 3; st++) begin : g_stage2
            localparam int GST = st + 2;

            for (genvar k = 0; k < MAX42; k++) begin : g_start_link
                assign link[GST][0][k] = 1'b0;
            end

            for (genvar col = 0; col < WIDTH; col++) begin : g_column
                localparam int H         = int'(PLAN.height[GST][col]);
                localparam int Q         = int'(PLAN.n_42[GST][col]);
                localparam int F         = int'(PLAN.n_fa[GST][col]);
                localparam int A         = int'(PLAN.n_ha[GST][col]);
                localparam int INC       = int'(PLAN.incoming[GST][col]);
                localparam int LIN       = int'(PLAN.links_in[GST][col]);
                localparam int USED      = 4*Q + 3*F + 2*A;
                localparam int PASS      = H - USED;
                localparam int LEFT_LINK = (LIN > Q) ? LIN - Q : 0;
                localparam int NEXT_H    = int'(PLAN.height[GST+1][col]);

                wire [Q+F+A:0] ordinary_carry;

                for (genvar k = 0; k < MAX42; k++) begin : g_link
                    if (k >= Q) begin : inactive
                        assign link[GST][col+1][k] = 1'b0;
                    end
                end

                for (genvar k = 0; k < Q; k++) begin : g_42
                    four_two_comp comp (
                        .a      (heap_2[st][col][4*k]),
                        .b      (heap_2[st][col][4*k+1]),
                        .c      (heap_2[st][col][4*k+2]),
                        .d      (heap_2[st][col][4*k+3]),
                        .cin    (link[GST][col][k]),
                        .s      (heap_2[st+1][col][INC+k]),
                        .cout_1 (link[GST][col+1][k]),
                        .cout_2 (ordinary_carry[k])
                    );
                end

                for (genvar k = 0; k < F; k++) begin : g_fa
                    fulladder fa (
                        .a  (heap_2[st][col][4*Q + 3*k]),
                        .b  (heap_2[st][col][4*Q + 3*k + 1]),
                        .c  (heap_2[st][col][4*Q + 3*k + 2]),
                        .o  (heap_2[st+1][col][INC + Q + k]),
                        .co (ordinary_carry[Q+k])
                    );
                end

                for (genvar k = 0; k < A; k++) begin : g_ha
                    halfadder ha (
                        .a  (heap_2[st][col][4*Q + 3*F + 2*k]),
                        .b  (heap_2[st][col][4*Q + 3*F + 2*k + 1]),
                        .o  (heap_2[st+1][col][INC + Q + F + k]),
                        .co (ordinary_carry[Q+F+k])
                    );
                end

                assign ordinary_carry[Q+F+A] = 1'b0;

                for (genvar k = 0; k < Q+F+A; k++) begin : g_carry
                    if (col+1 < WIDTH) begin : retained
                        assign heap_2[st+1][col+1][k] = ordinary_carry[k];
                    end
                end

                for (genvar k = 0; k < PASS; k++) begin : g_pass
                    assign heap_2[st+1][col][INC + Q + F + A + k] =
                        heap_2[st][col][USED+k];
                end

                for (genvar k = 0; k < LEFT_LINK; k++) begin : g_end_link
                    assign heap_2[st+1][col][INC + Q + F + A + PASS + k] =
                        link[GST][col][Q+k];
                end

                for (genvar k = NEXT_H; k < ROWS; k++) begin : g_pad
                    assign heap_2[st+1][col][k] = 1'b0;
                end
            end
        end
    endgenerate

    // Stage-2 output register: heap after D4.
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < WIDTH; i++) begin
                for (int j = 0; j < ROWS; j++) begin
                    pipe2_heap[i][j] <= 1'b0;
                end
            end
        end
        else begin
            for (int i = 0; i < WIDTH; i++) begin
                for (int j = 0; j < ROWS; j++) begin
                    pipe2_heap[i][j] <= heap_2[3][i][j];
                end
            end
        end
    end

    // Registered stage-2 output becomes local heap level 0 of stage 3.
    generate
        for (genvar col = 0; col < WIDTH; col++) begin : g_pipe2_to_heap3_col
            for (genvar slot = 0; slot < ROWS; slot++) begin : g_pipe2_to_heap3_slot
                assign heap_3[0][col][slot] = pipe2_heap[col][slot];
            end
        end
    endgenerate

    // =========================================================================
    // PIPELINE STAGE 3: D5 + D6 + D7
    // =========================================================================
    generate
        for (genvar st = 0; st < 3; st++) begin : g_stage3
            localparam int GST = st + 5;

            for (genvar k = 0; k < MAX42; k++) begin : g_start_link
                assign link[GST][0][k] = 1'b0;
            end

            for (genvar col = 0; col < WIDTH; col++) begin : g_column
                localparam int H         = int'(PLAN.height[GST][col]);
                localparam int Q         = int'(PLAN.n_42[GST][col]);
                localparam int F         = int'(PLAN.n_fa[GST][col]);
                localparam int A         = int'(PLAN.n_ha[GST][col]);
                localparam int INC       = int'(PLAN.incoming[GST][col]);
                localparam int LIN       = int'(PLAN.links_in[GST][col]);
                localparam int USED      = 4*Q + 3*F + 2*A;
                localparam int PASS      = H - USED;
                localparam int LEFT_LINK = (LIN > Q) ? LIN - Q : 0;
                localparam int NEXT_H    = int'(PLAN.height[GST+1][col]);

                wire [Q+F+A:0] ordinary_carry;

                for (genvar k = 0; k < MAX42; k++) begin : g_link
                    if (k >= Q) begin : inactive
                        assign link[GST][col+1][k] = 1'b0;
                    end
                end

                for (genvar k = 0; k < Q; k++) begin : g_42
                    four_two_comp comp (
                        .a      (heap_3[st][col][4*k]),
                        .b      (heap_3[st][col][4*k+1]),
                        .c      (heap_3[st][col][4*k+2]),
                        .d      (heap_3[st][col][4*k+3]),
                        .cin    (link[GST][col][k]),
                        .s      (heap_3[st+1][col][INC+k]),
                        .cout_1 (link[GST][col+1][k]),
                        .cout_2 (ordinary_carry[k])
                    );
                end

                for (genvar k = 0; k < F; k++) begin : g_fa
                    fulladder fa (
                        .a  (heap_3[st][col][4*Q + 3*k]),
                        .b  (heap_3[st][col][4*Q + 3*k + 1]),
                        .c  (heap_3[st][col][4*Q + 3*k + 2]),
                        .o  (heap_3[st+1][col][INC + Q + k]),
                        .co (ordinary_carry[Q+k])
                    );
                end

                for (genvar k = 0; k < A; k++) begin : g_ha
                    halfadder ha (
                        .a  (heap_3[st][col][4*Q + 3*F + 2*k]),
                        .b  (heap_3[st][col][4*Q + 3*F + 2*k + 1]),
                        .o  (heap_3[st+1][col][INC + Q + F + k]),
                        .co (ordinary_carry[Q+F+k])
                    );
                end

                assign ordinary_carry[Q+F+A] = 1'b0;

                for (genvar k = 0; k < Q+F+A; k++) begin : g_carry
                    if (col+1 < WIDTH) begin : retained
                        assign heap_3[st+1][col+1][k] = ordinary_carry[k];
                    end
                end

                for (genvar k = 0; k < PASS; k++) begin : g_pass
                    assign heap_3[st+1][col][INC + Q + F + A + k] =
                        heap_3[st][col][USED+k];
                end

                for (genvar k = 0; k < LEFT_LINK; k++) begin : g_end_link
                    assign heap_3[st+1][col][INC + Q + F + A + PASS + k] =
                        link[GST][col][Q+k];
                end

                for (genvar k = NEXT_H; k < ROWS; k++) begin : g_pad
                    assign heap_3[st+1][col][k] = 1'b0;
                end
            end
        end
    endgenerate

    // Stage-3 output register. D7 has reduced the heap to two rows,
    // so only those two 128-bit rows need to be registered.
    logic [127:0] row0_reg;
    logic [127:0] row1_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            row0_reg <= '0;
            row1_reg <= '0;
        end
        else begin
            for (int col = 0; col < WIDTH; col++) begin
                row0_reg[col] <= heap_3[3][col][0];
                row1_reg[col] <= heap_3[3][col][1];
            end
        end
    end

    // =========================================================================
    // PIPELINE STAGE 4: 128-bit Kogge-Stone final carry-propagate adder
    // =========================================================================
    logic [127:0] w_result;
    logic         final_cout;

    kogge_stone_128 final_adder (
        .a    (row0_reg),
        .b    (row1_reg),
        .sub  (1'b0),
        .sum  (w_result),
        .cout (final_cout)
    );

    // Stage-4 output register.
    always_ff @(posedge clk) begin
        if (reset)
            result <= '0;
        else
            result <= w_result;
    end

endmodule

`default_nettype wire