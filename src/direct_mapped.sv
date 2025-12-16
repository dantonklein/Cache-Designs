//this design is a direct mapped byte addressable write-back and write-allocate cache

//write-back: update the memory when the data gets evicted
//write-allocate: fetch whole cache line when you want to write to a location

//commands from device only come after cache_done is asserted
module direct_mapped #(

    parameter int ADDRESS_WIDTH = 16,
    parameter int INDEX_WIDTH = 3,
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

initial begin
    if (TAG_WIDTH < 1) $fatal(1, "Address is too small for index width and word_offset_width");
    if (WORD_OFFSET_WIDTH < 1) $fatal(1, "Word_Offset_Width too small, why are you even using a cache lol");
end

localparam NUM_LINES = 2 ** INDEX_WIDTH;

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
logic[3:0] cache_byte_enable_r;
//delay writing data
logic[31:0] cache_data_wr_r;

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

logic cache_hit;
assign cache_hit = valid_out && (tag_out == address_tag_r);


//state machine
always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        state_r <= IDLE1;

        for(int i = 0; i < NUM_LINES; i++) begin
            dirty_array[i] <= 0;
            valid_array[i] <= 0;
            tag_array[i] <= 0;
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
        valid_out <= 0;
        dirty_out <= 0;
        tag_out <= 0;
        data_out <= 0;

        //address register
        address_tag_r <= 0;
        index_r <= 0;
        word_offset_r <= 0;
        byte_offset_r <= 0;

        //cache signals registered
        cache_rd_r <= 0;
        cache_wr_r <= 0;
        cache_byte_enable_r <= 0;
        cache_data_wr_r <= 0;
    end else begin
        //default values
        cache_done <= 0;
        case(state_r)
            IDLE1: begin
                if(cache_rd | cache_wr) begin
                    //registered sram outputs
                    valid_out <= valid_array[index];
                    dirty_out <= dirty_array[index];
                    tag_out <= tag_array[index];
                    data_out <= word_array[index][word_offset];

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
                        cache_data_out <= data_out;
                        if(cache_rd | cache_wr) begin
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
                            cache_data_wr_r <= cache_data_wr;
                            cache_byte_enable_r <= cache_byte_enable;
                        end else state_r <= IDLE1;
                    end else begin
                        state_r <= CHECK_INDEX;
                    end
                //cpu attempts to write
                end else if(cache_wr_r) begin
                    if(cache_hit) begin
                        if(cache_byte_enable_r[0]) word_array[index_r][word_offset_r][7:0] <= cache_data_wr_r[7:0];
                        if(cache_byte_enable_r[1]) word_array[index_r][word_offset_r][15:8] <= cache_data_wr_r[15:8];
                        if(cache_byte_enable_r[2]) word_array[index_r][word_offset_r][23:16] <= cache_data_wr_r[23:16];
                        if(cache_byte_enable_r[3]) word_array[index_r][word_offset_r][31:24] <= cache_data_wr_r[31:24];
                        dirty_array[index_r] <= 1;
                        cache_done <= 1;
                        if(cache_rd | cache_wr) begin
                            //registered sram outputs
                            valid_out <= valid_array[index];
                            dirty_out <= dirty_array[index];
                            tag_out <= tag_array[index];
                            data_out <= word_array[index][word_offset];

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
                
                if(valid_out && dirty_out) begin
                    state_r <= WRITEBACK;
                    ram_wr <= 1;
                    ram_address <= {tag_out, index_r, line_width_zero, 2'b00};
                    ram_data_wr <= word_array[index_r][line_width_zero];
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
                        ram_address <= {tag_out, index_r, line_count_plus_one, 2'b00};
                        ram_data_wr <= word_array[index_r][line_count_plus_one];
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
                word_array[index_r] <= line_buffer;
                tag_array[index_r] <= address_tag_r;
                valid_array[index_r] <= 1;
                dirty_array[index_r] <= 0;

                if(cache_rd_r) begin
                    cache_done <= 1;
                    cache_data_out <= line_buffer[word_offset_r];
                end else if(cache_wr_r) begin
                    if(cache_byte_enable_r[0]) word_array[index_r][word_offset_r][7:0] <= cache_data_wr_r[7:0];
                    if(cache_byte_enable_r[1]) word_array[index_r][word_offset_r][15:8] <= cache_data_wr_r[15:8];
                    if(cache_byte_enable_r[2]) word_array[index_r][word_offset_r][23:16] <= cache_data_wr_r[23:16];
                    if(cache_byte_enable_r[3]) word_array[index_r][word_offset_r][31:24] <= cache_data_wr_r[31:24];
                    dirty_array[index_r] <= 1;
                    cache_done <= 1;
                end
                //figure out logic for when new read/write requests come in
                if(cache_rd | cache_wr) begin
                    //registered sram outputs
                    valid_out <= valid_array[index];
                    dirty_out <= dirty_array[index];
                    tag_out <= tag_array[index];
                    data_out <= word_array[index][word_offset];

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
