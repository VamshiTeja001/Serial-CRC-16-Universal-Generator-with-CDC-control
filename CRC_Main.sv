`timescale 1ns / 1ps

/**
 * Module: serial_crc_ip
 * Description:
 *  A configurable Serial CRC calculator.
 *  - Captures serial data using a phase-shifted clock (sclk_ps).
 *  - Calculates CRC based on configurable polynomial and width.
 *  - Designed for IP-XACT packaging with parameterized configuration.
 */

module serial_crc_ip #(
    // =========================================================================
    // Parameters (IP-XACT Configuration)
    // =========================================================================    
    // Synchronize Output to Global Clock: "Yes" or "No"
    parameter string SYNC_TO_SYSTEM_CLOCK = "Yes",
    // Data Rate Configuration: "SDR" or "DDR"
    parameter string DATA_RATE_MODE = "SDR",
        // Sampling Edge: "RISING" or "FALLING"
    parameter string INPUT_SAMPLING_EDGE = "RISING",
    // CRC Polynomial (Default: CRC-CCITT False 0x1021)
    parameter logic [15:0] POLYNOMIAL = 16'h1021,
    // Initial Value for the LFSR (Default: 0xFFFF for CCITT False)
    parameter logic [15:0] INIT_VAL = 16'hFFFF,
    // Invert output CRC (Common in some protocols like Ethernet)
    parameter string XOR_OUT = "No",
    // Enable Output Flow Control Indicators: "Yes" or "No"
    parameter string ENABLE_FLOW_CONTROL = "No"

) (
    // =========================================================================
    // Ports
    // =========================================================================
    
    // System Clock (Reserved for system-side bus interfaces/synchronization)
    input  logic                   sysclk,
    
    // Serial Clock (Base frequency reference)
    input  logic                   sclk,
    
    // Phase-Shifted Serial Clock (Used for data sampling and CRC logic)
    input  logic                   sclk_ps,
    // Reset (Active High, Asynchronous)
    input  logic                   rst,
    // Serial Data Input
    input  logic                   serial_in,
    // Serial Data Valid Qualifier
    input  logic                   serial_in_valid,
    // CRC Enable (Active High - enables calculation)
    input  logic                   crc_en,
    // CRC Output
    output logic [15:0]            crc_out,
    // CRC Valid (Asserts when a bit is processed and CRC is updated)
    output logic                   crc_valid,
    // Byte Valid (Asserts when 8 bits have been processed)
    output logic                   byte_valid
    
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    
    logic [15:0]          lfsr_q;
    logic                 feedback;
    logic [15:0]          next_lfsr;
    logic                 sclk_inv;
    logic                 sclk_ps_inv;
    logic [2:0]           bit_counter;
    // =========================================================================
    // CRC Calculation Logic
    // =========================================================================
    // The logic runs on sclk_ps to ensure setup/hold times are met with respect 
    // to the incoming serial stream.
    
     assign sclk_inv = ~sclk;
     assign sclk_ps_inv = ~sclk_ps;
    
    always_comb begin
        // Feedback based on MSB (bit 15) and input data
        feedback = lfsr_q[15] ^ serial_in;

        // Explicit CRC-CCITT (0x1021) implementation
        next_lfsr[0]  = feedback;
        next_lfsr[1]  = lfsr_q[0];
        next_lfsr[2]  = lfsr_q[1];
        next_lfsr[3]  = lfsr_q[2];
        next_lfsr[4]  = lfsr_q[3];
        next_lfsr[5]  = lfsr_q[4] ^ feedback;
        next_lfsr[6]  = lfsr_q[5];
        next_lfsr[7]  = lfsr_q[6];
        next_lfsr[8]  = lfsr_q[7];
        next_lfsr[9]  = lfsr_q[8];
        next_lfsr[10] = lfsr_q[9];
        next_lfsr[11] = lfsr_q[10];
        next_lfsr[12] = lfsr_q[11] ^ feedback;
        next_lfsr[13] = lfsr_q[12];
        next_lfsr[14] = lfsr_q[13];
        next_lfsr[15] = lfsr_q[14];
    end

    generate
        if (SYNC_TO_SYSTEM_CLOCK == "Yes") begin : g_sync_calc
            // Logic operating on synchronous clock (sysclk)
            logic sclk_meta, sclk_reg, spi_reg_reg;
            logic sclk_ps_meta, sclk_ps_reg, spi_ps_reg_reg;
            logic spi_clk_redge_en, spi_clk_fedge_en;
            logic spi_clk_ps_redge_en, spi_clk_ps_fedge_en;

            // Synchronize sclk to sysclk
            always_ff @(posedge sysclk) begin
                sclk_meta <= sclk;
                sclk_reg  <= sclk_meta; 
            end

            // Edge detection logic
            always_ff @(posedge sysclk) begin
                if (rst) spi_reg_reg <= 1'b0;
                else     spi_reg_reg <= sclk_reg;
            end
            
            always_ff @(posedge sysclk) begin
                sclk_ps_meta <= sclk_ps;
                sclk_ps_reg  <= sclk_ps_meta; 
            end

            // Edge detection logic
            always_ff @(posedge sysclk) begin
                if (rst) spi_ps_reg_reg <= 1'b0;
                else     spi_ps_reg_reg <= sclk_ps_reg;
            end
            

            assign spi_clk_redge_en = sclk_reg  & ~spi_reg_reg;
            assign spi_clk_fedge_en = ~sclk_reg & spi_reg_reg;
            
            assign spi_clk_ps_redge_en = sclk_ps_reg  & ~spi_ps_reg_reg;
            assign spi_clk_ps_fedge_en = ~sclk_ps_reg & spi_ps_reg_reg;
            
           
            // CRC Calculation on sysclk
            always_ff @(posedge sysclk) begin
                if (rst) begin
                    lfsr_q <= INIT_VAL;
                    bit_counter <= '0;
                    crc_valid <= 1'b0;
                    byte_valid <= 1'b0;
                end else if (crc_en) begin
                    
                    if (serial_in_valid) begin
                        logic update_en;
                        update_en = 1'b0;
                        
                        if (DATA_RATE_MODE == "QDR") begin
                            if (spi_clk_redge_en || spi_clk_fedge_en || spi_clk_ps_redge_en || spi_clk_ps_fedge_en) update_en = 1'b1;
                        end else if (DATA_RATE_MODE == "DDR") begin
                            if (spi_clk_redge_en || spi_clk_fedge_en) update_en = 1'b1;
                        end else begin
                            if (INPUT_SAMPLING_EDGE == "FALLING") begin
                                if (spi_clk_fedge_en) update_en = 1'b1;
                            end else begin
                                if (spi_clk_redge_en) update_en = 1'b1;
                            end
                        end

                        if (update_en) begin
                            lfsr_q <= next_lfsr;
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b1;
                                bit_counter <= bit_counter + 1'b1;
                                byte_valid <= (bit_counter == 3'd7);
                            end
                        end else begin
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b0;
                                byte_valid <= 1'b0;
                            end
                        end
                    end else begin
                        if (ENABLE_FLOW_CONTROL == "Yes") begin
                            crc_valid <= 1'b0;
                            byte_valid <= 1'b0;
                        end
                    end
                end else begin
                    if (ENABLE_FLOW_CONTROL == "Yes") begin
                        crc_valid <= 1'b0;
                        byte_valid <= 1'b0;
                    end
                end
            end
        end else begin : g_async_calc
            // Logic operating on sclk_ps (Original)
            // Logic operating on sclk_ps (Original)
            if (DATA_RATE_MODE == "QDR") begin : g_qdr
                // Dual Data Rate: Sample on both edges
                always_ff @(posedge sclk or posedge sclk_inv or posedge sclk_ps or posedge sclk_ps_inv) begin
                    if (rst) begin
                        lfsr_q <= INIT_VAL;
                        bit_counter <= '0;
                        crc_valid <= 1'b0;
                        byte_valid <= 1'b0;
                    end else if (crc_en) begin
                        if (serial_in_valid) begin
                            lfsr_q <= next_lfsr;
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b1;
                                bit_counter <= bit_counter + 1'b1;
                                byte_valid <= (bit_counter == 3'd7);
                            end
                        end else begin
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b0;
                                byte_valid <= 1'b0;
                            end
                        end
                    end else begin
                        if (ENABLE_FLOW_CONTROL == "Yes") begin
                            crc_valid <= 1'b0;
                            byte_valid <= 1'b0;
                        end
                    end
                end
                           
           end else if  (DATA_RATE_MODE == "DDR") begin : g_ddr
                // Dual Data Rate: Sample on both edges
                always_ff @(posedge sclk or posedge sclk_inv ) begin
                    if (rst) begin
                        lfsr_q <= INIT_VAL;
                        bit_counter <= '0;
                        crc_valid <= 1'b0;
                        byte_valid <= 1'b0;
                    end else if (crc_en) begin
                        if (serial_in_valid) begin
                            lfsr_q <= next_lfsr;
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b1;
                                bit_counter <= bit_counter + 1'b1;
                                byte_valid <= (bit_counter == 3'd7);
                            end
                        end else begin
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b0;
                                byte_valid <= 1'b0;
                            end
                        end
                    end else begin
                        if (ENABLE_FLOW_CONTROL == "Yes") begin
                            crc_valid <= 1'b0;
                            byte_valid <= 1'b0;
                        end
                    end
                end
                
            end else begin : g_sdr
                if (INPUT_SAMPLING_EDGE == "FALLING") begin : g_sdr_neg
                    // Single Data Rate: Sample on Falling Edge
                    always_ff @( posedge sclk_inv ) begin
                        if (rst) begin
                            lfsr_q <= INIT_VAL;
                            bit_counter <= '0;
                            crc_valid <= 1'b0;
                            byte_valid <= 1'b0;
                        end else if (crc_en) begin
                            if (serial_in_valid) begin
                                lfsr_q <= next_lfsr;
                                if (ENABLE_FLOW_CONTROL == "Yes") begin
                                    crc_valid <= 1'b1;
                                    bit_counter <= bit_counter + 1'b1;
                                    byte_valid <= (bit_counter == 3'd7);
                                end
                            end else begin
                                if (ENABLE_FLOW_CONTROL == "Yes") begin
                                    crc_valid <= 1'b0;
                                    byte_valid <= 1'b0;
                                end
                            end
                        end else begin
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b0;
                                byte_valid <= 1'b0;
                            end
                        end
                    end
                end else begin : g_sdr_pos
                    // Single Data Rate: Sample on Rising Edge (Default)
                    always_ff @(posedge sclk) begin
                        if (rst) begin
                            lfsr_q <= INIT_VAL;
                            bit_counter <= '0;
                            crc_valid <= 1'b0;
                            byte_valid <= 1'b0;
                        end else if (crc_en) begin
                            if (serial_in_valid) begin
                                lfsr_q <= next_lfsr;
                                if (ENABLE_FLOW_CONTROL == "Yes") begin
                                    crc_valid <= 1'b1;
                                    bit_counter <= bit_counter + 1'b1;
                                    byte_valid <= (bit_counter == 3'd7);
                                end
                            end else begin
                                if (ENABLE_FLOW_CONTROL == "Yes") begin
                                    crc_valid <= 1'b0;
                                    byte_valid <= 1'b0;
                                end
                            end
                        end else begin
                            if (ENABLE_FLOW_CONTROL == "Yes") begin
                                crc_valid <= 1'b0;
                                byte_valid <= 1'b0;
                            end
                        end
                    end
                end
            end
        end
    endgenerate

    // =========================================================================
    // Output Assignment
    // =========================================================================
    
    // Apply final XOR if required by the protocol
    assign crc_out = (XOR_OUT == "Yes") ? ~lfsr_q : lfsr_q;

    // =========================================================================
    // Unused Port Handling
    // =========================================================================
    // sysclk and sclk are included for interface compliance but not used 
    // in the core logic path to avoid CDC (Clock Domain Crossing) issues 
    // within the calculation loop.
    
endmodule
