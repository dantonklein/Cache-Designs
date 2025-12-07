module simulated_ram #(
    parameter int ADDRESS_WIDTH = 16
) (
    input logic clk, rst,

    input logic[31:0] ram_data_wr,
    input logic[ADDRESS_WIDTH-1:0] ram_address,
    input logic ram_rd, ram_wr,
    input logic [3:0] ram_byte_enable,
    output logic [31:0] ram_data_rd,
    output logic ram_ready
);
    localparam int ram_size = 2 ** (ADDRESS_WIDTH-2);

    logic[7:0] ram[ram_size][4];

    initial begin
        for(int i = 0; i < ram_size; i++) begin
            ram[i][0] = i[7:0];
            ram[i][1] = i[15:8];
            ram[i][2] = i[23:16];
            ram[i][3] = i[31:24];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            ram_data_rd <= 0;
            ram_ready <= 0;
        end else begin
            ram_ready <= 0;

            if(ram_rd) begin
                ram_ready <= 1;
                ram_data_rd[31:24] <= ram[ram_address[ADDRESS_WIDTH-1:2]][3];
                ram_data_rd[23:16] <= ram[ram_address[ADDRESS_WIDTH-1:2]][2];
                ram_data_rd[15:8] <= ram[ram_address[ADDRESS_WIDTH-1:2]][1];
                ram_data_rd[7:0] <= ram[ram_address[ADDRESS_WIDTH-1:2]][0];
            end else if(ram_wr) begin
                ram_ready <= 1;
                if(ram_byte_enable[0]) ram[ram_address[ADDRESS_WIDTH-1:2]][0] <= ram_data_wr[7:0];
                if(ram_byte_enable[1]) ram[ram_address[ADDRESS_WIDTH-1:2]][1] <= ram_data_wr[15:8];
                if(ram_byte_enable[2]) ram[ram_address[ADDRESS_WIDTH-1:2]][2] <= ram_data_wr[23:16];
                if(ram_byte_enable[3]) ram[ram_address[ADDRESS_WIDTH-1:2]][3] <= ram_data_wr[31:24];
            end
        end
    end

endmodule

module cache_tb;

    localparam int ADDRESS_WIDTH = 16;
    localparam int INDEX_WIDTH = 3;
    localparam int WORD_OFFSET_WIDTH = 2;

    logic clk, rst;

    //interface with external ram
    logic[31:0] ram_data_rd;
    logic ram_ready;
    logic[ADDRESS_WIDTH-1:0] ram_address;
    logic ram_rd, ram_wr;
    logic[31:0] ram_data_wr;
    logic[3:0] ram_byte_enable;

    //interface with device
    logic[31:0] cache_data_out;
    logic cache_ready;
    logic[ADDRESS_WIDTH-1:0] cache_address;
    logic cache_rd, cache_wr;
    logic[3:0] cache_byte_enable;
    logic[31:0] cache_data_wr;


    initial begin : generate_clock
        clk = 1'b0;
        forever #5 clk <= ~clk;
    end
    localparam int ram_size = 2 ** (ADDRESS_WIDTH - 2);
    logic[7:0] ram[ram_size][4]; //byte addressed
    initial begin : fill_ram
        for(int i = 0; i < 32; i++) begin
            for(int j = 0; j < 4; j++) begin
                ram[i][j] = i; //fill words with their word index
            end
        end
    end

    direct_mapped #(.ADDRESS_WIDTH(ADDRESS_WIDTH), .INDEX_WIDTH(INDEX_WIDTH), .WORD_OFFSET_WIDTH(WORD_OFFSET_WIDTH)) DUT (.*);

    initial begin
        //default values
        rst <= 1;
        ram_data_rd <= 0;
        ram_ready <= 0;

        cache_address <= 0;
        cache_rd <= 0;
        cache_wr <= 0;
        cache_byte_enable <= 0;
        cache_data_wr <= 0;
        @(posedge clk);
        rst <= 0;
        @(posedge clk);

        //test 1
        cache_address <= 16'd60;
        cache_byte_enable <= 4'hf;
        cache_rd <= 1;
    end
endmodule