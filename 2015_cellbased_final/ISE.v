`timescale 1ns/10ps
`define PX 16384
module ISE(clk, reset, image_in_index, pixel_in, busy, out_valid, color_index, image_out_index);
input           clk;
input           reset;
input   [4:0]   image_in_index;
input   [23:0]  pixel_in;
output          busy;
output          out_valid;
output  [1:0]   color_index;
output  [4:0]   image_out_index;

//=======================================================================

reg          busy;
reg          out_valid;
reg  [1:0]   color_index;
reg  [4:0]   image_out_index;

//=======================================================================

reg [1:0] c_cat;
reg [2:0] cs, ns;
reg [13:0] px_count;

reg [13:0] r_pixels, g_pixels, b_pixels;
reg [21:0] total_r_int, total_g_int, total_b_int;
reg [`R + 4:0] r_ranking [31:0]; // 5 + `R - 1 位元
reg [`R + 4:0] g_ranking [31:0]; // 5 + `R - 1 位元
reg [`R + 4:0] b_ranking [31:0]; // 5 + `R - 1 位元
reg [`R - 1:0] intensity;
reg [4:0] rank_i, image_index;

reg div_in_en;
reg [`A - 1:0] dividend;
reg [`B - 1:0] divisor;
wire [`R - 1:0] ratio;
wire div_out_en, div_busy;

reg renk_done;
reg [1:0] div_cs, div_ns;
reg [2:0] out_cs, out_ns;

//=======================================================================

wire [7:0] PX_R = pixel_in[23:16];
wire [7:0] PX_G = pixel_in[15:8];
wire [7:0] PX_B = pixel_in[7:0];

parameter IDLE = 3'd0,
          GET_P = 3'd1,
          CAL_C = 3'd2,
          DIV_INT = 3'd3,
          RANK = 3'd4,
          OUT = 3'd5,
          DONE = 3'd6;

parameter DIV_IDLE = 2'd0,
          DIV_IN = 2'd1,
          DIV_WAIT = 2'd2,
          DIV_DONE = 2'd3;

parameter CAT_R = 2'd0,
          CAT_G = 2'd1,
          CAT_B = 2'd2;

parameter OUT_IDLE = 3'd0,
          OUT_R = 3'd1,
          OUT_G = 3'd2,
          OUT_B = 3'd3,
          OUT_DONE = 3'd4;

//=======================================================================

DIV DIV(.clk(clk),
        .reset(reset),
        .in_en(div_in_en),
        .dividend(dividend),
        .divisor(divisor),
        .ratio(ratio),
        .out_en(div_out_en),
        .busy(div_busy));

//=======================================================================

//current state
always @(posedge clk or posedge reset) begin
    if(reset) cs <= IDLE;
    else cs <= ns;
end

//next state
always @(*) begin
    case (cs)
        IDLE: ns = GET_P;
        GET_P: begin
            if(px_count == (`PX - 1'd1)) ns = CAL_C;
            else ns = GET_P;
        end
        CAL_C: ns = DIV_INT;
        DIV_INT: begin
            if(div_cs == DIV_DONE) ns = RANK;
            else ns = DIV_INT;
        end
        RANK: begin
            if(renk_done == 1'b1) begin
                if(image_in_index <= 31) ns = GET_P;
                else ns = OUT;
            end else ns = RANK;
        end
        OUT: begin
            if(out_cs == OUT_DONE) ns = DONE;
            else ns = OUT;
        end
        DONE: ns = IDLE;
        default: ns = IDLE;
    endcase
end

//GET Pixels=============================================================

//r_pixels
always @(posedge clk or posedge reset) begin
    if(reset) r_pixels <= 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1)) begin
        r_pixels <= (PX_R >= PX_G && PX_R >= PX_B)
                        ? r_pixels + 1'd1
                        : r_pixels;
    end else if(cs == RANK) r_pixels <= 0;
end

//g_pixels
always @(posedge clk or posedge reset) begin
    if(reset) g_pixels <= 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1)) begin
        g_pixels <= (PX_G >= PX_B && PX_G > PX_R)
                        ? g_pixels + 1'd1
                        : g_pixels;
    end else if(cs == RANK) g_pixels <= 0;
end

//b_pixels
always @(posedge clk or posedge reset) begin
    if(reset) b_pixels <= 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1)) begin
        b_pixels <= (PX_B > PX_R && PX_B > PX_G)
                        ? b_pixels + 1'd1
                        : b_pixels;
    end else if(cs == RANK) b_pixels <= 0;
end

//total_r_int
always @(posedge clk or posedge reset) begin
    if(reset) total_r_int <= 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1))
        total_r_int <= (PX_R >= PX_G && PX_R >= PX_B)
                        ? total_r_int + PX_R
                        : total_r_int;
    else if(cs == RANK) total_r_int <= 0;
end

//total_g_int
always @(posedge clk or posedge reset) begin
    if(reset) total_g_int <= 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1))
        total_g_int <= (PX_G >= PX_B && PX_G > PX_R)
                        ? total_g_int + PX_G
                        : total_g_int;
    else if(cs == RANK) total_g_int <= 0;
end

//total_b_int
always @(posedge clk or posedge reset) begin
    if(reset) total_b_int <= 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1))
        total_b_int <= (PX_B > PX_R && PX_B > PX_G)
                        ? total_b_int + PX_B
                        : total_b_int;
     else if(cs == RANK) total_b_int <= 0;
end


//busy
always @(*) begin
    if(reset) busy = 0;
    else if(ns == GET_P && image_in_index < 31) busy = 0;
    else if(cs == GET_P && px_count < (`PX - 1'd1)) busy = 0;
    else busy = 1;
end

//px_count
always @(posedge clk or posedge reset) begin
    if(reset) px_count <= 0;
    else if(cs == GET_P && pixel_in >= 0) px_count <= px_count + 1;
    else px_count <= 0;
end

//Color Category=========================================================

//c_cat
always @(posedge clk or posedge reset) begin
    if(reset) c_cat <= 2'd3;
    else if(cs == CAL_C) begin
        if(r_pixels > g_pixels && r_pixels > b_pixels)
            c_cat <= 2'd0;
        else if(g_pixels > r_pixels && g_pixels > b_pixels)
            c_cat <= 2'd1;
        else if(b_pixels > r_pixels && b_pixels > g_pixels)
            c_cat <= 2'd2;
    end
end

//Calcualte Average Intensity============================================

//DIV current state
always @(posedge clk or posedge reset) begin
    if(reset) div_cs <= DIV_IDLE;
    else div_cs <= div_ns;
end

//DIV next state
always @(*) begin
    case (div_cs)
        DIV_IDLE: begin
            if(cs == DIV_INT) div_ns = DIV_IN;
            else div_ns = DIV_IDLE;
        end
        DIV_IN: div_ns = DIV_WAIT;
        DIV_WAIT: begin
            if(div_out_en) div_ns = DIV_DONE;
            else div_ns = DIV_WAIT;
        end
        DIV_DONE: div_ns = DIV_IDLE;
        default: div_ns = DIV_IDLE;
    endcase
end

// div_in_en ; dividend ; divisor ;
always @(*) begin
    if(cs == IDLE) begin
        div_in_en = 1'b0;
        dividend = 0;
        divisor = 0;
    end else if(cs == DIV_INT && !div_busy) begin
        case (div_cs)
            DIV_IN: begin
                case (c_cat)
                    2'd0: begin
                        div_in_en = 1'b1;
                        dividend = total_r_int;
                        divisor = r_pixels;
                    end
                    2'd1: begin
                        div_in_en = 1'b1;
                        dividend = total_g_int;
                        divisor = g_pixels;
                    end
                    2'd2: begin
                        div_in_en = 1'b1;
                        dividend = total_b_int;
                        divisor = b_pixels;
                    end
                    default: begin
                        div_in_en = 1'b0;
                        dividend = 0;
                        divisor = 0;
                    end
                endcase
            end
            default: begin
                div_in_en = 1'b0;
                dividend = 0;
                divisor = 0;
            end
        endcase
    end else begin
        div_in_en = 1'b0;
        dividend = 0;
        divisor = 0;
    end
end

//intensity
always @(posedge clk or posedge reset) begin
    if(reset) intensity <= 0;
    else begin
        if(cs == DIV_INT && div_out_en)
        intensity <= ratio;
    end
end

//Ranking================================================================

//image_index
always @(posedge clk or posedge reset) begin
    if(reset) image_index <= 0;
    else if(cs == GET_P && ns == GET_P) image_index <= image_in_index;
end

//r_ranking ; g_ranking ; b_ranking ; renk_done
integer i;
always @(posedge clk or posedge reset) begin
    if(reset) begin
        renk_done <= 1'b0;
        for(i = 0 ; i <= 31 ; i = i + 1'd1) begin
            r_ranking[i] <= 0;
        end
        for(i = 0 ; i <= 31 ; i = i + 1'd1) begin
            g_ranking[i] <= 0;
        end
        for(i = 0 ; i <= 31 ; i = i + 1'd1) begin
            b_ranking[i] <= 0;
        end
    end else if(cs == RANK) begin
        case (c_cat)
            2'd0: begin
                if(r_ranking[rank_i][`R - 1:0] == 0) begin
                    r_ranking[rank_i] <= {image_index, intensity};
                    renk_done <= 1'b1;
                end else if(intensity < r_ranking[rank_i][`R - 1:0]) begin
                    for(i = 0; i <= 30 - rank_i; i = i + 1'd1) begin
                        r_ranking[31 - i] <= r_ranking[30 - i];
                        if(i == 30 - rank_i) begin
                            r_ranking[rank_i] <= {image_index, intensity};
                            renk_done <= 1'b1;
                        end
                    end
                end
            end
            2'd1: begin
                if(g_ranking[rank_i][`R - 1:0] == 0) begin
                    g_ranking[rank_i] <= {image_index, intensity};
                    renk_done <= 1'b1;
                end else if(intensity < g_ranking[rank_i][`R - 1:0]) begin
                    for(i = 0; i <= 30 - rank_i; i = i + 1'd1) begin
                        g_ranking[31 - i] <= g_ranking[30 - i];
                        if(i == 30 - rank_i) begin
                            g_ranking[rank_i] <= {image_index, intensity};
                            renk_done <= 1'b1;
                        end
                    end
                end
            end
            2'd2: begin
                if(b_ranking[rank_i][`R - 1:0] == 0) begin
                    b_ranking[rank_i] <= {image_index, intensity};
                    renk_done <= 1'b1;
                end else if(intensity < b_ranking[rank_i][`R - 1:0]) begin
                    for(i = 0; i <= 30 - rank_i; i = i + 1'd1) begin
                        b_ranking[31 - i] <= b_ranking[30 - i];
                        if(i == 30 - rank_i) begin
                            b_ranking[rank_i] <= {image_index, intensity};
                            renk_done <= 1'b1;
                        end
                    end
                end
            end
        endcase
    end else renk_done <= 1'b0;
end

//Output=================================================================

//OUT current state
always @(posedge clk or posedge reset) begin
    if(reset) out_cs <= OUT_IDLE;
    else out_cs <= out_ns;
end

//OUT next state
always @(*) begin
    case (out_cs)
        OUT_IDLE: begin
            if(cs == OUT) begin
                if(r_ranking[0]) out_ns = OUT_R;
                else if(g_ranking[0]) out_ns = OUT_G;
                else if(b_ranking[0]) out_ns = OUT_B;
                else out_ns = OUT_DONE;
            end else out_ns = OUT_IDLE;
        end
        OUT_R: begin
            if(r_ranking[rank_i + 1'd1] == 0 || rank_i == 31) begin
                if(g_ranking[0]) out_ns = OUT_G;
                else if(b_ranking[0]) out_ns = OUT_B;
                else out_ns = OUT_DONE;
            end else out_ns = OUT_R;
        end
        OUT_G: begin
            if(g_ranking[rank_i + 1'd1] == 0 || rank_i == 31) begin
                if(b_ranking[0]) out_ns = OUT_B;
                else out_ns = OUT_DONE;
            end else out_ns = OUT_G;
        end
        OUT_B: begin
            if(b_ranking[rank_i + 1'd1] == 0 || rank_i == 31) out_ns = OUT_DONE;
            else out_ns = OUT_B;
        end
        OUT_DONE: out_ns = OUT_IDLE;
        default: out_ns = OUT_IDLE;
    endcase
end

// out_valid ; color_index ; image_out_index
always @(*) begin
    if(cs == IDLE) begin
        out_valid = 1'b0;
        color_index = 2'b11;
        image_out_index = 0;
    end else if(cs == OUT) begin
        case (out_cs)
            OUT_R: begin
                out_valid = 1'b1;
                color_index = 2'b00;
                image_out_index = r_ranking[rank_i][`R + 4:`R];
            end
            OUT_G: begin
                out_valid = 1'b1;
                color_index = 2'b01;
                image_out_index = g_ranking[rank_i][`R + 4:`R];
            end
            OUT_B: begin
                out_valid = 1'b1;
                color_index = 2'b10;
                image_out_index = b_ranking[rank_i][`R + 4:`R];
            end
            default: begin
                out_valid = 1'b0;
                color_index = 2'b11;
                image_out_index = 0;
            end
        endcase
    end else begin
        out_valid = 1'b0;
        color_index = 2'b11;
        image_out_index = 0;
    end
end

//Counter================================================================

//rank_i
always @(posedge clk or posedge reset) begin
    if(reset) rank_i <= 0;
    else if(cs == GET_P) rank_i <= 0;
    else if(cs == RANK) begin
        case (c_cat)
            2'd0: begin
                if(intensity > r_ranking[rank_i][`R - 1:0]
                    && r_ranking[rank_i][`R - 1:0] != 0)
                    rank_i <= rank_i + 1;
            end
            2'd1: begin
                if(intensity > g_ranking[rank_i][`R - 1:0]
                    && g_ranking[rank_i][`R - 1:0] != 0)
                rank_i <= rank_i + 1;
            end
            2'd2: begin
                if(intensity > b_ranking[rank_i][`R - 1:0]
                    && b_ranking[rank_i][`R - 1:0] != 0)
                rank_i <= rank_i + 1;
            end
        endcase
    end
    else if(cs == OUT) begin
        if(out_cs == OUT_IDLE &&
            (out_ns == OUT_R || out_ns == OUT_G || out_ns == OUT_B)) rank_i <= 0;
        else if(out_cs == OUT_R &&
            (out_ns == OUT_G || out_ns == OUT_B)) rank_i <= 0;
        else if(out_cs == OUT_G && out_ns == OUT_B) rank_i <= 0;
        else rank_i <= rank_i + 1;
    end
end
//=======================================================================

endmodule
