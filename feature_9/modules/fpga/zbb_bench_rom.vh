// Synthesizable ROM for Zbb Synthetic Benchmark
function [31:0] get_bench_instr;
    input [31:0] pc_addr;
    begin
        case (pc_addr[11:2])
            10'd0: get_bench_instr = 32'hffe00093;
            10'd1: get_bench_instr = 32'h00500113;
            10'd2: get_bench_instr = 32'h401171b3;
            10'd3: get_bench_instr = 32'h40116233;
            10'd4: get_bench_instr = 32'h401142b3;
            10'd5: get_bench_instr = 32'h0a20e333;
            10'd6: get_bench_instr = 32'h0a20f3b3;
            10'd7: get_bench_instr = 32'h0a20c433;
            10'd8: get_bench_instr = 32'h0a20d4b3;
            10'd9: get_bench_instr = 32'hfff00513;
            10'd10: get_bench_instr = 32'h080545b3;
            10'd11: get_bench_instr = 32'h60551613;
            10'd12: get_bench_instr = 32'h60451693;
            10'd13: get_bench_instr = 32'h0f000713;
            10'd14: get_bench_instr = 32'h60071793;
            10'd15: get_bench_instr = 32'h60171813;
            10'd16: get_bench_instr = 32'h60271893;
            10'd17: get_bench_instr = 32'h60271933;
            10'd18: get_bench_instr = 32'h602759b3;
            10'd19: get_bench_instr = 32'h60475a13;
            10'd20: get_bench_instr = 32'h69875a93;
            10'd21: get_bench_instr = 32'h28775b13;
            10'd22: get_bench_instr = 32'h00000013;
            10'd23: get_bench_instr = 32'h00000013;
            10'd24: get_bench_instr = 32'h00000013;
            default: get_bench_instr = 32'h0000_0013; // NOP
        endcase
    end
endfunction
