//this design is a direct mapped byte addressable write-back and write-allocate cache

//write-back: update the memory when the data gets evicted
//write-allocate: fetch whole cache line when you want to write to a location
module direct_mapped #(

    parameter int ADDRESS_WIDTH = 16,
    parameter int INDEX_WIDTH = 3,
    parameter int WORD_OFFSET_WIDTH = 2
) (
    input logic clk, rst,

    //interface with external ram
    input logic[7:0] data_in,
    output logic[ADDRESS_WIDTH-1:0] ram_address_read,
    output logic ram_rd, ram_wr,

    //interface with device
    input logic[ADDRESS_WIDTH-1:0] address_read,
    output logic[31:0] data_out,
    input logic cache_rd, cache_wr
);
localparam int TAG_WIDTH = ADDRESS_WIDTH - INDEX_WIDTH - WORD_OFFSET_WIDTH - 2; //byte addressable

initial begin
        if (TAG_WIDTH < 1) $fatal(1, "Address is too small for index with and word_offset_width");
    end

    
endmodule
