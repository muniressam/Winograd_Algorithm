module Winograd_TOP_Serial #(
    parameter width = 16,
    parameter rows = 224,
    parameter cols = 224
) (
    input clk,               
    input rst_n,
    input valid,                              // Start signal for new frame
    input signed [width-1:0] data_in,         // Serial input data
    input signed [width-1:0] kernel_in,       // Serial kernel input
    
    output logic signed [width-1:0] data_out, // Serial output data
    output logic data_out_valid,              // Valid signal for output
    output logic Convolution_done             // Frame processing complete
);

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        LOAD_KERNEL,
        LOAD_DATA,
        PROCESS,
        OUTPUT
    } state_t;
    
    state_t state, next_state;
    
    // Memory for storing input data and kernel
    logic signed [width-1:0] data_mem [0:rows-1][0:cols-1];
    logic signed [width-1:0] kernel_mem [0:2][0:2];
    
    // Counters for loading
    logic [15:0] kernel_cnt;  // 0 to 8 (9 kernel elements)
    logic [31:0] data_cnt;    // 0 to rows*cols-1
    logic [15:0] output_cnt;  // 0 to (rows/2)*(cols/2)-1
    
    // Addresses for kernel loading
    logic [1:0] kernel_row, kernel_col;
    
    // Addresses for data loading
    logic [15:0] data_row, data_col;
    
    // Addresses for output
    logic [15:0] out_row, out_col;
    
    // Internal signals for parallel processing
    logic signed [width-1:0] data_parallel [0:rows-1][0:cols-1];
    logic signed [width-1:0] kernel_parallel [0:2][0:2];
    logic signed [width-1:0] result_parallel [0:rows/2-1][0:cols/2-1];
    logic process_valid;
    logic process_done;
    
    // Address calculation
    assign kernel_row = kernel_cnt[2:1];
    assign kernel_col = kernel_cnt[0] ? kernel_cnt[1:0] - 2'd1 : kernel_cnt[1:0];
    assign data_row = data_cnt / cols;
    assign data_col = data_cnt % cols;
    assign out_row = output_cnt / (cols/2);
    assign out_col = output_cnt % (cols/2);
    
    // State machine - sequential
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // State machine - combinational
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (valid)
                    next_state = LOAD_KERNEL;
            end
            
            LOAD_KERNEL: begin
                if (kernel_cnt == 9)
                    next_state = LOAD_DATA;
            end
            
            LOAD_DATA: begin
                if (data_cnt == rows * cols)
                    next_state = PROCESS;
            end
            
            PROCESS: begin
                if (process_done)
                    next_state = OUTPUT;
            end
            
            OUTPUT: begin
                if (output_cnt == (rows/2) * (cols/2))
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Kernel loading
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kernel_cnt <= 0;
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    kernel_mem[i][j] <= 0;
        end else begin
            case (state)
                IDLE: begin
                    kernel_cnt <= 0;
                end
                
                LOAD_KERNEL: begin
                    if (kernel_cnt < 9) begin
                        kernel_mem[kernel_row][kernel_col] <= kernel_in;
                        kernel_cnt <= kernel_cnt + 1;
                    end
                end
            endcase
        end
    end
    
    // Data loading
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_cnt <= 0;
        end else begin
            case (state)
                LOAD_KERNEL: begin
                    data_cnt <= 0;
                end
                
                LOAD_DATA: begin
                    if (data_cnt < rows * cols) begin
                        data_mem[data_row][data_col] <= data_in;
                        data_cnt <= data_cnt + 1;
                    end
                end
            endcase
        end
    end
    
    // Trigger parallel processing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            process_valid <= 0;
        end else begin
            if (state == LOAD_DATA && next_state == PROCESS)
                process_valid <= 1;
            else
                process_valid <= 0;
        end
    end
    
    // Copy to parallel arrays for processing
    always_ff @(posedge clk) begin
        if (state == LOAD_DATA && data_cnt == rows * cols) begin
            data_parallel <= data_mem;
            kernel_parallel <= kernel_mem;
        end
    end
    
    // Instantiate original parallel processing module
    logic signed [width-1:0] data_out_even_even [0:rows/2-1][0:cols/2-1];
    logic signed [width-1:0] data_out_even_odd [0:rows/2-1][0:cols/2-1];
    logic signed [width-1:0] data_out_odd_even [0:rows/2-1][0:cols/2-1];
    logic signed [width-1:0] data_out_odd_odd [0:rows/2-1][0:cols/2-1];
    logic signed [width-1:0] kernel_even_even [0:2][0:2];
    logic signed [width-1:0] kernel_even_odd [0:2][0:2];
    logic signed [width-1:0] kernel_odd_even [0:2][0:2];
    logic signed [width-1:0] kernel_odd_odd [0:2][0:2];
    logic divide_done;
    
    Divide_image #(.width(width), .rows(rows), .cols(cols)) U_Divide_image (
        .clk(clk),
        .rst_n(rst_n),
        .valid(process_valid),
        .data_in(data_parallel),
        .kernel(kernel_parallel),
        .data_out_even_even(data_out_even_even),
        .data_out_even_odd(data_out_even_odd),
        .data_out_odd_even(data_out_odd_even),
        .data_out_odd_odd(data_out_odd_odd),
        .kernel_even_even(kernel_even_even),
        .kernel_even_odd(kernel_even_odd),
        .kernel_odd_even(kernel_odd_even),
        .kernel_odd_odd(kernel_odd_odd),
        .divide_done(divide_done)
    );
    
    Total_Y #(.width(width), .rows(rows), .cols(cols)) U_Total_Y (
        .clk(clk),
        .rst_n(rst_n),
        .divide_done(divide_done),
        .data_out_even_even(data_out_even_even),
        .data_out_even_odd(data_out_even_odd),
        .data_out_odd_even(data_out_odd_even),
        .data_out_odd_odd(data_out_odd_odd),
        .kernel_even_even(kernel_even_even),
        .kernel_even_odd(kernel_even_odd),
        .kernel_odd_even(kernel_odd_even),
        .kernel_odd_odd(kernel_odd_odd),
        .data_out(result_parallel),
        .Convolution_done(process_done)
    );
    
    // Serial output
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_cnt <= 0;
            data_out <= 0;
            data_out_valid <= 0;
            Convolution_done <= 0;
        end else begin
            case (state)
                PROCESS: begin
                    output_cnt <= 0;
                    data_out_valid <= 0;
                    Convolution_done <= 0;
                end
                
                OUTPUT: begin
                    if (output_cnt < (rows/2) * (cols/2)) begin
                        data_out <= result_parallel[out_row][out_col];
                        data_out_valid <= 1;
                        output_cnt <= output_cnt + 1;
                    end else begin
                        data_out_valid <= 0;
                        Convolution_done <= 1;
                    end
                end
                
                default: begin
                    data_out_valid <= 0;
                    Convolution_done <= 0;
                end
            endcase
        end
    end

