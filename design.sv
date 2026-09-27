`timescale 1ns/1ps

module adc_model #(
    parameter int    N_BITS     = 8,       // resolution
    parameter real   VREF       = 1.0,     // reference voltage (V)
    parameter real   OFFSET     = 0.002,   // offset error (V)
    parameter real   GAIN_ERR   = 0.01,    // gain error (fractional, e.g. 1%)
    parameter real   NOISE_RMS  = 0.0005,  // input-referred noise (V rms)
    parameter real   DNL_MAX    = 0.3      // max DNL in LSBs (random per-code)
)(
    input  wreal analog_in,      // analog input voltage
    input  logic clk,            // sampling clock
    input  logic rst_n,          // active-low reset
    output logic [N_BITS-1:0] dout,  // digital output code
    output logic dvalid          // output valid strobe
);

    real vin_sampled;
    real vin_noisy;
    real lsb;
    real code_real;
    real dnl_error;

    assign lsb = VREF / (2.0 ** N_BITS);

    function automatic real gauss_noise(real sigma);
        real u;
        int  i;
        u = 0;
        for (i = 0; i < 12; i++)
            u += ($urandom % 1000) / 1000.0;
        u = u - 6.0;
        return u * sigma;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout   <= '0;
            dvalid <= 1'b0;
        end else begin
            vin_sampled = analog_in;
            vin_sampled = vin_sampled + OFFSET;
            vin_sampled = vin_sampled * (1.0 + GAIN_ERR);
            vin_noisy = vin_sampled + gauss_noise(NOISE_RMS);

            if (vin_noisy >= VREF)
                code_real = 2.0 ** N_BITS - 1;
            else if (vin_noisy <= 0)
                code_real = 0;
            else
                code_real = int'(vin_noisy / lsb);

            dnl_error = DNL_MAX * (($urandom % 1000) / 1000.0 - 0.5);
            code_real = code_real + dnl_error;

            if (code_real >= 2.0 ** N_BITS - 1)
                dout <= {N_BITS{1'b1}};
            else if (code_real <= 0)
                dout <= '0;
            else
                dout <= int'(code_real + 0.5);

            dvalid <= 1'b1;
        end
    end

endmodule
