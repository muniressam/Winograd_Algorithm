`timescale 1ns/1ps

module tb_Winograd_TOP_Serial;

    // Parameters
    parameter width = 16;
    parameter rows = 224;
    parameter cols = 224;
    parameter OUTPUT_ROWS = rows/2;
    parameter OUTPUT_COLS = cols/2;
    
    // Clock period
    parameter CLK_PERIOD = 10;
    
    // Testbench signals
    logic clk;
    logic rst_n;
    logic valid;
    logic signed [width-1:0] data_in;
    logic signed [width-1:0] kernel_in;
    logic signed [width-1:0] data_out;
    logic data_out_valid;
    logic Convolution_done;
    
    // Memory to store file data
    logic signed [width-1:0] input_data [0:rows-1][0:cols-1];
    logic signed [width-1:0] kernel_data [0:2][0:2];
    logic signed [width-1:0] expected_output [0:OUTPUT_ROWS-1][0:OUTPUT_COLS-1];
    logic signed [width-1:0] received_output [0:OUTPUT_ROWS-1][0:OUTPUT_COLS-1];
    
    // File paths
    string input_file = "input_data.txt";
    string kernel_file = "kernel_data.txt";
    string expected_file = "expected_output.txt";
    string output_file = "received_output.txt";
    
    // Counters
    integer errors;
    integer output_count;
    
    // Instantiate DUT
    Winograd_TOP_Serial #(
        .width(width),
        .rows(rows),
        .cols(cols)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .data_in(data_in),
        .kernel_in(kernel_in),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .Convolution_done(Convolution_done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Task to read input data from file
    task read_input_data();
        integer file, status, i, j;
        integer value;
        begin
            file = $fopen(input_file, "r");
            if (file == 0) begin
                $display("ERROR: Cannot open input file: %s", input_file);
                $finish;
            end
            
            $display("Reading input data from %s...", input_file);
            for (i = 0; i < rows; i++) begin
                for (j = 0; j < cols; j++) begin
                    status = $fscanf(file, "%d", value);
                    if (status != 1) begin
                        $display("ERROR: Failed to read input data at [%0d][%0d]", i, j);
                        $fclose(file);
                        $finish;
                    end
                    input_data[i][j] = value[width-1:0];
                end
            end
            $fclose(file);
            $display("Successfully read %0d x %0d input data values", rows, cols);
        end
    endtask
    
    // Task to read kernel data from file
    task read_kernel_data();
        integer file, status, i, j;
        integer value;
        begin
            file = $fopen(kernel_file, "r");
            if (file == 0) begin
                $display("ERROR: Cannot open kernel file: %s", kernel_file);
                $finish;
            end
            
            $display("Reading kernel data from %s...", kernel_file);
            for (i = 0; i < 3; i++) begin
                for (j = 0; j < 3; j++) begin
                    status = $fscanf(file, "%d", value);
                    if (status != 1) begin
                        $display("ERROR: Failed to read kernel data at [%0d][%0d]", i, j);
                        $fclose(file);
                        $finish;
                    end
                    kernel_data[i][j] = value[width-1:0];
                end
            end
            $fclose(file);
            $display("Successfully read 3 x 3 kernel values");
        end
    endtask
    
    // Task to read expected output from file
    task read_expected_output();
        integer file, status, i, j;
        integer value;
        begin
            file = $fopen(expected_file, "r");
            if (file == 0) begin
                $display("ERROR: Cannot open expected output file: %s", expected_file);
                $finish;
            end
            
            $display("Reading expected output from %s...", expected_file);
            for (i = 0; i < OUTPUT_ROWS; i++) begin
                for (j = 0; j < OUTPUT_COLS; j++) begin
                    status = $fscanf(file, "%d", value);
                    if (status != 1) begin
                        $display("ERROR: Failed to read expected output at [%0d][%0d]", i, j);
                        $fclose(file);
                        $finish;
                    end
                    expected_output[i][j] = value[width-1:0];
                end
            end
            $fclose(file);
            $display("Successfully read %0d x %0d expected output values", OUTPUT_ROWS, OUTPUT_COLS);
        end
    endtask
    
    // Task to send kernel data serially
    task send_kernel();
        integer i, j;
        begin
            $display("Sending kernel data serially...");
            for (i = 0; i < 3; i++) begin
                for (j = 0; j < 3; j++) begin
                    @(posedge clk);
                    kernel_in = kernel_data[i][j];
                end
            end
            $display("Kernel data sent (9 values)");
        end
    endtask
    
    // Task to send input data serially
    task send_input_data();
        integer i, j;
        begin
            $display("Sending input data serially...");
            for (i = 0; i < rows; i++) begin
                for (j = 0; j < cols; j++) begin
                    @(posedge clk);
                    data_in = input_data[i][j];
                end
                if ((i+1) % 50 == 0) begin
                    $display("  Sent %0d/%0d rows", i+1, rows);
                end
            end
            $display("Input data sent (%0d values)", rows*cols);
        end
    endtask
    
    // Task to collect output data
    task collect_output();
        integer out_row, out_col;
        begin
            $display("Collecting output data...");
            output_count = 0;
            out_row = 0;
            out_col = 0;
            
            while (!Convolution_done) begin
                @(posedge clk);
                if (data_out_valid) begin
                    received_output[out_row][out_col] = data_out;
                    output_count++;
                    out_col++;
                    if (out_col == OUTPUT_COLS) begin
                        out_col = 0;
                        out_row++;
                        if ((out_row) % 25 == 0) begin
                            $display("  Received %0d/%0d rows", out_row, OUTPUT_ROWS);
                        end
                    end
                end
            end
            $display("Output collection complete (%0d values)", output_count);
        end
    endtask
    
    // Task to compare outputs
    task compare_outputs();
        integer i, j;
        integer max_error;
        integer current_error;
        begin
            $display("\nComparing received output with expected output...");
            errors = 0;
            max_error = 0;
            
            for (i = 0; i < OUTPUT_ROWS; i++) begin
                for (j = 0; j < OUTPUT_COLS; j++) begin
                    if (received_output[i][j] !== expected_output[i][j]) begin
                        current_error = (received_output[i][j] > expected_output[i][j]) ? 
                                       (received_output[i][j] - expected_output[i][j]) :
                                       (expected_output[i][j] - received_output[i][j]);
                        
                        if (errors < 10) begin  // Only print first 10 errors
                            $display("ERROR at [%0d][%0d]: Expected=%0d, Received=%0d, Diff=%0d", 
                                   i, j, expected_output[i][j], received_output[i][j], current_error);
                        end
                        errors++;
                        
                        if (current_error > max_error) begin
                            max_error = current_error;
                        end
                    end
                end
            end
            
            if (errors == 0) begin
                $display("SUCCESS: All outputs match! (%0d values checked)", OUTPUT_ROWS*OUTPUT_COLS);
            end else begin
                $display("FAILURE: %0d mismatches found out of %0d values", errors, OUTPUT_ROWS*OUTPUT_COLS);
                $display("Maximum error magnitude: %0d", max_error);
            end
        end
    endtask
    
    // Task to write received output to file
    task write_output_file();
        integer file, i, j;
        begin
            file = $fopen(output_file, "w");
            if (file == 0) begin
                $display("ERROR: Cannot open output file: %s", output_file);
                return;
            end
            
            $display("Writing received output to %s...", output_file);
            for (i = 0; i < OUTPUT_ROWS; i++) begin
                for (j = 0; j < OUTPUT_COLS; j++) begin
                    $fwrite(file, "%d", received_output[i][j]);
                    if (j < OUTPUT_COLS-1) begin
                        $fwrite(file, " ");
                    end
                end
                $fwrite(file, "\n");
            end
            $fclose(file);
            $display("Output written to file");
        end
    endtask
    
    // Main test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        valid = 0;
        data_in = 0;
        kernel_in = 0;
        errors = 0;
        output_count = 0;
        
        $display("\n========================================");
        $display("Winograd Convolution Testbench");
        $display("========================================\n");
        
        // Read data from files
        read_input_data();
        read_kernel_data();
        read_expected_output();
        
        // Reset sequence
        $display("\nApplying reset...");
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        
        // Start processing
        $display("\nStarting convolution...");
        @(posedge clk);
        valid = 1;
        @(posedge clk);
        valid = 0;
        
        // Send kernel and data
        fork
            send_kernel();
            send_input_data();
        join
        
        // Collect output
        collect_output();
        
        // Wait a few more cycles
        repeat(10) @(posedge clk);
        
        // Compare and report results
        compare_outputs();
        write_output_file();
        
        // Final report
        $display("\n========================================");
        $display("Simulation Summary");
        $display("========================================");
        $display("Input size: %0d x %0d", rows, cols);
        $display("Kernel size: 3 x 3");
        $display("Output size: %0d x %0d", OUTPUT_ROWS, OUTPUT_COLS);
        $display("Errors found: %0d", errors);
        $display("========================================\n");
        
        if (errors == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 1000000); // Adjust timeout as needed
        $display("\nERROR: Simulation timeout!");
        $finish;
    end
    
    // Optional: Generate VCD for waveform viewing
    initial begin
        $dumpfile("winograd_tb.vcd");
        $dumpvars(0, tb_Winograd_TOP_Serial);
    end

endmodule
