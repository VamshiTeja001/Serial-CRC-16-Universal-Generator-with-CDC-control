`timescale 1ns / 1ps

module serial_crc_ip_wrapper #(
    // Parameters matching the IP configuration
    parameter SYNC_TO_SYSTEM_CLOCK = "Yes",
    parameter DATA_RATE_MODE = "SDR",
    parameter INPUT_SAMPLING_EDGE = "RISING",
    parameter [15:0] POLYNOMIAL = 16'h1021,
    parameter [15:0] INIT_VAL = 16'hFFFF,
    parameter XOR_OUT = "No",
    parameter ENABLE_FLOW_CONTROL = "No"
) (
    // Ports
    input  wire        sysclk,
    input  wire        sclk,
    input  wire        sclk_ps,
    input  wire        rst,
    input  wire        serial_in,
    input  wire        serial_in_valid,
    input  wire        crc_en,
    output wire [15:0] crc_out,
    output wire        crc_valid,
    output wire        byte_valid
);

    // Instantiation of the SystemVerilog module
    serial_crc_ip #(
        .SYNC_TO_SYSTEM_CLOCK(SYNC_TO_SYSTEM_CLOCK),
        .DATA_RATE_MODE(DATA_RATE_MODE),
        .INPUT_SAMPLING_EDGE(INPUT_SAMPLING_EDGE),
        .POLYNOMIAL(POLYNOMIAL),
        .INIT_VAL(INIT_VAL),
        .XOR_OUT(XOR_OUT),
        .ENABLE_FLOW_CONTROL(ENABLE_FLOW_CONTROL)
    ) inst_serial_crc_ip (
        .sysclk(sysclk),
        .sclk(sclk),
        .sclk_ps(sclk_ps),
        .rst(rst),
        .serial_in(serial_in),
        .serial_in_valid(serial_in_valid),
        .crc_en(crc_en),
        .crc_out(crc_out),
        .crc_valid(crc_valid),
        .byte_valid(byte_valid)
    );

endmodule