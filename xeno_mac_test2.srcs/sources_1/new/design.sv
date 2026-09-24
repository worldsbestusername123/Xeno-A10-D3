`timescale 1ns/1ps
//top module (where all uh, yk, that lmao)
module xeno_top #(
    parameter int NUM_MACS   = 384,
    parameter int BRAM_DEPTH = 512 
) (
    input  logic signed [63:0] data_in,
    input  logic               clk,
    input  logic               rst,
    input  logic               start,
    input  logic               enable,
    input  logic               load,
    input  logic               load_weight_select,
    input  logic [4:0]         load_bank_select,
    input  logic [8:0]         execution_start_row, 

    output logic signed [31:0] result,
    output logic               done,
    output logic               load_done
);
    logic [8:0] load_row_addr;

    logic signed [7:0] bram_out_a [0:NUM_MACS-1];
    logic signed [7:0] bram_out_b [0:191];

    logic signed [15:0] product [0:NUM_MACS-1];

    logic signed [31:0] stage0 [0:383];
    logic signed [31:0] stage1 [0:191];
    logic signed [31:0] stage2 [0:95];
    logic signed [31:0] stage3 [0:47];
    logic signed [31:0] stage4 [0:23];
    logic signed [31:0] stage5 [0:11];
    logic signed [31:0] stage6 [0:5];
    logic signed [31:0] stage7 [0:2];
    logic signed [31:0] stage8 [0:1];
    
    logic signed [31:0] sum_products; 

    typedef enum logic [2:0] {
        IDLE,
        FETCH_PHASE0_ADDR,  // Setup Row 0 Address
        FETCH_PHASE0_LATCH, // Wait 1 cycle for BRAM, then LATCH Lower 192 activations
        FETCH_PHASE1_ADDR,  // Setup Row 1 Address
        FETCH_PHASE1_LATCH, // Wait 1 cycle for BRAM, then LATCH Upper 192 activations & weights
        PIPELINING,  
        ACCUMULATE,  
        FINISH
    } state_t;

    state_t state;
    logic [3:0] pipeline_cnt; 
    logic [1:0] mult_valid_pipe;

    logic [63:0] abuffer_read_reg [0:23];
    logic [63:0] bbuffer_read_reg [0:23];

    logic [23:0] write_en_a;
    logic [23:0] write_en_b;
    
    logic [8:0]  bram_read_addr;

  //rn, reset sets it to 0, address is added by one each clock cycle, oh yeah if not load it also sets to zero

    always_ff @(posedge clk) begin
        if (rst) begin
            load_row_addr <= '0;
            load_done     <= 1'b0;
        end
      //if the loading for this bank no finish, and load is high then begin
        else if (load && !load_done) begin
          //if load is like, 511 it'll set load done to true.
          if (load_row_addr == 9'(BRAM_DEPTH - 1)) begin
                load_done <= 1'b1;
            end
            else begin
                load_row_addr <= load_row_addr + 1'b1;
            end
        end
        else if (!load) begin
            load_row_addr <= '0;
            load_done     <= 1'b0;
        end
    end
	//makes sure the selected bank is below 24 so it doesn't grab from nonexistent banks
  //weight select is like, if it's 0 it does activations
    always_comb begin
        write_en_a = 24'b0;
        write_en_b = 24'b0;
        if (load && !load_done && (load_bank_select < 5'd24)) begin
            if (load_weight_select == 1'b0) begin
                write_en_a[load_bank_select] = 1'b1;
            end else begin
                write_en_b[load_bank_select] = 1'b1;
            end
        end
    end
  //if in the fetching states, it grabs the exec start row (which row it starts from) and adds it to the read counter (if 0, target 0-191, if 1, target 192-383)
    // If we are setting up or waiting for the second chunk of data, read Row 1.
    // Otherwise, always safely default to Row 0.
    always_comb begin
        if (state == FETCH_PHASE1_ADDR || state == FETCH_PHASE0_LATCH) begin
            bram_read_addr = execution_start_row + 9'd1;
        end else begin
            bram_read_addr = execution_start_row;
        end
    end

	//just making the actual ram that will feed the multipliers, they're fed the data_in
    genvar i;
    generate
        for (i = 0; i < 24; i = i + 1) begin : gen_bram_banks
            logic [63:0] ram_activation [0:BRAM_DEPTH-1];
            logic [63:0] ram_weight     [0:BRAM_DEPTH-1];

            always_ff @(posedge clk) begin
                if (write_en_a[i]) begin
                    ram_activation[load_row_addr] <= data_in;
                end
            end

            always_ff @(posedge clk) begin
                if (write_en_b[i]) begin
                    ram_weight[load_row_addr] <= data_in;
                end
            end
			//a register, cuz we using memory, it's a one clock latency so we gotta store the old values, then use them.
            always_ff @(posedge clk) begin
                abuffer_read_reg[i] <= ram_activation[bram_read_addr];
                bbuffer_read_reg[i] <= ram_weight[execution_start_row];
            end
        end
    endgenerate
  //if pipelining then it's b01, so it just started receiveing inputs (multipliers), if it's both (b11) then it's in the tree adder
    always_ff @(posedge clk) begin
        if (rst) begin
            mult_valid_pipe <= 2'b00;
        end else begin
          mult_valid_pipe <= {mult_valid_pipe[0], (state == PIPELINING)};
        end
    end

    logic [63:0] temp_a_word;
    logic [63:0] temp_b_word;
	//the fsm, controls everything basically
    		always_ff @(posedge clk) begin
        	if (rst) begin
            state        <= IDLE;
            pipeline_cnt <= '0;
            result       <= 32'sd0;
            done         <= 1'b0;
            
            for (int k = 0; k < NUM_MACS; k++) bram_out_a[k] <= '0;
            for (int k = 0; k < 192; k++)      bram_out_b[k] <= '0;
        end
        else begin
            done <= 1'b0;
    // da fsm


            case (state)
                IDLE: begin
                    pipeline_cnt <= '0;
                    if (start) begin
                        result <= 32'sd0;
                        state  <= FETCH_PHASE0_ADDR; //fetch
                    end
                end

                FETCH_PHASE0_ADDR: begin
                  //bram has latency so it takes one cc (yes we abbreviate it now lmao)
                    state <= FETCH_PHASE0_LATCH;
                end

                FETCH_PHASE0_LATCH: begin
                    // we get the first 192 a
                    for (int bank = 0; bank < 24; bank = bank + 1) begin
                        temp_a_word = abuffer_read_reg[bank];
                        for (int byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                            bram_out_a[(bank * 8) + byte_idx] <= 
                                $signed(temp_a_word[(byte_idx * 8) +: 8]);
                        end
                    end
                    state <= FETCH_PHASE1_ADDR; //next row
                end

                FETCH_PHASE1_ADDR: begin
                    state <= FETCH_PHASE1_LATCH;
                end

                FETCH_PHASE1_LATCH: begin
                    //next 192 a
                    for (int bank = 0; bank < 24; bank = bank + 1) begin
                        temp_a_word = abuffer_read_reg[bank];
                        for (int byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                            bram_out_a[192 + (bank * 8) + byte_idx] <= 
                                $signed(temp_a_word[(byte_idx * 8) +: 8]);
                        end
                    end
                    //the 384 b
                    for (int bank = 0; bank < 24; bank = bank + 1) begin
                        temp_b_word = bbuffer_read_reg[bank];
                        for (int byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                            bram_out_b[(bank * 8) + byte_idx] <= 
                                $signed(temp_b_word[(byte_idx * 8) +: 8]);
                        end
                    end
                    state <= PIPELINING; //go pipeline
                end
                PIPELINING: begin
                    if (pipeline_cnt == 4'd13) begin
                        state <= ACCUMULATE;
                    end else begin
                        pipeline_cnt <= pipeline_cnt + 1'b1;
                    end
                end
                ACCUMULATE: begin
                    if (enable) begin
                        result <= result + sum_products;
                        state  <= FINISH;
                    end
                end
                FINISH: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    genvar mult;
    generate 
        for (mult = 0; mult < 192; mult = mult + 1) begin : gen_multipliers
            xeno_multiplier multiplier_instance (
                .clk      (clk),
                .rst      (rst),
                .a        (bram_out_a[2 * mult]),
                .a1       (bram_out_a[2 * mult + 1]),
                .b        (bram_out_b[mult]),
                .product0 (product[2 * mult]),
                .product1 (product[2 * mult + 1])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
      //it's a tree adder, pretty simple
        if (rst) begin
            for (int k = 0; k < 384; k++) stage0[k] <= '0;
            for (int k = 0; k < 192; k++) stage1[k] <= '0;
            for (int k = 0; k < 96;  k++) stage2[k] <= '0;
            for (int k = 0; k < 48;  k++) stage3[k] <= '0;
            for (int k = 0; k < 24;  k++) stage4[k] <= '0;
            for (int k = 0; k < 12;  k++) stage5[k] <= '0;
            for (int k = 0; k < 6;   k++) stage6[k] <= '0;
            for (int k = 0; k < 3;   k++) stage7[k] <= '0;
            for (int k = 0; k < 2;   k++) stage8[k] <= '0;
            sum_products <= '0;
        end 
        else begin
            if (mult_valid_pipe[1]) begin
                for (int k = 0; k < 384; k++) begin
                  stage0[k] <= 32'($signed(product[k]));
                end
            end else begin
                for (int k = 0; k < 384; k++) begin
                    stage0[k] <= '0;
                end
            end
            for (int k = 0; k < 192; k++) stage1[k] <= stage0[2*k] + stage0[2*k + 1];
            for (int k = 0; k < 96;  k++) stage2[k] <= stage1[2*k] + stage1[2*k + 1];
            for (int k = 0; k < 48;  k++) stage3[k] <= stage2[2*k] + stage2[2*k + 1];
            for (int k = 0; k < 24;  k++) stage4[k] <= stage3[2*k] + stage3[2*k + 1];
            for (int k = 0; k < 12;  k++) stage5[k] <= stage4[2*k] + stage4[2*k + 1];
            for (int k = 0; k < 6;   k++) stage6[k] <= stage5[2*k] + stage5[2*k + 1];
            for (int k = 0; k < 3;   k++) stage7[k] <= stage6[2*k] + stage6[2*k + 1];
            
            stage8[0] <= stage7[0] + stage7[1];
            stage8[1] <= stage7[2];
            
            sum_products <= stage8[0] + stage8[1];
        end
    end

endmodule

module xeno_multiplier (
  //new discovery: i can reuse weights, so basically two activations and one weight, the multiplying is now a*b and a1*b
    input  logic               clk,
    input  logic               rst,
    input  logic signed [7:0]  a,   // Activation 0
    input  logic signed [7:0]  a1,  // Activation 1
    input  logic signed [7:0]  b,   // Shared Weight

    output logic signed [15:0] product0,
    output logic signed [15:0] product1
);
    logic [8:0]          a0_offset;
    logic signed [26:0]  packed_a;
    logic signed [35:0]  dsp_mult_out;
    logic signed [7:0]   b_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            a0_offset    <= '0;
            packed_a     <= '0;
            b_reg        <= '0;
            dsp_mult_out <= '0;
            product0     <= '0;
            product1     <= '0;
        end else begin
            a0_offset    <= $unsigned($signed(a) + 9'sd128);
            packed_a     <= ($signed(a1) <<< 18) + $signed({1'b0, a0_offset});
          //you might be thinking (what the fuck is packed_a? can't we just multiply them together normally
		// it's cuz we're dsp packing, we want to fit in calcs in one DSP, how does this work?
          //packed_a contains 8 bits of a, 10 bits guard and 8 bits of a1, then we multiply with b_reg (which is just b), the <<< 7 means bit shift, since a could be negative, if it's negative the complementary sign leaks up the guard bits and then leaks into a1, bit shifting it 7 bits out allows you to multiply and get a non corrupted answer, then we get dsp_mult_out which is just packed_a*b_reg, we then bit slice to get the products we want then we're done
            b_reg        <= b;
            dsp_mult_out <= packed_a * b_reg;
            product0     <= dsp_mult_out[15:0] - ($signed(b_reg) <<< 7);
            product1     <= dsp_mult_out[33:18];
        end
    end
endmodule