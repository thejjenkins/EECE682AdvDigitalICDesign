`timescale 1ns / 1ps
// Shared ALU for the programmable RK4 datapath.
// All values are Q16.16 signed fixed-point.
//
// ALU operations (alu_op encoding):
//   3'b000 = ADD   (a + b)
//   3'b001 = SUB   (a - b)
//   3'b010 = MUL   Q16.16 multiply: (a * b) >>> 16
//   3'b011 = SHL   (a <<< 1)   — arithmetic shift left by 1
//   3'b100 = SHR   (a >>> 1)   — arithmetic shift right by 1
//   3'b101 = ABS   |a|
//   3'b110 = NEG   -a
//   3'b111 = PASS  a (pass-through)

module rk4_alu (
    input  wire signed [31:0] op_a,
    input  wire signed [31:0] op_b,
    input  wire [2:0]         alu_op,
    output reg  signed [31:0] result
);

wire signed [63:0] mul_full = op_a * op_b;

always @(*) begin
    case (alu_op)
        3'b000:  result = op_a + op_b;
        3'b001:  result = op_a - op_b;
        3'b010:  result = mul_full[47:16];
        3'b011:  result = op_a <<< 1;
        3'b100:  result = op_a >>> 1;
        3'b101:  result = (op_a[31]) ? -op_a : op_a;
        3'b110:  result = -op_a;
        3'b111:  result = op_a;
        default: result = 32'sd0;
    endcase
end

endmodule
