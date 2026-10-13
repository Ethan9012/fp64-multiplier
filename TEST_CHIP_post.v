//---------------------------------------------------------//
//- Digital IC Design 2026                                 //
//-                                                        //
//- Final Project: FP_MUL                                  //
//---------------------------------------------------------//
`timescale 1ns/1ps
`define SDFFILE    "../Innovus/CHIP.sdf"
`include "../Innovus/CHIP.v"

module TEST;

// clock period = 2.0GHz = 0.5ns
parameter CYCLE=0.5;
parameter SIM_CYCLE=300;

reg           CLK, RESET;
reg           ENABLE;
reg    [7:0]  DATA_IN;
wire   [7:0]  DATA_OUT;
wire          READY;

reg    [63:0] A, B; //FP input
reg    [63:0] Z; // Actual output
reg    [63:0] C; // Expect output
reg    [31:0] err_count;
reg    [31:0] sim_count;
integer       i;

reg    [63:0] rand_A, rand_B;

initial     $sdf_annotate(`SDFFILE, CHIP_T);

CHIP CHIP_T(.CLK(CLK), .RESET(RESET), .ENABLE(ENABLE),
            .DATA_IN(DATA_IN),
            .DATA_OUT(DATA_OUT), .READY(READY));

always #(CYCLE/2.0) CLK=~CLK;


task auto_test(input [63:0] val_A,
               input [63:0] val_B);

    real real_A, real_B, real_Z;
    integer i;
    begin
        A = val_A;
        B = val_B;

        real_A = $bitstoreal(A);
        real_B = $bitstoreal(B);
        real_Z = real_A * real_B;
        C = $realtobits(real_Z);
        
        for(i=0; i<8; i=i+1)
        begin
            @(negedge CLK);
            ENABLE = 1'b1;
            DATA_IN = A[(i*8) +: 8];
        end

        for(i=0; i<8; i=i+1)
        begin
            @(negedge CLK);
            ENABLE = 1'b1;
            DATA_IN = B[(i*8) +: 8];
        end

        @(negedge CLK);
        ENABLE = 1'b0;

        while(READY !== 1'b1)
            @(negedge CLK);

        for(i=0; i<8; i=i+1)
        begin
            Z[(i*8) +: 8] = DATA_OUT;
            if(i<7)
                @(negedge CLK);
        end

        // if NaN, then don't care sign bit
        if(Z === C || ( Z[62:52] == 11'h7FF && Z[51:0] != 0 && 
                        C[62:52] == 11'h7FF && C[51:0] != 0))
        begin
            $display("[PASS]");
            $display("Expected : %b", C);
            $display("Actual   : %b\n", Z);
        end
        else
        begin
            err_count = err_count + 1;
            $display("[FAIL]");
            $display("Expected : %b", C);
            $display("Actual   : %b\n", Z);
        end

    end
endtask


initial
begin
    $toggle_count("TEST.CHIP_T");

    $fsdbDumpfile("CHIP.fsdb");
    $fsdbDumpvars;
    CLK=0; RESET=0; ENABLE=0; DATA_IN=0; err_count=0;

    @(negedge CLK) RESET = 1;
    @(negedge CLK) RESET = 0;

    // set test pattern
    $display("A = 1.5,  B = 2.0");
    auto_test($realtobits(1.5), $realtobits(2.0));
    $display("A = -3.14,  B = 2.5");
    auto_test($realtobits(-3.14), $realtobits(2.5));
    $display("A = 0.3333333333333333,  B = 3.0");
    auto_test($realtobits(0.3333333333333333), $realtobits(3.0));


    // random test patten
    $display("------random test pattern------");
    repeat(20)
    begin
        rand_A = {$random, $random};
        rand_B = {$random, $random};
        $display("A = %.17e,  B = %.17e", $bitstoreal(rand_A), $bitstoreal(rand_B));
        auto_test(rand_A, rand_B);
    end


    // special case test pattern
    $display("A = 0.0,  B = 3.0");    // ZERO
    auto_test(64'h0000000000000000, $realtobits(3.0));
    $display("A = INF,  B = 2.0");    // INF
    auto_test(64'h7FF0000000000000, $realtobits(2.0));
    $display("A = NaN,  B = 2.0");    // NaN
    auto_test(64'h7FF8000000000000, $realtobits(2.0));
    $display("A = INF,  B = ZERO");   // INF * ZERO = NaN
    auto_test(64'h7FF0000000000000, 64'h0000000000000000);
    $display("A = Max,  B = 2.0");    // overflow -> INF
    auto_test(64'h7FEFFFFFFFFFFFFF, $realtobits(2.0));
    $display("A = Min,  B = Min");    // underflow -> ZERO
    auto_test(64'h0010000000000000, 64'h0010000000000000);


    // report
    $display("=================================================");
    if(err_count != 0)
        $display("Simulation Fail!");
    else
    begin
        $display("Simulation OK!!!!");
    end
    $display("=================================================");

    $toggle_count_report_flat("CHIP.tcf", "TEST.CHIP_T");

    #50 $finish;
end

endmodule