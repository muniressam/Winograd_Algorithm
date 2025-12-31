import numpy as np
import os

# Parameters
WIDTH = 16
ROWS = 224
COLS = 224
KERNEL_SIZE = 3

# Function to clip values to 16-bit signed range``
def clip_to_16bit(value):
    """Clip value to 16-bit signed integer range [-32768, 32767]"""
    return np.clip(value, -32768, 32767).astype(np.int16)

# Generate input data (224x224)
def generate_input_data(pattern='gradient'):
    """
    Generate input data with different patterns
    pattern options: 'gradient', 'checkerboard', 'random', 'sine', 'simple'
    """
    if pattern == 'gradient':
        # Horizontal gradient
        data = np.tile(np.arange(COLS, dtype=np.int16), (ROWS, 1))
        # Scale to use more of the 16-bit range
        data = (data * 100).astype(np.int16)
        
    elif pattern == 'checkerboard':
        # Checkerboard pattern
        data = np.zeros((ROWS, COLS), dtype=np.int16)
        data[::2, ::2] = 1000
        data[1::2, 1::2] = 1000
        
    elif pattern == 'random':
        # Random values in range [-1000, 1000]
        data = np.random.randint(-1000, 1000, size=(ROWS, COLS), dtype=np.int16)
        
    elif pattern == 'sine':
        # Sine wave pattern
        x = np.arange(COLS)
        y = np.arange(ROWS)
        X, Y = np.meshgrid(x, y)
        data = (1000 * np.sin(X / 20.0) * np.cos(Y / 20.0)).astype(np.int16)
        
    else:  # 'simple'
        # Simple incrementing pattern
        data = np.arange(ROWS * COLS, dtype=np.int16).reshape(ROWS, COLS)
        data = (data % 1000).astype(np.int16)
    
    return data

# Generate kernel (3x3)
def generate_kernel(kernel_type='sobel_x'):
    """
    Generate different types of kernels
    kernel_type options: 'sobel_x', 'sobel_y', 'gaussian', 'sharpen', 'edge', 'identity', 'simple'
    """
    if kernel_type == 'sobel_x':
        # Sobel X (horizontal edge detection)
        kernel = np.array([
            [1, 0, -1],
            [2, 0, -2],
            [1, 0, -1]
        ], dtype=np.int16)
        
    elif kernel_type == 'sobel_y':
        # Sobel Y (vertical edge detection)
        kernel = np.array([
            [1, 2, 1],
            [0, 0, 0],
            [-1, -2, -1]
        ], dtype=np.int16)
        
    elif kernel_type == 'gaussian':
        # Gaussian blur
        kernel = np.array([
            [1, 2, 1],
            [2, 4, 2],
            [1, 2, 1]
        ], dtype=np.int16)
        
    elif kernel_type == 'sharpen':
        # Sharpening kernel
        kernel = np.array([
            [0, -1, 0],
            [-1, 5, -1],
            [0, -1, 0]
        ], dtype=np.int16)
        
    elif kernel_type == 'edge':
        # Edge detection
        kernel = np.array([
            [-1, -1, -1],
            [-1, 8, -1],
            [-1, -1, -1]
        ], dtype=np.int16)
        
    elif kernel_type == 'identity':
        # Identity (no change)
        kernel = np.array([
            [0, 0, 0],
            [0, 1, 0],
            [0, 0, 0]
        ], dtype=np.int16)
        
    else:  # 'simple'
        # Simple test kernel
        kernel = np.array([
            [1, 1, 1],
            [1, 1, 1],
            [1, 1, 1]
        ], dtype=np.int16)
    
    return kernel

