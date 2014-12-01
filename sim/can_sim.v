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
        can_lo_in,
        can_lo_out,
        can_hi_in,
        can_hi_out, 
        led0, 
        led1,
        node_num
    );
    input can_clk, sys_clk, reset, can_lo_in, can_hi_in;
    input wire clk_src0, clk_src1;
    input wire[3:0] node_num;
    output reg can_lo_out = 1, can_hi_out = 0, led0, led1;
    output led2, led3;

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
    reg[1:0] state = 2'b00, next_state = 2'b00;
    reg toggle = 0;
    reg id_transmit_flag;
    reg lower_priority = 0;
    reg[31:0] bits_transmitted;
    reg[31:0] bits_received;
    reg[127:0] message = 0; 
    
    reg[127:0] received_msg;
    reg[127:0] scrubbed_msg_in = 0;
    reg receive_rst = 1;
    
    reg[10:0] message_id;
    reg[3:0] data_length = 4'b0001;
    reg[7:0] data[7:0];
    reg[14:0] CRC = 15'h0000;
    
    parameter EOF = 7'h7F;
    // Extended format versus standard format base length
     parameter msg_length_base = 44;  
    `ifdef EXTENDEDFORMAT
        parameter msg_length_base += 18; 
    `endif
    reg[7:0] msg_length = 0;
    integer i = 0;
    integer index = 0;
   
    reg[4:0] bit_stuff_check = 5'b00001;
    reg flush_bitStuffCheck = 0; 

    always@(state, toggle) begin
        case(state)
            IDLE: begin    // IDLE
                /*
                *   Generate message if want to transmit. If no message to send, listen to bus. Else transmit
                */
                bits_transmitted <= 0;
                bits_received <= 0;
                scrubbed_msg_in <= 0;
                receive_rst <= 1;
                can_hi_out <= 0;
                can_lo_out <= 1;
                message_id = (node_num[0]) ? 11'h7FF : 11'h7F8;
                message = {1'b0,{message_id},2'b00,{data_length}}; 
                msg_length = msg_length_base;
                // Test with random data transmission
                data[0] = 8'h89;
                for(i=0; i < data_length; i = i+1) begin
                    message = {message,{data[i]}};
                    msg_length = msg_length + 8;     
                end
                message = {message, {CRC},3'b101,EOF};
                
                $display("NODE: %d, (Message: %x (len: %d))",node_num, message, msg_length);                
                $display("NODE: %d, SM: %b", node_num, message);
                // For now always transmit
                next_state <= 1; 
            end

            SENDING: begin    // SENDING
                receive_rst <= 0;
                /* Check transmitted bit with bus
                 * If not equal, lower priority. Kick off bus
                 * Takes cycle to latch output bit, so check next cycle
                 */
                if( lower_priority ) begin
                     bits_transmitted = 32'h7FFFFFFE;
                end else begin
                    /* Dominant = Logic 0 = High voltage
                     * Recessive = Logic 1 = Low voltage
                     * Bit stuffing. Should not bit stuff during CRC and EoF transmission
                     */
                    if(bits_transmitted < (msg_length - 25)) begin
                        if( ((bit_stuff_check == 5'b0) && message[(msg_length-1)-bits_transmitted]) ||
                            ((bit_stuff_check == 5'h1F) && !message[(msg_length-1)-bits_transmitted])
                        ) begin
                            can_hi_out = !bit_stuff_check[0];
                            can_lo_out = !can_hi_out;
                            // Flush bit_stuff_check
                            flush_bitStuffCheck = 1;
                        end else begin
                            can_hi_out = !message[(msg_length-1) - bits_transmitted];    
                            can_lo_out = !can_hi_out;
                            flush_bitStuffCheck = 0;
                        end
                    end else begin
                        can_hi_out = !message[(msg_length-1) - bits_transmitted];    
                        can_lo_out = !can_hi_out;
                    end
                 
                    bit_stuff_check = {bit_stuff_check, can_hi_out};
                end
               
                if(flush_bitStuffCheck)
                    bit_stuff_check = 5'b00001;
                else
                    bits_transmitted = bits_transmitted + 1;
        
                // While sending id/start bit, set id_transmit flag hi    
                if(bits_transmitted < 13) 
                    id_transmit_flag <= 1;
                else
                    id_transmit_flag <= 0;

                if(bits_transmitted < msg_length) begin
                    next_state <= SENDING;
                end else begin 
                    if(bits_transmitted == 32'h7FFFFFFF) 
                        // lower priority, kicked off bus
                        next_state <= WAIT;
                    else
                        // this node was bus master and finished transmission. 
                        next_state <= PROCESS;
                end
            end

            WAIT: begin    // WAIT RX 
                can_hi_out <= 0;
                can_lo_out <= 1;
                // Check for end of frame
                if( (received_msg[6:0] != 7'h7F) || (bits_received < msg_length_base) ) begin
                    next_state <= WAIT;
                end else begin
                    next_state <= PROCESS;
                end
            end    

            PROCESS: begin    // PROCESS
                bit_stuff_check = 5'b00001;
                for(i=127; i>=0; i=i-1) begin
                    //$display("NODE: %d. i: %d, scrubbed msg in: %x, BSC: %b",node_num, i, scrubbed_msg_in,bit_stuff_check);
                    if(i<=25 || i > bits_received) begin
                        scrubbed_msg_in = {scrubbed_msg_in, received_msg[i]};
                    end else begin  
                        if( ((bit_stuff_check == 5'b00) ) ||
                            ((bit_stuff_check == 5'h1F) )
                        ) begin
                            flush_bitStuffCheck = 1;
                            scrubbed_msg_in = {1'b0, scrubbed_msg_in};
                        end else begin
                            scrubbed_msg_in = {scrubbed_msg_in, received_msg[i]};
                            flush_bitStuffCheck = 0;
                        end

                        if(flush_bitStuffCheck) 
                            bit_stuff_check = 5'b00001;
                        else
                            bit_stuff_check = {bit_stuff_check, received_msg[i]};
                    end
                end

                $display("NODE: %d, Received message: %x",node_num, scrubbed_msg_in);
                $display("NODE: %d, RM: %b", node_num, received_msg);
                $display("NODE: %d, RM: %b", node_num, scrubbed_msg_in);
                next_state <= 0;
            end
        endcase   
        led0 = state[1];
        led1 = state[0];
    end
 
    // Check to see if message id lower priority 
    // and fill receive buffer
    always@(negedge can_clk) begin
        if(can_hi_out != can_hi_in && id_transmit_flag) begin
            lower_priority <= 1; 
        end else begin
            lower_priority <= 0;
        end

        if(receive_rst) begin
            received_msg = 128'b0;
            bits_received = 0;
        end else begin
            received_msg = {received_msg, can_lo_in};
            bits_received = bits_received + 1;
        end
        $display("NODE: %d, State: %d, CANout: (%d, %d), CANin: (%d, %d), RM: %b (BR: %d)",
                    node_num, state, can_hi_out, can_lo_out, can_hi_in, can_lo_in, received_msg[61:0],bits_received);
    end
 
    always@(posedge can_clk) begin
        if (reset) 
            state <= 0;
        else
            state <= next_state;
        toggle <= ~toggle;
    end
endmodule


