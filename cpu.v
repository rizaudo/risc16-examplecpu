
// C like なちゃんとインクルード順が安定するように
`define CPU_V

// 何時もの、お馴染み
`default_nettype none

module cpu (
            input clk,
            input rst_n
            );
   parameter REGS_INIT_ZERO = 1'b1;

   // INSTRUCTIONS
   localparam ADD = 3'b000;     // RRR
   localparam ADDI = 3'b001;    // RRI
   localparam NAND = 3'b010;    // RRR
   localparam LUI = 3'b011;     // RI
   localparam SW = 3'b100;      // RRI
   localparam LW = 3'b101;      // RRI
   localparam BEQ = 3'b110;     // RRI
   localparam JALR = 3'b111;    // RRI

   // ちなみに仕様に無いがShifterは1クロックサイクルで終わらせたい場合バレルシフタ等を使う必要が有る。

   // 記憶媒体の0番地は例外発見のために使う事が多いので、1始まりでやっています。
   reg [15:0] pc = 1;
   wire [15:0] data;

   // プロセッサではクロックサイクルをカウントして、プロセッサ内タイマーが出来るようにしている。
   // 今回は読者がわかりやすいデバッグ出力の為だけに用意している。
   reg [31:0]  cycle_counter = 0;


   // REG0はZERO REGISTER, 8つのレジスタを持つ
   reg [15:0] register[1:7];

   // IF
   // 簡便の為、プレフェッチは無し。I$は事前に読み込まれるというシミュレーション前提の作り。
   reg [15:0] instruction_cache [0:65535];

   assign data = instruction_cache[pc];

   // ID
   wire [2:0]  opcode, regA_address,regB_address,regC_address;

   wire        op_add_b, op_addi_b, op_nand_b, op_lui_b, op_sw_b, op_lw_b, op_beq_b, op_jalr_b;

   wire signed [15:0] regA_data;
   wire signed [15:0] regB_data;
   wire signed [15:0] regC_data;

   wire [15:0]         imm_u;
   wire signed [15:0]  imm_s;

   assign opcode = data[15:13];
   assign regA_address = data[12:10];
   assign regB_address = data[9:7];
   assign regC_address = data[2:0];

   assign regA_data = regA_address == 0? 16'h0000: register[regA_address];
   assign regB_data = regB_address == 0? 16'h0000: register[regB_address];
   assign regC_data = regC_address == 0? 16'h0000: register[regC_address];

   assign imm_u = {6'b0 ,data[9:0]};
   assign imm_s = $signed({{8{data[6]}},data[6:0]});

   // 本当はあまり良くない比較。シミュレーション想定なのでこうしています。
   assign op_add_b = opcode === ADD;
   assign op_addi_b = opcode === ADDI;
   assign op_nand_b = opcode === NAND;
   assign op_lui_b = opcode === LUI;
   assign op_sw_b = opcode === SW;
   assign op_lw_b = opcode === LW;
   assign op_beq_b = opcode === BEQ;
   assign op_jalr_b = opcode === JALR;

   wire [7:0]          dbg_opcode_b ;
   assign dbg_opcode_b = {op_add_b, op_addi_b, op_nand_b, op_lui_b,
                          op_sw_b, op_lw_b, op_beq_b, op_jalr_b};

   // EX
   wire signed [15:0] result;
   wire signed [15:0] regc_or_immed;

   assign regc_or_immed = op_add_b? register[regC_data]:
                          op_addi_b? imm_s : 16'h0000;
   assign result = op_add_b | op_addi_b?  regB_data + regc_or_immed:
                   op_nand_b? ~(regB_data & regC_data):
                   op_lui_b? imm_u & 16'hffc0:
                   op_sw_b | op_lw_b? regB_data + imm_s:
                   op_beq_b?  pc + 1 + imm_s:
                   op_jalr_b? pc + 1:   // pc is jalr instruction address.
                   16'h0000;

   integer            i;


   // WB


   //MEM
   wire [15:0] addr;                   // To memory of memory_sim.v
   wire        rw;                     // To memory of memory_sim.v
   wire        valid;                  // To memory of memory_sim.v
   wire [15:0] wdata;                  // To memory of memory_sim.v

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [15:0] rdata;                  // From memory of memory_sim.v
   // End of automatics
   memory_sim memory(/*AUTOINST*/
                     // Outputs
                     .rdata             (rdata[15:0]),
                     // Inputs
                     .clk               (clk),
                     .valid             (valid),
                     .rw                (rw),
                     .addr              (addr[15:0]),
                     .wdata             (wdata[15:0]));

   assign valid = op_sw_b | op_lw_b;
   assign rw = op_sw_b? 1'b1: 1'b0;
   assign addr = result;
   assign wdata = regA_data;

   always @(posedge clk)
     begin
        if(~rst_n)
          begin
             // $monitor("imm_s:%d", imm_s);
             pc <= 16'h0000;
             cycle_counter <= 32'b0;
             // i$ init
             $readmemh("./i_cache.dat", instruction_cache);
		         if (REGS_INIT_ZERO) begin
			          for (i = 1; i < 8; i = i+1)begin
				           register[i] = 16'h0000;
                   $display("register: %d", register[i]);
                end
	           end
          end
        else
          begin
             //WB
             if(regA_address != 3'b000)begin
                if(!(op_sw_b|op_lw_b|op_jalr_b|op_beq_b))begin
                   register[regA_address] <= result;
                end else if(op_lw_b) begin
                   // lsの場合は組み合わせ回路で送られているのでここで考慮することはない。
                   register[regA_address] <= rdata;
                end
             end else if(regA_address == 3'b000 & op_jalr_b) begin
                $display("halted!");
                $finish;
             end
             // PC update;
             pc <= op_jalr_b? regB_data:
                   op_beq_b & (regB_data == regC_data)? result:
                   pc + 1;

             cycle_counter <= cycle_counter+1;

             // Debug section
             $display(" === ");
             $display("cycle: %d, PC: %d", cycle_counter, pc);
             $display("ADD:ADDI:NAND:LUI:SW:LW:BEQ:JALR\n%b", dbg_opcode_b);
             $display("register\n r0:%4d, r1:%4d, r3:%4d, r3:%4d \n r4:%4d, r5:%4d, r6:%4d, r7:%4d",
                      16'd0, register[16'd1], register[16'd2],register[16'd3],
                      register[16'd4], register[16'd5], register[16'd6], register[16'd7]);
             if(op_beq_b)begin
                $display("beq: %d == %d ?: %d",regB_data, regC_data, regB_data === regC_data);
                $display("branch to: %d", result);
             end
             // if(pc === 16'hxxxx| data === 16'hxxxx)
             //   $finish;

             // $display("register:\n\" %d %d %d %d\n %d %d %d %d",0,regiter)

          end
     end // always @ (posedge clk)


endmodule

// one-read, one-write memory
module memory_sim(
                  input         clk,valid, rw, // rw=0:read, re=1:write
                  input [15:0]  addr,
                  input [15:0]  wdata,
                  output [15:0] rdata
                  );
   parameter LEN = 65535;
   parameter ADDR_LEN = 16;
   parameter WORD = 16;

   reg [15:0]                   mem_bank [0:LEN];
   reg [15:0]                   data = 0;

   assign rdata = data;

   always @(posedge clk)begin
      // そのままでは操作の要求かどうかわからないため、valid信号が必要。
      if(rw == 1'b1 & valid)begin
         mem_bank[addr] <= wdata;
      end else if(rw == 1'b0 & valid) begin
         data <= mem_bank[addr];
      end
   end

   initial begin

      $readmemh("./mem.dat", mem_bank);
   end
endmodule // memory_sim

module top();
   reg rst_n = 0;
   reg clk = 0;

   parameter CLK_PERIOD = 10;

   cpu cpu_1(/*AUTOINST*/
             // Inputs
             .clk                       (clk),
             .rst_n                     (rst_n));

   initial begin
      rst_n <= 0;
      #10 rst_n <= 1;
      #1000 $finish;
   end

   always #(CLK_PERIOD/2) begin
        clk <= !clk;
   end

endmodule // top

`default_nettype wire
