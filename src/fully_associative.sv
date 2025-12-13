//this implementation uses true LRU with counters for its replacement policy


module direct_mapped #(

    parameter int ADDRESS_WIDTH = 16,
    parameter int WORD_OFFSET_WIDTH = 2 //value cant be zero
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
localparam int NUM_LINES_WIDTH = 3;

//This cache will have 8 lines


initial begin
    if (TAG_WIDTH < 1) $fatal(1, "Address is too small for index width and word_offset_width");
    if (WORD_OFFSET_WIDTH < 1) $fatal(1, "Word_Offset_Width too small, why are you even using a cache lol");
end

//dirty bit array, valid bit array, tag array, word array
logic dirty_array [8]; //indicates if the lie has been modified and needs to be written to memory when evicted
logic valid_array [8]; //indicates if the line has valid data
logic[TAG_WIDTH-1:0] tag_array [8]; //holds each tag

localparam WORDS_PER_LINE = 2 ** WORD_OFFSET_WIDTH;
logic[31:0] word_array [8][WORDS_PER_LINE];

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
logic valid_out [8];
logic dirty_out [8];
logic[TAG_WIDTH-1:0] tag_out [8];
logic[31:0] data_out [8];

//delay address by one cycle too
logic [TAG_WIDTH-1:0] address_tag_r;
logic [WORD_OFFSET_WIDTH-1:0] word_offset_r;
logic [1:0] byte_offset_r;

//delay read/write
logic cache_rd_r, cache_rd_r2; 
logic cache_wr_r, cache_wr_r2;
logic[3:0] cache_byte_enable_r, cache_byte_enable_r2;
//delay writing data
logic[31:0] cache_data_wr_r, cache_data_wr_r2;


//fully associative stuff
//you need a comparator for each line 
logic[NUM_LINES_WIDTH-1:0] tag_matches;
logic cache_hit;

generate
    for(genvar i = 0; i < 8; i++) begin
        assign tag_matches[i] = valid_out[i] && (tag_out[i] == address_tag_r);
    end
endgenerate

assign cache_hit = | tag_matches;

//pipeline calculations
logic cache_hit_r;
logic[NUM_LINES_WIDTH-1:0] tag_matches_r;
logic[31:0] data_out_r [8];

logic[NUM_LINES_WIDTH-1:0] hit_line;

//priority encoder for determining which line hit
priority_encoder_parameterized #(.WIDTH(NUM_LINES_WIDTH)) which_tag (.in(tag_matches_r), .result(hit_line));

//LRU STUFF
//I will be doing a tree-based pseudo-lru. the tree is organized as follows:
//bit 0: root
//bits 1 and 2: connected to bit 0
//bits 3 and 4: connected to bit 1
//bits 5 and 6: connected to bit 2

//upon cache write, all nodes of the tree will have their bits updated (bit 0 means its pointing left and bit 1 means its pointing right)
//the 8 bits of the cache index go from 0->7

//upon updating the cache after a miss, you need to also update the plru tree
logic fill_enable;

//update tree based on cache writes
logic [6:0] plru_tree;

//victim, invalid index
logic [2:0] victim_index, invalid_index;

//victim index holds the spot in the cache that will be replaced
//invalid index holds the spot in the cache that will be replaced initially before all data becomes valid

logic any_invalids;
logic[7:0] invalids;

always_comb begin
    for (int i = 0; i < 8; i++) begin
        invalids[i] = ~valid_out[i];
    end
    any_invalids = | invalids;
end

always_comb begin
    if(any_invalids) begin
        victim_index = invalid_index;
    end else begin
        victim_index[2] = ~plru_tree[0];

        if(victim_index[2]) victim_index[1] = ~plru_tree[2];
        else victim_index[1] = ~plru_tree[1];

        case(victim_index[2:1])
            2'b00: victim_index[0] = ~plru_tree[3];
            2'b01: victim_index[0] = ~plru_tree[4];
            2'b10: victim_index[0] = ~plru_tree[5];
            2'b11: victim_index[0] = ~plru_tree[6];
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) plru_tree <= 0;
    else if(cache_hit_r || fill_enable) begin
        logic[2:0] new_index;
        new_index = cache_hit_r ? hit_line : victim_index;

        plru_tree[0] <= new_index[2];

        if(new_index[2]) plru_tree[2] <= new_index[1];
        else plru_tree[1] <= new_index[1];

        case (new_index[2:1]) 
            2'b00: plru_tree[3] <= new_index[0];
            2'b01: plru_tree[4] <= new_index[0];
            2'b10: plru_tree[5] <= new_index[0];
            2'b11: plru_tree[6] <= new_index[0];
        endcase
    end
end

//main finite state machine
typedef enum logic[2:0] {
    IDLE1,
    IDLE2,
    IDLE3,
    CHECK_INDEX,
    WRITEBACK,
    FETCH,
    UPDATE_CACHE
} state_t;

state_t state_r;

endmodule