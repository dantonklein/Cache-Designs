module simulated_ram #(
    parameter int ADDRESS_WIDTH = 16
) (
    input logic clk, rst,

    input logic[31:0] ram_data_wr,
    input logic[ADDRESS_WIDTH-1:0] ram_address,
    input logic ram_rd, ram_wr,
    output logic [31:0] ram_data_rd,
    output logic ram_data_valid
);
    localparam int ram_size = 2 ** (ADDRESS_WIDTH-2);

    logic[7:0] ram[ram_size][4];

    initial begin
        for(int i = 0; i < ram_size; i++) begin
            ram[i][0] = i[7:0];
            ram[i][1] = i[7:0];
            ram[i][2] = i[7:0];
            ram[i][3] = i[7:0];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            ram_data_rd <= 0;
            ram_data_valid <= 0;
        end else begin
            ram_data_valid <= 0;

            if(ram_rd) begin
                ram_data_valid <= 1;
                ram_data_rd[31:24] <= ram[ram_address[ADDRESS_WIDTH-1:2]][3];
                ram_data_rd[23:16] <= ram[ram_address[ADDRESS_WIDTH-1:2]][2];
                ram_data_rd[15:8] <= ram[ram_address[ADDRESS_WIDTH-1:2]][1];
                ram_data_rd[7:0] <= ram[ram_address[ADDRESS_WIDTH-1:2]][0];
            end else if(ram_wr) begin
                ram_data_valid <= 1;
                ram[ram_address[ADDRESS_WIDTH-1:2]][0] <= ram_data_wr[7:0];
                ram[ram_address[ADDRESS_WIDTH-1:2]][1] <= ram_data_wr[15:8];
                ram[ram_address[ADDRESS_WIDTH-1:2]][2] <= ram_data_wr[23:16];
                ram[ram_address[ADDRESS_WIDTH-1:2]][3] <= ram_data_wr[31:24];
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
    logic ram_data_valid;
    logic[ADDRESS_WIDTH-1:0] ram_address;
    logic ram_rd, ram_wr;
    logic[31:0] ram_data_wr;

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

    direct_mapped #(.ADDRESS_WIDTH(ADDRESS_WIDTH), .INDEX_WIDTH(INDEX_WIDTH), .WORD_OFFSET_WIDTH(WORD_OFFSET_WIDTH)) DUT (.*);
    simulated_ram #(.ADDRESS_WIDTH(ADDRESS_WIDTH)) DUT_RAM (.*);

    initial begin
        //default values
        rst <= 1;

        cache_address <= 0;
        cache_rd <= 0;
        cache_wr <= 0;
        cache_byte_enable <= 0;
        cache_data_wr <= 0;
        @(posedge clk);
        rst <= 0;
        @(posedge clk);

        //test 1: first read from memory
        cache_address <= 16'h0020;
        cache_byte_enable <= 4'b1111;
        cache_rd <= 1;
        @(posedge clk);
        cache_rd <= 0;
        @(posedge cache_ready);

        //test 2: first write to memory from different address
        cache_address <= 16'hD030;
        cache_wr <= 1;
        cache_data_wr <= 16'h1234;
        @(posedge clk);
        cache_wr <= 0;
        @(posedge cache_ready);

        //test 3: second read from meory
        cache_address <= 16'hA840;
        cache_rd <= 1;
        @(posedge clk);
        cache_rd <= 0;
        @(posedge cache_ready);

        //test 4: read hit 
        cache_address <= 16'h002C;
        cache_rd <= 1;
        @(posedge clk);
        //cache_rd <= 0;
        //@(posedge cache_ready);

        //test 5: read hit right after read hit(test pipeline)
        cache_address <= 16'hA844;
        cache_rd <= 1;
        @(posedge clk);
        cache_rd <= 0;
        @(posedge clk);
        @(posedge clk);

        //test 6: write hit to address from test 2
        cache_address <= 16'hD034;
        cache_wr <= 1;
        cache_data_wr <= 16'h5678;
        @(posedge clk);
        cache_wr <= 0;
        @(posedge cache_ready);
        @(posedge clk);


        //test 7: write from same line but different address from test 6
        cache_address <= 16'h3D30;
        cache_byte_enable <= 4'b0001;
        cache_wr <= 1;
        cache_data_wr <= 16'h0008;
        @(posedge clk);
        cache_wr <= 0;
        @(posedge cache_ready);
        @(posedge clk);

        //test 8: read from same line but different address from test 7 to test dirty data being saved and replaced
        cache_address <= 16'h5630;
        cache_rd <= 1;
        @(posedge clk);
        cache_rd <= 0;
        @(posedge cache_ready);
        @(posedge clk);

        //test 9: do nothing and see if cache stays in idle state
        repeat(5) @(posedge clk);

        disable generate_clock;
    end
endmodule