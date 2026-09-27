`timescale 1ns/1ps

module tb_adc_model;

    localparam int  N_BITS  = 8;
    localparam real VREF    = 1.0;
    localparam real CLK_PER = 10.0;
    localparam real LSB     = VREF / (2.0 ** N_BITS);
    localparam int  CODE_TOL = 3;

    wreal                 analog_in;
    logic                 clk;
    logic                 rst_n;
    logic [N_BITS-1:0]    dout;
    logic                 dvalid;

    real vin_at_sample;
    int  ideal_code;
    int  errors;
    int  checks;

    adc_model #(
        .N_BITS (N_BITS),
        .VREF   (VREF)
    ) dut (
        .analog_in (analog_in),
        .clk       (clk),
        .rst_n     (rst_n),
        .dout      (dout),
        .dvalid    (dvalid)
    );

    initial clk = 1'b0;
    always #(CLK_PER/2.0) clk = ~clk;

    task automatic drive_analog(real v);
        analog_in = v;
    endtask

    task automatic apply_ramp(int steps);
        real step_v;
        step_v = VREF / steps;
        for (int i = 0; i <= steps; i++) begin
            drive_analog(i * step_v);
            @(posedge clk);
        end
    endtask

    task automatic apply_random(int n);
        real r;
        for (int i = 0; i < n; i++) begin
            r = $urandom_range(0, 1000) / 1000.0 * (VREF * 1.2) - (VREF * 0.1);
            drive_analog(r);
            @(posedge clk);
        end
    endtask

    real   pending_vin;
    logic  pending_valid;

    always @(posedge clk) begin
        pending_vin   = analog_in;
        pending_valid = rst_n;
    end

    always @(negedge clk) begin
        if (pending_valid && dvalid) begin
            checks++;
            if (pending_vin >= VREF)
                ideal_code = (2 ** N_BITS) - 1;
            else if (pending_vin <= 0)
                ideal_code = 0;
            else
                ideal_code = int'(pending_vin / LSB);

            if (!(dout inside {[(ideal_code - CODE_TOL >= 0 ? ideal_code - CODE_TOL : 0) :
                                (ideal_code + CODE_TOL <= (2**N_BITS)-1 ? ideal_code + CODE_TOL : (2**N_BITS)-1)]})) begin
                errors++;
                $display("[%0t] MISMATCH: vin=%.5f ideal=%0d actual=%0d",
                          $time, pending_vin, ideal_code, dout);
            end
        end
    end

    property p_no_unknown;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(dout);
    endproperty
    a_no_unknown: assert property (p_no_unknown)
        else $error("[%0t] dout went unknown", $time);

    property p_dvalid_after_reset;
        @(posedge clk) $rose(rst_n) |=> dvalid;
    endproperty
    a_dvalid_after_reset: assert property (p_dvalid_after_reset)
        else $error("[%0t] dvalid did not assert after reset release", $time);

    property p_rail_high;
        @(posedge clk) disable iff (!rst_n)
        (analog_in >= VREF) |=> (dout == {N_BITS{1'b1}});
    endproperty
    a_rail_high: assert property (p_rail_high)
        else $error("[%0t] failed to saturate high for vin=%.4f", $time, analog_in);

    property p_rail_low;
        @(posedge clk) disable iff (!rst_n)
        (analog_in <= 0.0) |=> (dout == '0);
    endproperty
    a_rail_low: assert property (p_rail_low)
        else $error("[%0t] failed to clamp low for vin=%.4f", $time, analog_in);

    property p_reset_clears;
        @(posedge clk) !rst_n |-> (dout == '0);
    endproperty
    a_reset_clears: assert property (p_reset_clears)
        else $error("[%0t] dout not cleared during reset", $time);

    covergroup cg_codes @(posedge clk);
        cp_code: coverpoint dout {
            bins low  = {[0:15]};
            bins mid  = {[16:239]};
            bins high = {[240:255]};
        }
    endgroup
    cg_codes cg_inst;

    initial begin
        cg_inst = new();
        errors  = 0;
        checks  = 0;
        rst_n   = 1'b0;
        analog_in = 0.0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        drive_analog(0.0);           @(posedge clk);
        drive_analog(VREF);          @(posedge clk);
        drive_analog(VREF / 2.0);    @(posedge clk);
        drive_analog(-0.05);         @(posedge clk);
        drive_analog(VREF + 0.05);   @(posedge clk);

        apply_ramp(64);
        apply_random(200);

        repeat (5) @(posedge clk);

        $display("--------------------------------------------------");
        $display(" ADC self-check complete");
        $display(" total comparisons : %0d", checks);
        $display(" mismatches        : %0d", errors);
        if (errors == 0)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");
        $display(" code coverage     : %.1f%%", cg_inst.get_coverage());
        $display("--------------------------------------------------");

        $finish;
    end

    initial begin
        $dumpfile("adc_tb.vcd");
        $dumpvars(0, tb_adc_model);
    end

endmodule
