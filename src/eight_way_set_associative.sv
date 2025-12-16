module eight_way_set_associative #(

    parameter int ADDRESS_WIDTH = 16,
    parameter int INDEX_WIDTH = 4,
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
    output logic cache_done,
    input logic[ADDRESS_WIDTH-1:0] cache_address,
    input logic cache_rd, cache_wr,
    input logic[3:0] cache_byte_enable,
    input logic[31:0] cache_data_wr
);
localparam int TAG_WIDTH = ADDRESS_WIDTH - INDEX_WIDTH - WORD_OFFSET_WIDTH - 2; //byte addressable

localparam NUM_SETS = 2 ** INDEX_WIDTH;

initial begin
    if (TAG_WIDTH < 1) $fatal(1, "Address is too small for index width and word_offset_width");
    if (WORD_OFFSET_WIDTH < 1) $fatal(1, "Word_Offset_Width too small");
end

//dirty bit array, valid bit array, tag array, word array
logic dirty_array [NUM_SETS][8]; //indicates if the lie has been modified and needs to be written to memory when evicted
logic valid_array [NUM_SETS][8]; //indicates if the line has valid data
logic[TAG_WIDTH-1:0] tag_array [NUM_SETS][8]; //holds each tag

localparam WORDS_PER_LINE = 2 ** WORD_OFFSET_WIDTH;
logic[31:0] word_array [NUM_SETS][8][WORDS_PER_LINE];

logic[31:0] line_buffer [WORDS_PER_LINE];
logic[WORD_OFFSET_WIDTH-1:0] line_count;

logic[WORD_OFFSET_WIDTH-1:0] line_width_zero, line_count_plus_one;
assign line_count_plus_one = line_count + 1;
assign line_width_zero = 0;

//address breakdown
logic [TAG_WIDTH-1:0] address_tag;
logic [INDEX_WIDTH-1:0] index;
logic [WORD_OFFSET_WIDTH-1:0] word_offset;
logic [1:0] byte_offset;
assign {address_tag, index, word_offset, byte_offset} = cache_address;

//delay by one cycle for tag comparison, valid check, dirty bit check, for all lines
logic valid_out [8];
logic dirty_out [8];
logic[TAG_WIDTH-1:0] tag_out [8];
logic[31:0] data_out [8];

//delay address by one cycle too
logic [TAG_WIDTH-1:0] address_tag_r;
logic [INDEX_WIDTH-1:0] index_r;
logic [WORD_OFFSET_WIDTH-1:0] word_offset_r;
logic [1:0] byte_offset_r;

//delay read/write
logic cache_rd_r; 
logic cache_wr_r;
logic[3:0] cache_byte_enable_r;
//delay writing data
logic[31:0] cache_data_wr_r;


//fully associative stuff
//you need a comparator for each line 
logic[7:0] tag_matches;
logic cache_hit;

generate
    for(genvar i = 0; i < 8; i++) begin
        assign tag_matches[i] = valid_out[i] && (tag_out[i] == address_tag_r);
    end
endgenerate

assign cache_hit = | tag_matches;

logic[2:0] hit_line;

//priority encoder for determining which line hit
priority_encoder_parameterized #(.WIDTH(8)) which_tag (.in(tag_matches), .result(hit_line));

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
logic [6:0] plru_tree[NUM_SETS];

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

priority_encoder_parameterized #(.WIDTH(8)) which_invalid (.in(invalids), .result(invalid_index));

always_comb begin
    if(any_invalids) begin
        victim_index = invalid_index;
    end else begin
        victim_index[2] = ~plru_tree[index_r][0];

        if(victim_index[2]) victim_index[1] = ~plru_tree[index_r][2];
        else victim_index[1] = ~plru_tree[index_r][1];

        case(victim_index[2:1])
            2'b00: victim_index[0] = ~plru_tree[index_r][3];
            2'b01: victim_index[0] = ~plru_tree[index_r][4];
            2'b10: victim_index[0] = ~plru_tree[index_r][5];
            2'b11: victim_index[0] = ~plru_tree[index_r][6];
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        for(int i = 0; i < 7; i++) begin
            plru_tree[index_r][i] <= 0;
        end
    end
    else if(cache_hit || fill_enable) begin
        logic[2:0] new_index;
        new_index = cache_hit ? hit_line : victim_index;

        plru_tree[index_r][0] <= new_index[2];

        if(new_index[2]) plru_tree[index_r][2] <= new_index[1];
        else plru_tree[index_r][1] <= new_index[1];

        case (new_index[2:1]) 
            2'b00: plru_tree[index_r][3] <= new_index[0];
            2'b01: plru_tree[index_r][4] <= new_index[0];
            2'b10: plru_tree[index_r][5] <= new_index[0];
            2'b11: plru_tree[index_r][6] <= new_index[0];
        endcase
    end
