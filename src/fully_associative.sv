//this implementation uses true LRU with counters for its replacement policy


module direct_mapped #(

    parameter int ADDRESS_WIDTH = 16,
    parameter int WORD_OFFSET_WIDTH = 2, //value cant be zero
    parameter int NUM_LINES = 8
) (
    input logic clk, rst,

    //interface with external ram
    input logic[31:0] ram_data_rd, 
    input logic ram_data_valid,
    output logic[ADDRESS_WIDTH-1:0] ram_address,
    output logic ram_rd, ram_wr,
    output logic[31:0] ram_data_wr,

    //interface with device
    output logic[31:0] cache_data_out,
    output logic cache_ready,
    input logic[ADDRESS_WIDTH-1:0] cache_address,
    input logic cache_rd, cache_wr,
    input logic[3:0] cache_byte_enable,
    input logic[31:0] cache_data_wr
);
localparam int TAG_WIDTH = ADDRESS_WIDTH - WORD_OFFSET_WIDTH - 2; //byte addressable
localparam int NUM_LINES_WIDTH = $clog2(NUM_LINES);

initial begin
    if (TAG_WIDTH < 1) $fatal(1, "Address is too small for index width and word_offset_width");
    if (WORD_OFFSET_WIDTH < 1) $fatal(1, "Word_Offset_Width too small, why are you even using a cache lol");
end

//dirty bit array, valid bit array, tag array, word array
logic dirty_array [NUM_LINES]; //indicates if the lie has been modified and needs to be written to memory when evicted
logic valid_array [NUM_LINES]; //indicates if the line has valid data
logic[TAG_WIDTH-1:0] tag_array [NUM_LINES]; //holds each tag

localparam WORDS_PER_LINE = 2 ** WORD_OFFSET_WIDTH;
logic[31:0] word_array [NUM_LINES][WORDS_PER_LINE];

logic[31:0] line_buffer [WORDS_PER_LINE];
logic[WORD_OFFSET_WIDTH-1:0] line_count;

logic[WORD_OFFSET_WIDTH-1:0] line_width_zero, line_count_plus_one;
assign line_count_plus_one = line_count + 1;
assign line_width_zero = 0;

//address breakdown
logic [TAG_WIDTH-1:0] address_tag;
logic [WORD_OFFSET_WIDTH-1:0] word_offset;
logic [1:0] byte_offset;
assign {address_tag, word_offset, byte_offset} = cache_address;

//delay by one cycle for tag comparison, valid check, dirty bit check, for all lines
logic valid_out [NUM_LINES];
logic dirty_out [NUM_LINES];
logic[TAG_WIDTH-1:0] tag_out [NUM_LINES];
logic[31:0] data_out [NUM_LINES];

//delay address by one cycle too
logic [TAG_WIDTH-1:0] address_tag_r;
logic [WORD_OFFSET_WIDTH-1:0] word_offset_r;
logic [1:0] byte_offset_r;

//delay read/write
logic cache_rd_r, cache_wr_r;
logic[3:0] cache_byte_enable_r;

//fully associative stuff
//you need a comparator for each line 
logic[NUM_LINES_WIDTH-1:0] tag_matches;
logic cache_hit;

generate
    for(genvar i = 0; i < NUM_LINES; i++) begin
        assign tag_matches[i] = valid_out[i] && (tag_out[i] == address_tag_r);
    end
endgenerate

assign cache_hit = | tag_matches;

logic cache_hit_r;
logic[NUM_LINES_WIDTH-1:0] tag_matches_r;
logic[31:0] data_out_r [NUM_LINES];

logic[NUM_LINES_WIDTH-1:0] hit_line;

//priority encoder for determining which line hit (idk if this is synthesizable)
always_comb begin
    hit_line = 0;
    for (logic[NUM_LINES_WIDTH-1:0] i = NUM_LINES-1; i >= 0; i--) begin
        if(tag_matches_r[i]) hit_line = i;
    end
end

endmodule