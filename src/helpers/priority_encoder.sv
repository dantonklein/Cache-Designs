module priority_encoder_parameterized #(
    parameter int WIDTH = 8
) (
    input logic[WIDTH-1:0] in,
    //output logic valid,
    output logic [$clog2(WIDTH)-1:0] result
);
localparam int RESULT_WIDTH = $clog2(WIDTH);


initial begin
    if (WIDTH < 1) $fatal(1, "WIDTH too small.");
end

if(WIDTH == 1) begin
    //assign valid = in;
    assign result = 0;
end
else begin
    always_comb begin
        //valid = 1'b0;
        result = '0;
        for (int i = WIDTH-1; i >= 0; i--) begin
            if(in[i] == 1'b1) begin
                result = RESULT_WIDTH'(i);
                //valid = 1'b1;
                break;
            end
        end
    end
end
endmodule

module priority_encoder_tb;

    localparam int WIDTH = 8;

    logic [WIDTH-1:0] in;
    logic valid;
    logic [$clog2(WIDTH)-1:0] result;

    priority_encoder_parameterized #(.WIDTH(WIDTH)) DUT (.*);

    logic clk;

    initial begin : generate_clock
        clk = 1'b0;
        forever #5 clk <= ~clk;
    end

    initial begin
        $timeformat(-9, 0, " ns");
        for(int i = 0; i < 2 ** WIDTH; i++) begin
            in <= i;
            @(posedge clk);
        end

        disable generate_clock;
    end

endmodule