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
    input logic[31:0] ram_data_rd, 
    input logic ram_ready,
    output logic[ADDRESS_WIDTH-1:0] ram_address,
    output logic ram_rd, ram_wr,
    output logic[3:0] ram_byte_enable,
    output logic[31:0] ram_data_wr,

    //interface with device
    
    output logic[31:0] cache_data_out,
    output logic cache_ready,
    input logic[ADDRESS_WIDTH-1:0] cache_address,
    input logic cache_rd, cache_wr,
    input logic[3:0] cache_byte_enable,
    input logic[31:0] cache_data_wr
);
localparam int TAG_WIDTH = ADDRESS_WIDTH - INDEX_WIDTH - WORD_OFFSET_WIDTH - 2; //byte addressable

initial begin
    if (TAG_WIDTH < 1) $fatal(1, "Address is too small for index width and word_offset_width");
end

localparam NUM_LINES = 2 ** INDEX_WIDTH;

//dirty bit array, valid bit array, tag array, word array
logic dirty_array [NUM_LINES]; //indicates if the lie has been modified and needs to be written to memory when evicted
logic valid_array [NUM_LINES]; //indicates if the line has valid data
logic[TAG_WIDTH-1:0] tag_array [NUM_LINES]; //holds each tag

localparam WORDS_PER_LINE = 2 ** WORD_OFFSET_WIDTH;
logic[31:0] word_array [NUM_LINES][WORDS_PER_LINE];

//address breakdown
logic [TAG_WIDTH-1:0] address_tag;
logic [INDEX_WIDTH-1:0] index;
logic [WORD_OFFSET_WIDTH-1:0] word_offset;
logic [1:0] byte_offset;
assign {address_tag, index, word_offset, byte_offset} = cache_address;


//delay by one cycle for tag comparison, valid check, dirty bit check, all that
logic valid_out, dirty_out;
logic[TAG_WIDTH-1:0] tag_out;
logic[31:0] data_out;

//delay address by one cycle too
logic [TAG_WIDTH-1:0] address_tag_r;
logic [INDEX_WIDTH-1:0] index_r;
logic [WORD_OFFSET_WIDTH-1:0] word_offset_r;
logic [1:0] byte_offset_r;

//delay read/write
logic cache_rd_r, cache_wr_r;
always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        valid_out <= 0;
        dirty_out <= 0;
        tag_out <= 0;
        data_out <= 0;

        address_tag_r <= 0;
        index_r <= 0;
        word_offset_r <= 0;
        byte_offset_r <= 0;

        cache_rd_r <= 0;
        cache_wr_r <= 0;
    end else begin
        valid_out <= valid_array[index];
        dirty_out <= dirty_array[index];
        tag_out <= tag_array[index];
        data_out <= word_array[index][word_offset];

        address_tag_r <= address_tag;
        index_r <= index;
        word_offset_r <= word_offset;
        byte_offset_r <= byte_offset;

        cache_rd_r <= cache_rd;
        cache_wr_r <= cache_wr;
    end
end


logic cache_hit;
assign cache_hit = valid_out && (tag_out == address_tag_r);

//main finite state machine
typedef enum logic[2:0] {
    IDLE,
    
} state_t;

endmodule
