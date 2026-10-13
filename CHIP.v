//-------------------------------------------------------------//
//- Digital IC Design 2026                                     //
//-                                                            //
//- Final Project: FP_MUL                                      //
//-------------------------------------------------------------//
`timescale 1ns/1ps

module CHIP(CLK, RESET, ENABLE, DATA_IN, DATA_OUT, READY);

//Parameter
parameter fp_latency=3;

// I/O Ports
input           CLK; //clock signal
input           RESET; //sync. RESET=1
input           ENABLE; //input data sequence when ENABLE =1
input     [7:0] DATA_IN; //input data sequence
output    reg [7:0] DATA_OUT; //ouput data sequence
output    reg       READY; //output data is READY when READY=1


// FSM, 0: "LOAD", 1: "COMP", 2: "OUT"
reg [1:0] state;
reg [3:0] load_cnt; // 0...15
reg [2:0] comp_cnt; // 0...7 (7 pipeline stages)
reg [2:0] out_cnt;  // 0...7

// state transition
always @(posedge CLK)
begin
    if(RESET)
    begin
        state <= 0;
        load_cnt <= 0;
        comp_cnt <= 0;
        out_cnt <= 0;
    end
    else
    begin
        case(state)
            0:  // "LOAD"
            begin
                if(ENABLE)
                begin
                    if(load_cnt == 15)
                    begin
                        state <= 1;
                        load_cnt <= 0;
                    end
                    else
                        load_cnt <= load_cnt + 1;
                end
            end
            1:  // "COMP"
            begin
                if(comp_cnt == 7)
                begin
                    state <= 2;
                    comp_cnt <= 0;
                end
                else
                    comp_cnt <= comp_cnt + 1;
            end
            2:  // "OUT"
            begin
                if(out_cnt == 7)
                begin
                    state <= 0;
                    out_cnt <= 0;
                end
                else
                    out_cnt <= out_cnt + 1;
            end
        endcase
    end
end

// load input data
reg [63:0] A_in, B_in;

always @(posedge CLK)
begin
    if(RESET)
    begin
        A_in <= 0;
        B_in <= 0;
    end
    else if(state==0 && ENABLE)
    begin
        if(load_cnt[3] == 0)   // 0...7
            A_in <= {DATA_IN, A_in[63:8]};
        else // 8...15
            B_in <= {DATA_IN, B_in[63:8]};
    end
end

wire s_a = A_in[63];     // sign bit
wire [10:0] e_a = A_in[62:52];   // exponent bits
wire [51:0] f_a = A_in[51:0];    // fraction bits
wire s_b = B_in[63];
wire [10:0] e_b = B_in[62:52];
wire [51:0] f_b = B_in[51:0];



wire a_zero = (e_a == 0) && (f_a == 0);   // means ZERO
wire b_zero = (e_b == 0) && (f_b == 0);
wire a_inf = (e_a == 2047) && (f_a == 0); // means INF
wire b_inf = (e_b == 2047) && (f_b == 0);
wire a_nan = (e_a == 2047) && (f_a != 0); // means NaN
wire b_nan = (e_b == 2047) && (f_b != 0);





// C1
reg s_c1;
reg [10:0] e_a_c1, e_b_c1;
reg [52:0] m_a_c1, m_b_c1;  // {implicit 1, fraction}
reg a_zero_c1, b_zero_c1;
reg a_inf_c1, b_inf_c1;
reg any_nan_c1;

always @(posedge CLK)
begin
    if(RESET)
    begin
        s_c1 <= 0;
        e_a_c1 <= 0;
        e_b_c1 <= 0;
        m_a_c1 <= 0;
        m_b_c1 <= 0;
        a_zero_c1 <= 0;
        b_zero_c1 <= 0;
        a_inf_c1 <= 0;
        b_inf_c1 <= 0;
        any_nan_c1 <= 0;
    end
    else
    begin
        s_c1 <= s_a ^ s_b;  // final sign bit
        e_a_c1 <= e_a;
        e_b_c1 <= e_b;
        m_a_c1 <= {1'b1, f_a};
        m_b_c1 <= {1'b1, f_b};
        a_zero_c1 <= a_zero;
        b_zero_c1 <= b_zero;
        a_inf_c1 <= a_inf;
        b_inf_c1 <= b_inf;
        any_nan_c1 <= a_nan || b_nan;
    end
end





// C2
reg signed [12:0] e_sum_c2;   // 11bit + 2bit = 13bit
reg [26:0] a_h_c2, b_h_c2;    // high 27 bits
reg [25:0] a_l_c2, b_l_c2;    // low 26 bits
reg s_c2;
reg a_zero_c2, b_zero_c2;
reg a_inf_c2, b_inf_c2;
reg any_nan_c2;

always @(posedge CLK)
begin
    if(RESET)
    begin
        e_sum_c2 <= 0;
        a_h_c2 <= 0;
        b_h_c2 <= 0;
        a_l_c2 <= 0;
        b_l_c2 <= 0;
        s_c2 <= 0;
        a_zero_c2 <= 0;
        b_zero_c2 <= 0;
        a_inf_c2 <= 0;
        b_inf_c2 <= 0;
        any_nan_c2 <= 0;
    end
    else
    begin
        e_sum_c2 <= $signed({2'b00, e_a_c1}) + $signed({2'b00, e_b_c1}) - $signed({2'b00, 11'd1023});   // e_a + e_b - bias(1023)
        a_h_c2 <= m_a_c1[52:26];    
        b_h_c2 <= m_b_c1[52:26];
        a_l_c2 <= m_a_c1[25:0];
        b_l_c2 <= m_b_c1[25:0];
        s_c2 <= s_c1;
        a_zero_c2 <= a_zero_c1;
        b_zero_c2 <= b_zero_c1;
        a_inf_c2 <= a_inf_c1;
        b_inf_c2 <= b_inf_c1;
        any_nan_c2 <= any_nan_c1;
    end
end





// C3 (Partial Product)
reg [53:0] pp_hh_c3;    // 27 x 27 -> 54 bits
reg [52:0] pp_hl_c3;    // 27 x 26 -> 53 bits
reg [52:0] pp_lh_c3;    // 26 x 27 -> 53 bits
reg [51:0] pp_ll_c3;    // 26 x 26 -> 52 bits
reg signed [12:0] e_sum_c3;
reg s_c3, a_zero_c3, b_zero_c3, a_inf_c3, b_inf_c3, any_nan_c3;

always @(posedge CLK)
begin
    if(RESET)
    begin
        pp_hh_c3 <= 0;
        pp_hl_c3 <= 0;
        pp_lh_c3 <= 0;
        pp_ll_c3 <= 0;
        e_sum_c3 <= 0;
        s_c3 <= 0;
        a_zero_c3 <= 0;
        b_zero_c3 <= 0;
        a_inf_c3 <= 0;
        b_inf_c3 <= 0;
        any_nan_c3 <= 0;
    end
    else
    begin
        pp_hh_c3 <= a_h_c2 * b_h_c2;
        pp_hl_c3 <= a_h_c2 * b_l_c2;
        pp_lh_c3 <= a_l_c2 * b_h_c2;
        pp_ll_c3 <= a_l_c2 * b_l_c2;
        e_sum_c3 <= e_sum_c2;
        s_c3 <= s_c2;
        a_zero_c3 <= a_zero_c2;
        b_zero_c3 <= b_zero_c2;
        a_inf_c3 <= a_inf_c2;
        b_inf_c3 <= b_inf_c2;
        any_nan_c3 <= any_nan_c2;
    end
end






// C4
reg [53:0] pp_hh_c4;
reg [53:0] pp_mid_c4;    // pp_hl + pp_lh
reg [51:0] pp_ll_c4;
reg signed [12:0] e_sum_c4;
reg s_c4, a_zero_c4, b_zero_c4, a_inf_c4, b_inf_c4, any_nan_c4;

always @(posedge CLK)
begin
    if(RESET)
    begin
        pp_hh_c4 <= 0;
        pp_mid_c4 <= 0;
        pp_ll_c4 <= 0;
        e_sum_c4 <= 0;
        s_c4 <= 0;
        a_zero_c4 <= 0;
        b_zero_c4 <= 0;
        a_inf_c4 <= 0;
        b_inf_c4 <= 0;
        any_nan_c4 <= 0;
    end
    else
    begin
        pp_hh_c4 <= pp_hh_c3;
        pp_mid_c4 <= {1'b0, pp_hl_c3} + {1'b0, pp_lh_c3};
        pp_ll_c4 <= pp_ll_c3;
        e_sum_c4 <= e_sum_c3;
        s_c4 <= s_c3;
        a_zero_c4 <= a_zero_c3;
        b_zero_c4 <= b_zero_c3;
        a_inf_c4 <= a_inf_c3;
        b_inf_c4 <= b_inf_c3;
        any_nan_c4 <= any_nan_c3;
    end
end






// C5
reg [54:0] upper_combo_c5;     // pp_hh + pp_mid(first half)
reg [52:0] lower_combo_c5;     // pp_ll + pp_mid(second half)
reg signed [12:0] e_sum_c5;
reg s_c5, a_zero_c5, b_zero_c5, a_inf_c5, b_inf_c5, any_nan_c5;

always @(posedge CLK)
begin
    if(RESET)
    begin
        upper_combo_c5 <= 0;
        lower_combo_c5 <= 0;
        e_sum_c5 <= 0;
        s_c5 <= 0;
        a_zero_c5 <= 0;
        b_zero_c5 <= 0;
        a_inf_c5 <= 0;
        b_inf_c5 <= 0;
        any_nan_c5 <= 0;
    end
    else
    begin
        upper_combo_c5 <= {1'b0, pp_hh_c4} + {27'd0, pp_mid_c4[53:26]};
        lower_combo_c5 <= {1'b0, pp_mid_c4[25:0], 26'd0} + {1'b0, pp_ll_c4};
        e_sum_c5 <= e_sum_c4;
        s_c5 <= s_c4;
        a_zero_c5 <= a_zero_c4;
        b_zero_c5 <= b_zero_c4;
        a_inf_c5 <= a_inf_c4;
        b_inf_c5 <= b_inf_c4;
        any_nan_c5 <= any_nan_c4;
    end
end





// C6
wire [53:0] prod_upper_c5 = upper_combo_c5[53:0] + {53'd0, lower_combo_c5[52]};   // upper_combo + lower_combo's carry out
wire [105:0] prod_full_c5 = {prod_upper_c5, lower_combo_c5[51:0]};   // final product


// [1,2) * [1,2) = [1,4)
wire norm_no_shift_c5 = prod_full_c5[105];   // detect leading 1
// if not leading 1, left shift 1 bit
wire [105:0] prod_norm_c5 = norm_no_shift_c5 ? prod_full_c5 : {prod_full_c5[104:0], 1'b0};
// if don't left shift 1 bit, then exponent plus 1   
wire signed [12:0] e_norm_c5 = e_sum_c5 + {12'd0, norm_no_shift_c5};

reg [52:0] mant_c6;
reg guard_c6;
reg sticky_c6;
reg signed [12:0] e_norm_c6;
reg s_c6, a_zero_c6, b_zero_c6, a_inf_c6, b_inf_c6, any_nan_c6;

always @(posedge CLK)
begin
    if(RESET)
    begin
        mant_c6 <= 0;
        guard_c6 <= 0;
        sticky_c6 <= 0;
        e_norm_c6 <= 0;
        s_c6 <= 0;
        a_zero_c6 <= 0;
        b_zero_c6 <= 0;
        a_inf_c6 <= 0;
        b_inf_c6 <= 0;
        any_nan_c6 <= 0;
    end
    else
    begin
        mant_c6 <= prod_norm_c5[105:53];  // legal 52 bits
        guard_c6 <= prod_norm_c5[52];
        sticky_c6 <= |prod_norm_c5[51:0];
        e_norm_c6 <= e_norm_c5;
        s_c6 <= s_c5;
        a_zero_c6 <= a_zero_c5;
        b_zero_c6 <= b_zero_c5;
        a_inf_c6 <= a_inf_c5;
        b_inf_c6 <= b_inf_c5;
        any_nan_c6 <= any_nan_c5;
    end
end




// C7
// round to nearest even
// if GS=10 means half, then round to even
wire round_up_c6 = guard_c6 & (sticky_c6 | mant_c6[0]);
// round
wire [53:0] mant_plus_c6 = {1'b0, mant_c6} + {53'd0, round_up_c6};
wire round_overflow_c6 = mant_plus_c6[53];
// if overflow, keep legal 52 bits
wire [52:0] mant_after_c6 = round_overflow_c6 ? mant_plus_c6[53:1] : mant_plus_c6[52:0];
// if overflow, exponent plus 1
wire signed [12:0] e_final_c6 = e_norm_c6 + {12'd0, round_overflow_c6};

reg [52:0] mant_c7;
reg signed [12:0] e_final_c7;
reg s_c7, a_zero_c7, b_zero_c7, a_inf_c7, b_inf_c7, any_nan_c7;

always @(posedge CLK)
begin
    if(RESET)
    begin
        mant_c7 <= 0;
        e_final_c7 <= 0;
        s_c7 <= 0;
        a_zero_c7 <= 0;
        b_zero_c7 <= 0;
        a_inf_c7 <= 0;
        b_inf_c7 <= 0;
        any_nan_c7 <= 0;
    end
    else
    begin
        mant_c7 <= mant_after_c6;
        e_final_c7 <= e_final_c6;
        s_c7 <= s_c6;
        a_zero_c7 <= a_zero_c6;
        b_zero_c7 <= b_zero_c6;
        a_inf_c7 <= a_inf_c6;
        b_inf_c7 <= b_inf_c6;
        any_nan_c7 <= any_nan_c6;
    end
end




// C8
wire is_inf_x_zero_c7 = (a_inf_c7 && b_zero_c7) || (a_zero_c7 && b_inf_c7);    // INF x ZERO = NAN
wire is_nan_out_c7 = any_nan_c7 || is_inf_x_zero_c7;
wire is_inf_out_c7 = (a_inf_c7 || b_inf_c7) && ~is_nan_out_c7;    // if not NAN, then detect whether is INF
wire is_zero_out_c7 = (a_zero_c7 || b_zero_c7) && ~is_nan_out_c7 && ~is_inf_out_c7; // if not NAN and INF, then detect whether is ZERO
wire is_overflow_c7 = (e_final_c7 >= 13'sd2047);
wire is_underflow_c7 = (e_final_c7 <= 13'sd0);

reg [63:0] result_comb;
always @(*)
begin
    if(is_nan_out_c7)               // NAN
        result_comb = {1'b0, 11'd2047, 1'b1, 51'd0};
    else if(is_inf_out_c7)          // INF
        result_comb = {s_c7, 11'd2047, 52'd0};
    else if(is_zero_out_c7)         // ZERO
        result_comb = {s_c7, 11'd0, 52'd0};
    else if(is_overflow_c7)         // overflow -> INF
        result_comb = {s_c7, 11'd2047, 52'd0};
    else if(is_underflow_c7)        // underflow -> ZERO
        result_comb = {s_c7, 11'd0, 52'd0};
    else
        result_comb = {s_c7, e_final_c7[10:0], mant_c7[51:0]};
end





// output
reg [63:0] out_shift;

always @(posedge CLK)
begin
    if(RESET)
    begin
        DATA_OUT <= 0;
        READY <= 0;
        out_shift <= 0;
    end
    
    else if(state == 1 && comp_cnt == 7)
    begin
        DATA_OUT <= result_comb[7:0];
        out_shift <= {8'd0, result_comb[63:8]};
        READY <= 1;
    end
    
    else if(state == 2 && out_cnt != 7)
    begin
        DATA_OUT <= out_shift[7:0];
        out_shift <= {8'd0, out_shift[63:8]};
        READY <= 1;
    end
    
    else
    begin
        DATA_OUT <= 0;
        out_shift <= 0;
        READY <= 0;
    end
end

endmodule