endmodule

/*
module Winograd_TOP #(parameter width = 16 , parameter rows = 224 ,parameter cols = 224) (
    input clk,               
    input rst_n, 
    input valid, // valid signal to indicate that the data is ready to be processed            
    input signed [width - 1:0] data_in  [0: rows-1][0: cols-1], // 224x224x1 channel
    input signed [width - 1:0] kernel [0:2][0:2], // kernel width = 8 with 3x3x1 

    output logic signed [width - 1:0] data_out [0: rows/2 -1][0: cols/2 -1], // 112x112x1 channel
    output logic Convolution_done // signal to indicate that the processing is done
);

    logic signed [width - 1:0] data_out_even_even [0: rows/2 -1][0: cols/2 -1]; // 112x112x1 channel
    logic signed [width - 1:0] data_out_even_odd [0: rows/2 -1][0: cols/2 -1]; // 112x112x1 channel
    logic signed [width - 1:0] data_out_odd_even [0: rows/2 -1][0: cols/2 -1]; // 112x112x1 channel
    logic signed [width - 1:0] data_out_odd_odd [0: rows/2 -1][0: cols/2 -1]; // 112x112x1 channel
    logic signed [width - 1:0] kernel_even_even [0:2][0:2];
    logic signed [width - 1:0] kernel_even_odd [0:2][0:2];
    logic signed [width - 1:0] kernel_odd_even [0:2][0:2];
    logic signed [width - 1:0] kernel_odd_odd [0:2][0:2];
    logic divide_done; // signal to indicate that the processing is done
    
    Divide_image U_Divide_image(
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid), // valid signal to indicate that the data is ready to be processed            
        .data_in(data_in),
        .kernel(kernel), 
        .data_out_even_even(data_out_even_even),
        .data_out_even_odd(data_out_even_odd),
        .data_out_odd_even(data_out_odd_even),
        .data_out_odd_odd(data_out_odd_odd),
        .kernel_even_even(kernel_even_even),
        .kernel_even_odd(kernel_even_odd),
        .kernel_odd_even(kernel_odd_even),   
        .kernel_odd_odd(kernel_odd_odd),
        .divide_done(divide_done) // signal to indicate that the processing is done
    );

    Total_Y U_Total_Y(
        .clk(clk),
        .rst_n(rst_n),
        .divide_done(divide_done),           
        .data_out_even_even(data_out_even_even),
        .data_out_even_odd(data_out_even_odd),
        .data_out_odd_even(data_out_odd_even),
        .data_out_odd_odd(data_out_odd_odd),
        .kernel_even_even(kernel_even_even),
        .kernel_even_odd(kernel_even_odd),
        .kernel_odd_even(kernel_odd_even),   
        .kernel_odd_odd(kernel_odd_odd),
        .data_out(data_out), // 112x112x1 channel
        .Convolution_done(Convolution_done) // signal to indicate that the processing is done
    );
    
endmodule*/