`timescale 1ns/10ps
`define A 22 //dividend data width
`define B 14 //divisor data width
`define R 24 //ratio data width 12 + 12 (quotient + decimal)
`define N 15 //remainder data width 15
`define Q 12 //quotient data width 12
`define D 12 //decimal data width 12(4 is enough for this contest)
module DIV(clk, reset, in_en, dividend, divisor, ratio, out_en, busy);
input clk, reset, in_en;
input [`A - 1:0] dividend;
input [`B - 1:0] divisor;
output [`R - 1:0] ratio;
output out_en, busy;

//=================================================================================

reg [`R - 1:0] ratio;
reg out_en, busy;

//=================================================================================

reg [2:0] cs, ns;

reg [`A - 1:0] A_Data;
reg [`B - 1:0] B_Data;

reg [`Q - 1:0] quotient;
reg [`N - 1:0] remainder;
reg [`D - 1:0] decimal;

reg [`N - 1:0] itarator_r;
reg [4:0] bit_count;

//=================================================================================

parameter IDLE = 3'd0,
          GET_D = 3'd1,
          CAL_Q = 3'd2,
          CAL_R = 3'd3,
          CAL_D = 3'd4,
          DONE = 3'd5;

//=================================================================================

//current state
always @(posedge clk or posedge reset) begin
    if(reset) cs <= IDLE;
    else cs <= ns;
end

//next state
always @(*) begin
    case (cs)
        IDLE: ns = GET_D;
        GET_D:begin
            if(in_en) ns = CAL_Q;
            else ns = GET_D;
        end
        CAL_Q: ns = CAL_R;
        CAL_R: begin
            if(`D > 0) ns = CAL_D;
            else ns = DONE;
        end
        CAL_D: begin
            if(bit_count == `D) ns = DONE;
            else ns = CAL_D;
        end
        DONE: ns = IDLE;
        default: ns = IDLE;
    endcase
end

//A_Data
always @(posedge clk or posedge reset) begin
    if(reset) A_Data <= 0;
    else if(cs == GET_D && in_en && !busy) A_Data <= dividend;
end

//B_Data
always @(posedge clk or posedge reset) begin
    if(reset) B_Data <= 0;
    else if(cs == GET_D && in_en && !busy) B_Data <= divisor;
end

//quotient
always @(posedge clk or posedge reset) begin
    if(reset) quotient <= 0;
    else if(cs == CAL_Q) quotient <= A_Data / B_Data;
end

//remainder
always @(*) begin
    if(reset) remainder = 0;
    else if(cs == CAL_R) remainder = A_Data % B_Data;
end

//decimal
always @(posedge clk or posedge reset) begin
    if(reset || cs == IDLE) decimal <= 0;
    else if(cs == CAL_R) itarator_r <= remainder;
    else if(cs == CAL_D) begin
        if(itarator_r >= B_Data) begin
            decimal[`D - bit_count] <= 1'b1;
            itarator_r <= ((itarator_r - B_Data) << 1);
        end else begin
            decimal[`D - bit_count] <= 1'b0;
            itarator_r <= (itarator_r << 1);
        end
    end
end

//bit_count
always @(posedge clk or posedge reset) begin
    if(reset) bit_count <= 0;
    else if(cs == CAL_D) begin
        bit_count <= bit_count + 1;
    end else bit_count <= 0;
end

//ratio
always @(*) begin
    if(cs == IDLE) ratio = 0;
    else if(cs == DONE) begin
        if(`D > 0) ratio = {quotient, decimal};
        else ratio = quotient;
    end
    else ratio = 0;
end

//busy
always @(*) begin
    if(cs == IDLE || cs == GET_D) busy = 1'd0;
    else busy = 1'd1;
end

//out_en
always @(*) begin
    if(cs == IDLE) out_en = 1'd0;
    else if(cs == DONE) out_en = 1'd1;
    else out_en = 1'd0;
end

//=================================================================================

endmodule
