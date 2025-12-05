//this design is a direct mapped byte addressable write-back and write-allocate cache

//write-back: update the memory when the data gets evicted
//write-allocate: fetch whole cache line when you want to write to a location

//commands from device only come after cache_ready is asserted
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

logic[31:0] line_buffer [WORDS_PER_LINE];
logic[WORD_OFFSET_WIDTH-1:0] line_count;
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
        cache_data_wr_r <= 0;
        cache_byte_enable_r <= 0;
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
        cache_data_wr_r <= cache_data_wr;
        cache_byte_enable_r <= cache_byte_enable;
    end
end


logic cache_hit;
assign cache_hit = valid_out && (tag_out == address_tag_r);

//main finite state machine
typedef enum logic[2:0] {
    IDLE,
    CHECK_INDEX,
    WRITEBACK,
    FETCH,
    UPDATE_CACHE
} state_t;

state_t state_r;

//state machine
always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        state_r <= IDLE;

        for(int i = 0; i < NUM_LINES; i++) begin
            dirty_array[i] <= 0;
            valid_array[i] <= 0;
        end
        line_count <= 0;

        //cache signals
        cache_ready <= 0;
        cache_data_out <= 0;

        //ram signals
        ram_address <= 0
        ram_rd <= 0;
        ram_wr <= 0;
        ram_data_wr <= 0;
    end else begin
        //default values
        cache_ready <= 0;
        case(state_r)
            IDLE: begin

                //cpu attempts to read
                if(cache_rd_r) begin
                    if(cache_hit) begin
                        cache_ready <= 1;
                        cache_data_out <= data_out;
                    end else begin
                        state_r <= CHECK_INDEX;
                    end
                //cpu attempts to write
                end else if(cache_wr_r) begin
                    if(cache_hit) begin
                        for (int i = 0; i < 4; i++) begin
                            if(cache_byte_enable_r[i]) word_array[index_r][word_offset_r][((i+1)*8)-1:8*i] <= cache_data_wr_r[((i+1)*8)-1:8*i];
                        end
                        dirty_array[index_r] <= 1;
                        cache_ready <= 1;
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
                end else begin
                    state_r <= FETCH;
                end
            end
            WRITEBACK: begin
                ram_wr <= 1;
                ram_address <= {tag_out, index_r, line_count, 2'b00};
                ram_data_wr <= word_array[index_r][line_count];

                if(ram_ready) begin
                    if(line_count == WORDS_PER_LINE -1) begin
                        ram_wr <= 0;
                        state_r <= FETCH;
                        line_count <= 0;
                    end else begin
                        line_count <= line_count + 1;
                    end
                end
            end
            FETCH: begin
                //fill line buffer with values from ram
                ram_rd <= 1;
            end
            UPDATE_CACHE: begin

            end
        endcase
    end
end
endmodule