# Compute expected output using standard convolution with stride=2
def compute_convolution_stride2(input_data, kernel):
    """
    Compute 2D convolution with stride=2 (downsampling)
    This matches the expected output size of 112x112
    """
    output_rows = ROWS // 2
    output_cols = COLS // 2
    output = np.zeros((output_rows, output_cols), dtype=np.int32)
    
    print("Computing convolution (this may take a moment)...")
    
    for i in range(output_rows):
        if (i + 1) % 25 == 0:
            print(f"  Processing output row {i+1}/{output_rows}...")
            
        for j in range(output_cols):
            # Map output position to input position (stride=2)
            in_i = i * 2
            in_j = j * 2
            
            # Compute convolution at this position
            conv_sum = 0
            for ki in range(KERNEL_SIZE):
                for kj in range(KERNEL_SIZE):
                    # Input coordinates with boundary handling
                    row = in_i + ki - 1  # -1 for center alignment
                    col = in_j + kj - 1
                    
                    # Zero padding for boundaries
                    if 0 <= row < ROWS and 0 <= col < COLS:
                        conv_sum += int(input_data[row, col]) * int(kernel[ki, kj])
            
            # Clip to 16-bit range
            output[i, j] = np.clip(conv_sum, -32768, 32767)
    
    print("Convolution complete!")
    return output.astype(np.int16)

# Write data to file
def write_to_file(filename, data):
    """Write data array to text file"""
    with open(filename, 'w') as f:
        rows, cols = data.shape
        for i in range(rows):
            for j in range(cols):
                f.write(f"{data[i, j]}")
                if j < cols - 1:
                    f.write(" ")
            f.write("\n")
    print(f"Written {rows}x{cols} values to {filename}")

# Main generation function
def generate_test_files(input_pattern='simple', kernel_type='simple', output_dir='.'):
    """
    Generate all test files
    """
    print("\n" + "="*50)
    print("Winograd Convolution Test File Generator")
    print("="*50 + "\n")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate input data
    print(f"Generating input data (pattern: {input_pattern})...")
    input_data = generate_input_data(input_pattern)
    input_file = os.path.join(output_dir, 'input_data.txt')
    write_to_file(input_file, input_data)
    
    # Generate kernel
    print(f"\nGenerating kernel (type: {kernel_type})...")
    kernel = generate_kernel(kernel_type)
    kernel_file = os.path.join(output_dir, 'kernel_data.txt')
    write_to_file(kernel_file, kernel)
    print(f"Kernel:\n{kernel}\n")
    
    # Compute expected output
    print("Generating expected output...")
    expected_output = compute_convolution_stride2(input_data, kernel)
    output_file = os.path.join(output_dir, 'expected_output.txt')
    write_to_file(output_file, expected_output)
    
    # Statistics
    print("\n" + "="*50)
    print("Generation Summary")
    print("="*50)
    print(f"Input data range: [{input_data.min()}, {input_data.max()}]")
    print(f"Kernel sum: {kernel.sum()}")
    print(f"Expected output range: [{expected_output.min()}, {expected_output.max()}]")
    print(f"Output directory: {output_dir}")
    print("\nFiles generated:")
    print(f"  - {input_file}")
    print(f"  - {kernel_file}")
    print(f"  - {output_file}")
    print("="*50 + "\n")

# Example usage
if __name__ == "__main__":
    # You can change these parameters to generate different test cases
    
    # Test Case 1: Simple pattern with simple kernel
    print("Generating Test Case 1: Simple pattern")
    generate_test_files(input_pattern='simple', kernel_type='simple', output_dir='.')
    
    # Uncomment below to generate additional test cases
    
    # Test Case 2: Gradient with Sobel X
    # generate_test_files(input_pattern='gradient', kernel_type='sobel_x', output_dir='test_sobel')
    
    # Test Case 3: Random with Gaussian blur
    # generate_test_files(input_pattern='random', kernel_type='gaussian', output_dir='test_gaussian')
    
    # Test Case 4: Sine wave with edge detection
    # generate_test_files(input_pattern='sine', kernel_type='edge', output_dir='test_edge')
    
    print("\nTest files generated successfully!")
    print("You can now run your SystemVerilog testbench with these files.")