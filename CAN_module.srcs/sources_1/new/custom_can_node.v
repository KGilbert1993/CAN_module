`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2014 02:15:27 PM
// Design Name: 
// Module Name: custom_can_node
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module custom_can_node(
        can_clk,
        sys_clk,
        reset,
        clk_src0,
        clk_src1,
        can_lo_in,
        can_lo_out,
        can_hi_in,
        can_hi_out, 
        led0, 
        led1,
        led2,
        led3
    );
    input can_clk, sys_clk, reset, can_lo_in, can_hi_in;
    input wire clk_src0, clk_src1;
    output reg can_lo_out, can_hi_out, led0, led1;
    output led2, led3;

/*************************************************************************
*   CLK Source
**************************************************************************/  
    wire db_clk;
    wire clk_50kHz, clk_1Hz;
    wire clk;
    
    parameter SRC_RAW_BTN = 2'b00;
    parameter SRC_DB_BTN = 2'b01;
    parameter SRC_CLK_50kHz = 2'b10;
    parameter SRC_CLK_1Hz = 2'b11;
    
    //debounce db0(sys_clk, 0, can_clk, db_clk);
    clock_divider clk500(sys_clk, clk_50kHz,5000000);
    clock_divider clk1(sys_clk, clk_1Hz, 100000000);
    /* I'm so sorry... */
    assign clk = ((clk_src0) ? ((clk_src1) ? clk_1Hz : can_clk) : (clk_src1) ? clk_50kHz : can_clk);                                             
    
    assign led2 = clk;

/*************************************************************************
*   State machine constants
**************************************************************************/
    /* 4 states for CAN node:
    *   1. Idle  
    *   2. Sending
    *   3. Wait Rx
    *   4. Process
    */
    parameter IDLE = 2'b00;
    parameter SENDING = 2'b01;
    parameter WAIT = 2'b10;
    parameter PROCESS = 2'b11;
    
/*************************************************************************
*   CAN frame components
**************************************************************************/
    reg[1:0] state, next_state;
    reg toggle = 0;
    reg[31:0] bits_transmitted;
    reg[127:0] message; 
    
    reg[10:0] message_id = 11'h123;
    reg[3:0] data_length = 4'b0001;
    reg[7:0] data[7:0];
    reg[14:0] CRC;
    
    parameter EOF = 7'h7F;
    // Extended format versus standard format base length
     parameter msg_length_base = 44;  
    `ifdef EXTENDEDFORMAT
        parameter msg_length_base += 18; 
    `endif
    reg[7:0] msg_length = 0;
    integer i = 0;
    
    always@(state, toggle) begin
        case(state)
            IDLE: begin    // IDLE
                /*
                *   Generate message if want to transmit. If no message to send, listen to bus. Else transmit
                */
                bits_transmitted <= 0;
                message = {0,{message_id},2'b00,{data_length}}; 
                msg_length = msg_length_base;
                // Test with random data transmission
                data[0] = 8'h89;
                for(i=0; i < data_length; i = i+1) begin
                    message = {message,{data[i]}};
                    msg_length = msg_length + 8;     
                end
                message = {message, {CRC},3'b101,EOF};
                // For now always transmit
                next_state <= 1; 
            end
            SENDING: begin    // SENDING
                // Check transmitted bit with bus
                // If not equal, lower priority. Kick off bus
                // Takes cycle to latch output bit, so check next cycle
                //if( (can_hi_out != can_hi_in) || (can_lo_out != can_lo_in) ) begin
                if(0) begin
                     bits_transmitted = msg_length - 1;
                end else begin
                    // Dominant = Logic 0 = High voltage
                    // Recessive = Logic 1 = Low voltage
                    can_hi_out = !message[(msg_length-1) - bits_transmitted];    
                    can_lo_out = message[(msg_length-1) - bits_transmitted];
                end
                
                bits_transmitted = bits_transmitted + 1;
                if(bits_transmitted < msg_length) begin
                    next_state <= SENDING;
                end else begin
                    next_state <= WAIT;
                end 
            end
            WAIT: begin    // WAIT RX
                next_state <= 3;
            end
            PROCESS: begin    // PROCESS
                next_state <= 0;
            end
        endcase   
        led0 = state[1];
        led1 = state[0];
    end
    
    always@(posedge clk) begin
        if (reset) 
            state <= 0;
        else
            state <= next_state;
        toggle <= ~toggle;
    end
endmodule