end

//main finite state machine
typedef enum logic[2:0] {
    IDLE1,
    IDLE2,
    CHECK_INDEX,
    WRITEBACK,
    FETCH,
    UPDATE_CACHE
} state_t;

state_t state_r;

//state machine
always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        state_r <= IDLE1;
        for(int i = 0; i < NUM_SETS; i++) begin
            for(int j = 0; j < 8; j++) begin
                dirty_array[i][j] <= 0;
                valid_array[i][j] <= 0;
                tag_array[i][j] <= 0;
            end
        end
        line_count <= 0;

        //cache signals
        cache_done <= 0;
        cache_data_out <= 0;

        //ram signals
        ram_address <= 0;
        ram_rd <= 0;
        ram_wr <= 0;
        ram_data_wr <= 0;

        //registered cache inputs
        for(int i = 0; i < 8; i++) begin
            valid_out[i] <= 0;
            dirty_out[i] <= 0;
            tag_out[i] <= 0;
            data_out[i] <= 0;
        end

        //address register
        address_tag_r <= 0;
        word_offset_r <= 0;
        byte_offset_r <= 0;
        index_r <= 0;

        //cache signals registered
        cache_rd_r <= 0;
        cache_wr_r <= 0;
        cache_byte_enable_r <= 0;
        cache_data_wr_r <= 0;
    end else begin
        //default values
        cache_done <= 0;
        fill_enable <= 0;
        case(state_r)
            IDLE1: begin
                if(cache_rd | cache_wr) begin
                    //registered sram outputs
                    valid_out <= valid_array[index];
                    dirty_out <= dirty_array[index];
                    tag_out <= tag_array[index];
                    for (int i = 0; i < 8; i++) begin
                        data_out[i] <= word_array[index][i][word_offset];
                    end
                    //cache address needs to be delayed by a cycle for timing
                    address_tag_r <= address_tag;
                    index_r <= index;
                    word_offset_r <= word_offset;
                    byte_offset_r <= byte_offset;

                    //same with the cache control signals
                    cache_rd_r <= cache_rd;
                    cache_wr_r <= cache_wr;
                    cache_data_wr_r <= cache_data_wr;
                    cache_byte_enable_r <= cache_byte_enable;
                    state_r <= IDLE2;
                end
            end
            IDLE2: begin
                //attempts to read
                if(cache_rd_r) begin
                    if(cache_hit) begin
                        cache_done <= 1;
                        cache_data_out <= data_out[hit_line];
                        if(cache_rd | cache_wr) begin
                            //registered sram outputs
                            valid_out <= valid_array[index];
                            dirty_out <= dirty_array[index];
                            tag_out <= tag_array[index];
                            for (int i = 0; i < 8; i++) begin
                                data_out[i] <= word_array[index][i][word_offset];
                            end
                            //cache address needs to be delayed by a cycle for timing
                            address_tag_r <= address_tag;
                            index_r <= index;
                            word_offset_r <= word_offset;
                            byte_offset_r <= byte_offset;

                            //same with the cache control signals
                            cache_rd_r <= cache_rd;
                            cache_wr_r <= cache_wr;
                            cache_data_wr_r <= cache_data_wr;
                            cache_byte_enable_r <= cache_byte_enable;
                        end else state_r <= IDLE1;
                    end else begin
                        state_r <= CHECK_INDEX;
                    end
                end else if(cache_wr_r) begin
                    if(cache_hit) begin
                        if(cache_byte_enable_r[0]) word_array[index_r][hit_line][word_offset_r][7:0] <= cache_data_wr_r[7:0];
                        if(cache_byte_enable_r[1]) word_array[index_r][hit_line][word_offset_r][15:8] <= cache_data_wr_r[15:8];
                        if(cache_byte_enable_r[2]) word_array[index_r][hit_line][word_offset_r][23:16] <= cache_data_wr_r[23:16];
                        if(cache_byte_enable_r[3]) word_array[index_r][hit_line][word_offset_r][31:24] <= cache_data_wr_r[31:24];
                        dirty_array[index_r][hit_line] <= 1;
                        cache_done <= 1;
                        if(cache_rd | cache_wr) begin
                            //registered sram outputs
                            valid_out <= valid_array[index];
                            dirty_out <= dirty_array[index];
                            tag_out <= tag_array[index];
                            for (int i = 0; i < 8; i++) begin
                                data_out[i] <= word_array[index][i][word_offset];
                            end
                            //cache address needs to be delayed by a cycle for timing
                            address_tag_r <= address_tag;
                            index_r <= index;
                            word_offset_r <= word_offset;
                            byte_offset_r <= byte_offset;

                            //same with the cache control signals
                            cache_rd_r <= cache_rd;
                            cache_wr_r <= cache_wr;
                            cache_data_wr_r <= cache_data_wr;
                            cache_byte_enable_r <= cache_byte_enable;
                        end else state_r <= IDLE1;
                    end else begin
                        state_r <= CHECK_INDEX;
                    end
                end
            end
            CHECK_INDEX: begin
                //in the event that the data is valid and it has data that needs to be written (dirty bit asserted) write that data
                line_count <= 0;
                
                if(valid_out[victim_index] && dirty_out[victim_index]) begin
                    state_r <= WRITEBACK;
                    ram_wr <= 1;
                    ram_address <= {tag_out[victim_index], index_r, line_width_zero, 2'b00};
                    ram_data_wr <= word_array[index_r][victim_index][line_width_zero];
                end else begin
                    state_r <= FETCH;
                    ram_rd <= 1;
                    ram_address <= {address_tag_r, index_r, line_width_zero, 2'b00};
                end
            end
            WRITEBACK: begin
                ram_wr <= ram_data_valid; //only write when ram is ready (ram is not pipelineable)
                if(ram_data_valid) begin
                    if(line_count == WORDS_PER_LINE-1) begin
                        ram_wr <= 0;
                        state_r <= FETCH;
                        line_count <= 0;
                        ram_rd <= 1;
                        ram_address <= {address_tag_r, index_r, line_width_zero, 2'b00};
                    end else begin
                        line_count <= line_count_plus_one;
                        ram_address <= {tag_out[victim_index], index_r, line_count_plus_one, 2'b00};
                        ram_data_wr <= word_array[index_r][victim_index][line_count_plus_one];
                    end
                end
            end
            FETCH: begin
                //fill line buffer with values from ram
                ram_rd <= ram_data_valid; //only read when ram is ready (ram is not pipelineable)

                if(ram_data_valid) begin
                    line_buffer[line_count] <= ram_data_rd;
                    if(line_count == WORDS_PER_LINE-1) begin
                        ram_rd <= 0;
                        state_r <= UPDATE_CACHE;
                    end
                    line_count <= line_count_plus_one;
                    ram_address <= {address_tag_r, index_r, line_count_plus_one, 2'b00};
                end
            end
            UPDATE_CACHE: begin
                fill_enable <= 1;
                word_array[index_r][victim_index] <= line_buffer;
                tag_array[index_r][victim_index] <= address_tag_r;
                valid_array[index_r][victim_index] <= 1;
                dirty_array[index_r][victim_index] <= 0;

                if(cache_rd_r) begin
                    cache_done <= 1;
                    cache_data_out <= line_buffer[word_offset_r];
                end else if(cache_wr_r) begin
                    if(cache_byte_enable_r[0]) word_array[index_r][victim_index][word_offset_r][7:0] <= cache_data_wr_r[7:0];
                    if(cache_byte_enable_r[1]) word_array[index_r][victim_index][word_offset_r][15:8] <= cache_data_wr_r[15:8];
                    if(cache_byte_enable_r[2]) word_array[index_r][victim_index][word_offset_r][23:16] <= cache_data_wr_r[23:16];
                    if(cache_byte_enable_r[3]) word_array[index_r][victim_index][word_offset_r][31:24] <= cache_data_wr_r[31:24];
                    dirty_array[index_r][victim_index] <= 1;
                    cache_done <= 1;
                end

                if(cache_rd | cache_wr) begin
                    //registered sram outputs
                    valid_out <= valid_array[index];
                    dirty_out <= dirty_array[index];
                    tag_out <= tag_array[index];
                    for (int i = 0; i < 8; i++) begin
                        data_out[i] <= word_array[index][i][word_offset];
                    end
                    //cache address needs to be delayed by a cycle for timing
                    address_tag_r <= address_tag;
                    index_r <= index;
                    word_offset_r <= word_offset;
                    byte_offset_r <= byte_offset;

                    //same with the cache control signals
                    cache_rd_r <= cache_rd;
                    cache_wr_r <= cache_wr;
                    cache_data_wr_r <= cache_data_wr;
                    cache_byte_enable_r <= cache_byte_enable;
                    state_r <= IDLE2;
                end else state_r <= IDLE1;
            end
        endcase
    end
end
endmodule