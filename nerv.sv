module nerv #(
	parameter [31:0] RESET_ADDR = 32'h 0000_0000
) (
	input clock,
	input reset,
	input stall,
	output trap,

`ifdef NERV_RVFI
	output reg        rvfi_valid,
	output reg [63:0] rvfi_order,
	output reg [31:0] rvfi_insn,
	output reg        rvfi_trap,
	output reg        rvfi_halt,
	output reg        rvfi_intr,
	output reg [ 1:0] rvfi_mode,
	output reg [ 1:0] rvfi_ixl,
	output reg [ 4:0] rvfi_rs1_addr,
	output reg [ 4:0] rvfi_rs2_addr,
	output reg [31:0] rvfi_rs1_rdata,
	output reg [31:0] rvfi_rs2_rdata,
	output reg [ 4:0] rvfi_rd_addr,
	output reg [31:0] rvfi_rd_wdata,
	output reg [31:0] rvfi_pc_rdata,
	output reg [31:0] rvfi_pc_wdata,
	output reg [31:0] rvfi_mem_addr,
	output reg [ 3:0] rvfi_mem_rmask,
	output reg [ 3:0] rvfi_mem_wmask,
	output reg [31:0] rvfi_mem_rdata,
	output reg [31:0] rvfi_mem_wdata,
`endif

	output [31:0] imem_addr,
	input  [31:0] imem_data,

	output        dmem_valid,
	output [31:0] dmem_addr,
	output [ 3:0] dmem_wstrb,
	output [31:0] dmem_wdata,
	input  [31:0] dmem_rdata
);
	reg mem_wr_enable;
	reg [31:0] mem_wr_addr;
	reg [31:0] mem_wr_data;
	reg [3:0] mem_wr_strb;

	reg mem_rd_enable;
	reg [31:0] mem_rd_addr;
	reg [4:0] mem_rd_reg;
	reg [4:0] mem_rd_func;

	reg mem_rd_enable_q;
	reg [4:0] mem_rd_reg_q;
	reg [4:0] mem_rd_func_q;

	always @(posedge clock) begin
		if (!stall) begin
			mem_rd_enable_q <= mem_rd_enable;
			mem_rd_reg_q <= mem_rd_reg;
			mem_rd_func_q <= mem_rd_func;
		end
		if (reset) begin
			mem_rd_enable_q <= 0;
		end
	end

	assign dmem_valid = mem_wr_enable || mem_rd_enable;
	assign dmem_addr = mem_wr_enable ? mem_wr_addr : mem_rd_enable ? mem_rd_addr : 32'h x;
	assign dmem_wstrb = mem_wr_enable ? mem_wr_strb : 4'h 0;
	assign dmem_wdata = mem_wr_enable ? mem_wr_data : 32'h x;

	reg [31:0] regfile [0:31];
	wire [31:0] insn;
	reg [31:0] npc;
	reg [31:0] pc;

	reg [31:0] imem_addr_q;

	always @(posedge clock) begin
		imem_addr_q <= imem_addr;
	end

	assign imem_addr = (stall || mem_rd_enable_q) ? imem_addr_q : npc;
	assign insn = imem_data;

	wire [31:0] rs1_value = !insn_rs1 ? 0 : regfile[insn_rs1];
	wire [31:0] rs2_value = !insn_rs2 ? 0 : regfile[insn_rs2];

	wire [6:0] insn_funct7;
	wire [4:0] insn_rs2;
	wire [4:0] insn_rs1;
	wire [2:0] insn_funct3;
	wire [4:0] insn_rd;
	wire [6:0] insn_opcode;

	assign {insn_funct7, insn_rs2, insn_rs1, insn_funct3, insn_rd, insn_opcode} = insn;

	wire [11:0] imm_i;
	assign imm_i = insn[31:20];

	wire [11:0] imm_s;
	assign imm_s[11:5] = insn_funct7, imm_s[4:0] = insn_rd;

	wire [12:0] imm_b;
	assign {imm_b[12], imm_b[10:5]} = insn_funct7, {imm_b[4:1], imm_b[11]} = insn_rd, imm_b[0] = 1'b0;

	wire [20:0] imm_j;
	assign {imm_j[20], imm_j[10:1], imm_j[11], imm_j[19:12], imm_j[0]} = {insn[31:12], 1'b0};

	wire [31:0] imm_i_sext = $signed(imm_i);
	wire [31:0] imm_s_sext = $signed(imm_s);
	wire [31:0] imm_b_sext = $signed(imm_b);
	wire [31:0] imm_j_sext = $signed(imm_j);

	localparam OPCODE_LOAD       = 7'b 00_000_11;
	localparam OPCODE_STORE      = 7'b 01_000_11;
	localparam OPCODE_MADD       = 7'b 10_000_11;
	localparam OPCODE_BRANCH     = 7'b 11_000_11;

	localparam OPCODE_LOAD_FP    = 7'b 00_001_11;
	localparam OPCODE_STORE_FP   = 7'b 01_001_11;
	localparam OPCODE_MSUB       = 7'b 10_001_11;
	localparam OPCODE_JALR       = 7'b 11_001_11;

	localparam OPCODE_CUSTOM_0   = 7'b 00_010_11;
	localparam OPCODE_CUSTOM_1   = 7'b 01_010_11;
	localparam OPCODE_NMSUB      = 7'b 10_010_11;
	localparam OPCODE_RESERVED_0 = 7'b 11_010_11;

	localparam OPCODE_MISC_MEM   = 7'b 00_011_11;
	localparam OPCODE_AMO        = 7'b 01_011_11;
	localparam OPCODE_NMADD      = 7'b 10_011_11;
	localparam OPCODE_JAL        = 7'b 11_011_11;

	localparam OPCODE_OP_IMM     = 7'b 00_100_11;
	localparam OPCODE_OP         = 7'b 01_100_11;
	localparam OPCODE_OP_FP      = 7'b 10_100_11;
	localparam OPCODE_SYSTEM     = 7'b 11_100_11;

	localparam OPCODE_AUIPC      = 7'b 00_101_11;
	localparam OPCODE_LUI        = 7'b 01_101_11;
	localparam OPCODE_RESERVED_1 = 7'b 10_101_11;
	localparam OPCODE_RESERVED_2 = 7'b 11_101_11;

	localparam OPCODE_OP_IMM_32  = 7'b 00_110_11;
	localparam OPCODE_OP_32      = 7'b 01_110_11;
	localparam OPCODE_CUSTOM_2   = 7'b 10_110_11;
	localparam OPCODE_CUSTOM_3   = 7'b 11_110_11;

	reg next_wr;
	reg [31:0] next_rd;
	reg illinsn;

	reg trapped;
	assign trap = trapped;

	always @(posedge clock) begin
	end

	always @* begin
		npc = pc + 4;
		next_wr = 0;
		next_rd = 0;
		illinsn = 0;

		mem_wr_enable = 0;
		mem_wr_addr = 'hx;
		mem_wr_data = 'hx;
		mem_wr_strb = 'hx;

		mem_rd_enable = 0;
		mem_rd_addr = 'hx;
		mem_rd_reg = 'hx;
		mem_rd_func = 'hx;

		case (insn_opcode)
			OPCODE_LUI: begin
				next_wr = 1;
				next_rd = insn[31:12] << 12;
			end
			OPCODE_AUIPC: begin
				next_wr = 1;
				next_rd = (insn[31:12] << 12) + pc;
			end
			OPCODE_JAL: begin
				next_wr = 1;
				next_rd = npc;
				npc = pc + imm_j_sext;
				if (npc & 32'b 11) begin
					illinsn = 1;
					npc = npc & ~32'b 11;
				end
			end
			OPCODE_JALR: begin
				case (insn_funct3)
					3'b 000 /* JALR */: begin
						next_wr = 1;
						next_rd = npc;
						npc = (rs1_value + imm_i_sext) & ~32'b 1;
					end
					default: illinsn = 1;
				endcase
				if (npc & 32'b 11) begin
					illinsn = 1;
					npc = npc & ~32'b 11;
				end
			end
			OPCODE_BRANCH: begin
				case (insn_funct3)
					3'b 000 /* BEQ  */: begin if (rs1_value == rs2_value) npc = pc + imm_b_sext; end
					3'b 001 /* BNE  */: begin if (rs1_value != rs2_value) npc = pc + imm_b_sext; end
					3'b 100 /* BLT  */: begin if ($signed(rs1_value) < $signed(rs2_value)) npc = pc + imm_b_sext; end
					3'b 101 /* BGE  */: begin if ($signed(rs1_value) >= $signed(rs2_value)) npc = pc + imm_b_sext; end
					3'b 110 /* BLTU */: begin if (rs1_value < rs2_value) npc = pc + imm_b_sext; end
					3'b 111 /* BGEU */: begin if (rs1_value >= rs2_value) npc = pc + imm_b_sext; end
					default: illinsn = 1;
				endcase
				if (npc & 32'b 11) begin
					illinsn = 1;
					npc = npc & ~32'b 11;
				end
			end
			OPCODE_LOAD: begin
				case (insn_funct3)
					3'b 000 /* LB  */,
					3'b 001 /* LH  */,
					3'b 010 /* LW  */,
					3'b 100 /* LBU */,
					3'b 101 /* LHU */: begin
						mem_rd_enable = 1;
						mem_rd_addr = rs1_value + imm_i_sext;
						mem_rd_reg = insn_rd;
						mem_rd_func = {mem_rd_addr[1:0], insn_funct3};
						mem_rd_addr = {mem_rd_addr[31:2], 2'b 00};
					end
					default: illinsn = 1;
				endcase
			end
			OPCODE_STORE: begin
				case (insn_funct3)
					3'b 000 /* SB */,
					3'b 001 /* SH */,
					3'b 010 /* SW */: begin
						mem_wr_enable = 1;
						mem_wr_addr = rs1_value + imm_s_sext;
						mem_wr_data = rs2_value;
						mem_wr_strb = 4'b 1111;
						case (insn_funct3)
							3'b 000 /* SB  */: begin mem_wr_strb = 4'b 0001; end
							3'b 001 /* SH  */: begin mem_wr_strb = 4'b 0011; end
							3'b 010 /* SW  */: begin mem_wr_strb = 4'b 1111; end
						endcase
						mem_wr_data = mem_wr_data << (8*mem_wr_addr[1:0]);
						mem_wr_strb = mem_wr_strb << mem_wr_addr[1:0];
						mem_wr_addr = {mem_wr_addr[31:2], 2'b 00};
					end
					default: illinsn = 1;
				endcase
			end
			OPCODE_OP_IMM: begin
				casez ({insn_funct7, insn_funct3})
					10'b zzzzzzz_000 /* ADDI  */: begin next_wr = 1; next_rd = rs1_value + imm_i_sext; end
					10'b zzzzzzz_010 /* SLTI  */: begin next_wr = 1; next_rd = $signed(rs1_value) < $signed(imm_i_sext); end
					10'b zzzzzzz_011 /* SLTIU */: begin next_wr = 1; next_rd = rs1_value < imm_i_sext; end
					10'b zzzzzzz_100 /* XORI  */: begin next_wr = 1; next_rd = rs1_value ^ imm_i_sext; end
					10'b zzzzzzz_110 /* ORI   */: begin next_wr = 1; next_rd = rs1_value | imm_i_sext; end
					10'b zzzzzzz_111 /* ANDI  */: begin next_wr = 1; next_rd = rs1_value & imm_i_sext; end
					10'b 0000000_001 /* SLLI  */: begin next_wr = 1; next_rd = rs1_value << insn[24:20]; end
					10'b 0000000_101 /* SRLI  */: begin next_wr = 1; next_rd = rs1_value >> insn[24:20]; end
					10'b 0100000_101 /* SRAI  */: begin next_wr = 1; next_rd = $signed(rs1_value) >>> insn[24:20]; end
					default: illinsn = 1;
				endcase
			end
			OPCODE_OP: begin
				case ({insn_funct7, insn_funct3})
					10'b 0000000_000 /* ADD  */: begin next_wr = 1; next_rd = rs1_value + rs2_value; end
					10'b 0100000_000 /* SUB  */: begin next_wr = 1; next_rd = rs1_value - rs2_value; end
					10'b 0000000_001 /* SLL  */: begin next_wr = 1; next_rd = rs1_value << rs2_value[4:0]; end
					10'b 0000000_010 /* SLT  */: begin next_wr = 1; next_rd = $signed(rs1_value) < $signed(rs2_value); end
					10'b 0000000_011 /* SLTU */: begin next_wr = 1; next_rd = rs1_value < rs2_value; end
					10'b 0000000_100 /* XOR  */: begin next_wr = 1; next_rd = rs1_value ^ rs2_value; end
					10'b 0000000_101 /* SRL  */: begin next_wr = 1; next_rd = rs1_value >> rs2_value[4:0]; end
					10'b 0100000_101 /* SRA  */: begin next_wr = 1; next_rd = $signed(rs1_value) >>> rs2_value[4:0]; end
					10'b 0000000_110 /* OR   */: begin next_wr = 1; next_rd = rs1_value | rs2_value; end
					10'b 0000000_111 /* AND  */: begin next_wr = 1; next_rd = rs1_value & rs2_value; end
					default: illinsn = 1;
				endcase
			end
			default: illinsn = 1;
		endcase

		if (reset) begin
			npc = RESET_ADDR;
			next_wr = 0;
			illinsn = 0;
		end
	end

	reg reset_q;
	reg [31:0] mem_rdata;
`ifdef NERV_RVFI
	reg rvfi_pre_valid;
	reg [ 4:0] rvfi_pre_rd_addr;
	reg [31:0] rvfi_pre_rd_wdata;
`endif

	always @* begin
		mem_rdata = dmem_rdata >> (8*mem_rd_func_q[4:3]);
		case (mem_rd_func_q[2:0])
			3'b 000 /* LB  */: begin mem_rdata = $signed(mem_rdata[7:0]); end
			3'b 001 /* LH  */: begin mem_rdata = $signed(mem_rdata[15:0]); end
			3'b 100 /* LBU */: begin mem_rdata = mem_rdata[7:0]; end
			3'b 101 /* LHU */: begin mem_rdata = mem_rdata[15:0]; end
		endcase
	end

	always @(posedge clock) begin
		reset_q <= reset;

		if (!trapped && !stall && !reset && !reset_q) begin
			if (illinsn)
				trapped <= 1;
			if (!mem_rd_enable_q)
				pc <= npc;
`ifdef NERV_RVFI
			if (mem_rd_enable_q) begin
				rvfi_pre_valid <= 0;
			end else begin
				rvfi_pre_valid <= 1;
				rvfi_order <= rvfi_order + 1;
				rvfi_insn <= insn;
				rvfi_trap <= illinsn;
				rvfi_halt <= illinsn;
				rvfi_intr <= 0;
				rvfi_mode <= 3;
				rvfi_ixl <= 1;
				rvfi_rs1_addr <= insn_rs1;
				rvfi_rs2_addr <= insn_rs2;
				rvfi_rs1_rdata <= rs1_value;
				rvfi_rs2_rdata <= rs2_value;
				rvfi_pre_rd_addr <= next_wr ? insn_rd : 0;
				rvfi_pre_rd_wdata <= next_wr && insn_rd ? next_rd : 0;
				rvfi_pc_rdata <= pc;
				rvfi_pc_wdata <= npc;
				rvfi_mem_addr <= dmem_addr;
				case ({mem_rd_enable, insn_funct3})
					4'b 1_000 /* LB  */: begin rvfi_mem_rmask <= 4'b 0001 << mem_rd_func[4:3]; end
					4'b 1_001 /* LH  */: begin rvfi_mem_rmask <= 4'b 0011 << mem_rd_func[4:3]; end
					4'b 1_010 /* LW  */: begin rvfi_mem_rmask <= 4'b 1111 << mem_rd_func[4:3]; end
					4'b 1_100 /* LBU */: begin rvfi_mem_rmask <= 4'b 0001 << mem_rd_func[4:3]; end
					4'b 1_101 /* LHU */: begin rvfi_mem_rmask <= 4'b 0011 << mem_rd_func[4:3]; end
					default: rvfi_mem_rmask <= 0;
				endcase
				rvfi_mem_wmask <= dmem_wstrb;
				rvfi_mem_wdata <= dmem_wdata;
			end
`endif
			if (mem_rd_enable_q || next_wr)
				regfile[mem_rd_enable_q ? mem_rd_reg_q : insn_rd] <= mem_rd_enable_q ? mem_rdata : next_rd;
		end

		if (reset || reset_q) begin
			pc <= RESET_ADDR - (reset ? 4 : 0);
			trapped <= 0;
`ifdef NERV_RVFI
			rvfi_pre_valid <= 0;
			rvfi_order <= 0;
`endif
		end
	end

`ifdef NERV_RVFI
	always @* begin
		if (mem_rd_enable_q) begin
			rvfi_rd_addr = mem_rd_reg_q;
			rvfi_rd_wdata = mem_rdata;
		end else begin
			rvfi_rd_addr = rvfi_pre_rd_addr;
			rvfi_rd_wdata = rvfi_pre_rd_wdata;
		end
		rvfi_valid = rvfi_pre_valid && !stall && !reset && !reset_q;
		rvfi_mem_rdata = dmem_rdata;
	end
`endif

`ifdef NERV_DBGREGS
	wire [31:0] dbg_reg_x0  = 0;
	wire [31:0] dbg_reg_x1  = regfile[1];
	wire [31:0] dbg_reg_x2  = regfile[2];
	wire [31:0] dbg_reg_x3  = regfile[3];
	wire [31:0] dbg_reg_x4  = regfile[4];
	wire [31:0] dbg_reg_x5  = regfile[5];
	wire [31:0] dbg_reg_x6  = regfile[6];
	wire [31:0] dbg_reg_x7  = regfile[7];
	wire [31:0] dbg_reg_x8  = regfile[8];
	wire [31:0] dbg_reg_x9  = regfile[9];
	wire [31:0] dbg_reg_x10 = regfile[10];
	wire [31:0] dbg_reg_x11 = regfile[11];
	wire [31:0] dbg_reg_x12 = regfile[12];
	wire [31:0] dbg_reg_x13 = regfile[13];
	wire [31:0] dbg_reg_x14 = regfile[14];
	wire [31:0] dbg_reg_x15 = regfile[15];
	wire [31:0] dbg_reg_x16 = regfile[16];
	wire [31:0] dbg_reg_x17 = regfile[17];
	wire [31:0] dbg_reg_x18 = regfile[18];
	wire [31:0] dbg_reg_x19 = regfile[19];
	wire [31:0] dbg_reg_x20 = regfile[20];
	wire [31:0] dbg_reg_x21 = regfile[21];
	wire [31:0] dbg_reg_x22 = regfile[22];
	wire [31:0] dbg_reg_x23 = regfile[23];
	wire [31:0] dbg_reg_x24 = regfile[24];
	wire [31:0] dbg_reg_x25 = regfile[25];
	wire [31:0] dbg_reg_x26 = regfile[26];
	wire [31:0] dbg_reg_x27 = regfile[27];
	wire [31:0] dbg_reg_x28 = regfile[28];
	wire [31:0] dbg_reg_x29 = regfile[29];
	wire [31:0] dbg_reg_x30 = regfile[30];
	wire [31:0] dbg_reg_x31 = regfile[31];
`endif
endmodule