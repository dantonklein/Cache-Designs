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