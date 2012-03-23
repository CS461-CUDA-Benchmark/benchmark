#include "serpent.h"

#include <cuda.h>
#include <cuda_runtime_api.h>

#ifndef SUBKEY_LENGTH
#define SUBKEY_LENGTH 132
#endif


// order of output from S-box functions
#define beforeS0(f) f(0,a,b,c,d,e)
#define afterS0(f) f(1,b,e,c,a,d)
#define afterS1(f) f(2,c,b,a,e,d)
#define afterS2(f) f(3,a,e,b,d,c)
#define afterS3(f) f(4,e,b,d,c,a)
#define afterS4(f) f(5,b,a,e,c,d)
#define afterS5(f) f(6,a,c,b,e,d)
#define afterS6(f) f(7,a,c,d,b,e)
#define afterS7(f) f(8,d,e,b,a,c)

// order of output from inverse S-box functions
#define beforeI7(f) f(8,a,b,c,d,e)
#define afterI7(f) f(7,d,a,b,e,c)
#define afterI6(f) f(6,a,b,c,e,d)
#define afterI5(f) f(5,b,d,e,c,a)
#define afterI4(f) f(4,b,c,e,a,d)
#define afterI3(f) f(3,a,b,e,c,d)
#define afterI2(f) f(2,b,d,e,c,a)
#define afterI1(f) f(1,a,b,c,e,d)
#define afterI0(f) f(0,a,d,b,e,c)

// The linear transformation.
#define linear_transformation(i,a,b,c,d,e) {\
        a = rotl_fixed(a, 13);   \
        c = rotl_fixed(c, 3);    \
        d = rotl_fixed(d ^ c ^ (a << 3), 7);     \
        b = rotl_fixed(b ^ a ^ c, 1);    \
        a = rotl_fixed(a ^ b ^ d, 5);       \
        c = rotl_fixed(c ^ d ^ (b << 7), 22);}

// The inverse linear transformation.
#define inverse_linear_transformation(i,a,b,c,d,e)        {\
        c = rotr_fixed(c, 22);   \
        a = rotr_fixed(a, 5);    \
        c ^= d ^ (b << 7);      \
        a ^= b ^ d;             \
        b = rotr_fixed(b, 1);    \
        d = rotr_fixed(d, 7) ^ c ^ (a << 3);     \
        b ^= a ^ c;             \
        c = rotr_fixed(c, 3);    \
        a = rotr_fixed(a, 13);}

#define S0(i, r0, r1, r2, r3, r4) \
       {           \
    r3 ^= r0;   \
    r4 = r1;   \
    r1 &= r3;   \
    r4 ^= r2;   \
    r1 ^= r0;   \
    r0 |= r3;   \
    r0 ^= r4;   \
    r4 ^= r3;   \
    r3 ^= r2;   \
    r2 |= r1;   \
    r2 ^= r4;   \
    r4 = ~r4;      \
    r4 |= r1;   \
    r1 ^= r3;   \
    r1 ^= r4;   \
    r3 |= r0;   \
    r1 ^= r3;   \
    r4 ^= r3;   \
            }

#define I0(i, r0, r1, r2, r3, r4) \
       {           \
    r2 = ~r2;      \
    r4 = r1;   \
    r1 |= r0;   \
    r4 = ~r4;      \
    r1 ^= r2;   \
    r2 |= r4;   \
    r1 ^= r3;   \
    r0 ^= r4;   \
    r2 ^= r0;   \
    r0 &= r3;   \
    r4 ^= r0;   \
    r0 |= r1;   \
    r0 ^= r2;   \
    r3 ^= r4;   \
    r2 ^= r1;   \
    r3 ^= r0;   \
    r3 ^= r1;   \
    r2 &= r3;   \
    r4 ^= r2;   \
            }

#define S1(i, r0, r1, r2, r3, r4) \
       {           \
    r0 = ~r0;      \
    r2 = ~r2;      \
    r4 = r0;   \
    r0 &= r1;   \
    r2 ^= r0;   \
    r0 |= r3;   \
    r3 ^= r2;   \
    r1 ^= r0;   \
    r0 ^= r4;   \
    r4 |= r1;   \
    r1 ^= r3;   \
    r2 |= r0;   \
    r2 &= r4;   \
    r0 ^= r1;   \
    r1 &= r2;   \
    r1 ^= r0;   \
    r0 &= r2;   \
    r0 ^= r4;   \
            }

#define I1(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r1;   \
    r1 ^= r3;   \
    r3 &= r1;   \
    r4 ^= r2;   \
    r3 ^= r0;   \
    r0 |= r1;   \
    r2 ^= r3;   \
    r0 ^= r4;   \
    r0 |= r2;   \
    r1 ^= r3;   \
    r0 ^= r1;   \
    r1 |= r3;   \
    r1 ^= r0;   \
    r4 = ~r4;      \
    r4 ^= r1;   \
    r1 |= r0;   \
    r1 ^= r0;   \
    r1 |= r4;   \
    r3 ^= r1;   \
            }

#define S2(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r0;   \
    r0 &= r2;   \
    r0 ^= r3;   \
    r2 ^= r1;   \
    r2 ^= r0;   \
    r3 |= r4;   \
    r3 ^= r1;   \
    r4 ^= r2;   \
    r1 = r3;   \
    r3 |= r4;   \
    r3 ^= r0;   \
    r0 &= r1;   \
    r4 ^= r0;   \
    r1 ^= r3;   \
    r1 ^= r4;   \
    r4 = ~r4;      \
            }

#define I2(i, r0, r1, r2, r3, r4) \
       {           \
    r2 ^= r3;   \
    r3 ^= r0;   \
    r4 = r3;   \
    r3 &= r2;   \
    r3 ^= r1;   \
    r1 |= r2;   \
    r1 ^= r4;   \
    r4 &= r3;   \
    r2 ^= r3;   \
    r4 &= r0;   \
    r4 ^= r2;   \
    r2 &= r1;   \
    r2 |= r0;   \
    r3 = ~r3;      \
    r2 ^= r3;   \
    r0 ^= r3;   \
    r0 &= r1;   \
    r3 ^= r4;   \
    r3 ^= r0;   \
            }

#define S3(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r0;   \
    r0 |= r3;   \
    r3 ^= r1;   \
    r1 &= r4;   \
    r4 ^= r2;   \
    r2 ^= r3;   \
    r3 &= r0;   \
    r4 |= r1;   \
    r3 ^= r4;   \
    r0 ^= r1;   \
    r4 &= r0;   \
    r1 ^= r3;   \
    r4 ^= r2;   \
    r1 |= r0;   \
    r1 ^= r2;   \
    r0 ^= r3;   \
    r2 = r1;   \
    r1 |= r3;   \
    r1 ^= r0;   \
            }

#define I3(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r2;   \
    r2 ^= r1;   \
    r1 &= r2;   \
    r1 ^= r0;   \
    r0 &= r4;   \
    r4 ^= r3;   \
    r3 |= r1;   \
    r3 ^= r2;   \
    r0 ^= r4;   \
    r2 ^= r0;   \
    r0 |= r3;   \
    r0 ^= r1;   \
    r4 ^= r2;   \
    r2 &= r3;   \
    r1 |= r3;   \
    r1 ^= r2;   \
    r4 ^= r0;   \
    r2 ^= r4;   \
            }

#define S4(i, r0, r1, r2, r3, r4) \
       {           \
    r1 ^= r3;   \
    r3 = ~r3;      \
    r2 ^= r3;   \
    r3 ^= r0;   \
    r4 = r1;   \
    r1 &= r3;   \
    r1 ^= r2;   \
    r4 ^= r3;   \
    r0 ^= r4;   \
    r2 &= r4;   \
    r2 ^= r0;   \
    r0 &= r1;   \
    r3 ^= r0;   \
    r4 |= r1;   \
    r4 ^= r0;   \
    r0 |= r3;   \
    r0 ^= r2;   \
    r2 &= r3;   \
    r0 = ~r0;      \
    r4 ^= r2;   \
            }

#define I4(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r2;   \
    r2 &= r3;   \
    r2 ^= r1;   \
    r1 |= r3;   \
    r1 &= r0;   \
    r4 ^= r2;   \
    r4 ^= r1;   \
    r1 &= r2;   \
    r0 = ~r0;      \
    r3 ^= r4;   \
    r1 ^= r3;   \
    r3 &= r0;   \
    r3 ^= r2;   \
    r0 ^= r1;   \
    r2 &= r0;   \
    r3 ^= r0;   \
    r2 ^= r4;   \
    r2 |= r3;   \
    r3 ^= r0;   \
    r2 ^= r1;   \
            }

#define S5(i, r0, r1, r2, r3, r4) \
       {           \
    r0 ^= r1;   \
    r1 ^= r3;   \
    r3 = ~r3;      \
    r4 = r1;   \
    r1 &= r0;   \
    r2 ^= r3;   \
    r1 ^= r2;   \
    r2 |= r4;   \
    r4 ^= r3;   \
    r3 &= r1;   \
    r3 ^= r0;   \
    r4 ^= r1;   \
    r4 ^= r2;   \
    r2 ^= r0;   \
    r0 &= r3;   \
    r2 = ~r2;      \
    r0 ^= r4;   \
    r4 |= r3;   \
    r2 ^= r4;   \
            }

#define I5(i, r0, r1, r2, r3, r4) \
       {           \
    r1 = ~r1;      \
    r4 = r3;   \
    r2 ^= r1;   \
    r3 |= r0;   \
    r3 ^= r2;   \
    r2 |= r1;   \
    r2 &= r0;   \
    r4 ^= r3;   \
    r2 ^= r4;   \
    r4 |= r0;   \
    r4 ^= r1;   \
    r1 &= r2;   \
    r1 ^= r3;   \
    r4 ^= r2;   \
    r3 &= r4;   \
    r4 ^= r1;   \
    r3 ^= r0;   \
    r3 ^= r4;   \
    r4 = ~r4;      \
            }

#define S6(i, r0, r1, r2, r3, r4) \
       {           \
    r2 = ~r2;      \
    r4 = r3;   \
    r3 &= r0;   \
    r0 ^= r4;   \
    r3 ^= r2;   \
    r2 |= r4;   \
    r1 ^= r3;   \
    r2 ^= r0;   \
    r0 |= r1;   \
    r2 ^= r1;   \
    r4 ^= r0;   \
    r0 |= r3;   \
    r0 ^= r2;   \
    r4 ^= r3;   \
    r4 ^= r0;   \
    r3 = ~r3;      \
    r2 &= r4;   \
    r2 ^= r3;   \
            }

#define I6(i, r0, r1, r2, r3, r4) \
       {           \
    r0 ^= r2;   \
    r4 = r2;   \
    r2 &= r0;   \
    r4 ^= r3;   \
    r2 = ~r2;      \
    r3 ^= r1;   \
    r2 ^= r3;   \
    r4 |= r0;   \
    r0 ^= r2;   \
    r3 ^= r4;   \
    r4 ^= r1;   \
    r1 &= r3;   \
    r1 ^= r0;   \
    r0 ^= r3;   \
    r0 |= r2;   \
    r3 ^= r1;   \
    r4 ^= r0;   \
            }

#define S7(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r2;   \
    r2 &= r1;   \
    r2 ^= r3;   \
    r3 &= r1;   \
    r4 ^= r2;   \
    r2 ^= r1;   \
    r1 ^= r0;   \
    r0 |= r4;   \
    r0 ^= r2;   \
    r3 ^= r1;   \
    r2 ^= r3;   \
    r3 &= r0;   \
    r3 ^= r4;   \
    r4 ^= r2;   \
    r2 &= r0;   \
    r4 = ~r4;      \
    r2 ^= r4;   \
    r4 &= r0;   \
    r1 ^= r3;   \
    r4 ^= r1;   \
            }

#define I7(i, r0, r1, r2, r3, r4) \
       {           \
    r4 = r2;   \
    r2 ^= r0;   \
    r0 &= r3;   \
    r2 = ~r2;      \
    r4 |= r3;   \
    r3 ^= r1;   \
    r1 |= r0;   \
    r0 ^= r2;   \
    r2 &= r4;   \
    r1 ^= r2;   \
    r2 ^= r0;   \
    r0 |= r2;   \
    r3 &= r4;   \
    r0 ^= r3;   \
    r4 ^= r1;   \
    r3 ^= r4;   \
    r4 |= r0;   \
    r3 ^= r2;   \
    r4 ^= r2;   \
            }

// key xor
#define KX(r, a, b, c, d, e)    {\
        a ^= subkey[4 * r + 0]; \
        b ^= subkey[4 * r + 1]; \
        c ^= subkey[4 * r + 2]; \
        d ^= subkey[4 * r + 3];}


/**	Decrypt a single block on the device.
 */
__device__ void serpent_cuda_decrypt_block(block128* block, uint32* subkey);


/**	Decrypt the specified array of blocks with the specified subkey through a CUDA thread.
 */
__global__ void serpent_cuda_decrypt_blocks(block128* cuda_blocks, uint32* subkey, int block_count, int blocks_per_thread );


/**	Encrypt a single block on the device.
 */
__device__ void serpent_cuda_encrypt_block(block128* block, uint32* subkey);


/**	Encrypt the specified array of blocks with the specified subkey through a CUDA thread.
 */
__global__ void serpent_cuda_encrypt_blocks(block128* cuda_blocks, uint32* subkey, int block_count, int blocks_per_thread );


/**	Flip the bytes of the specified 32-bit unsigned integer.
 *	@return	A 32-bit unsigned integer with the bytes mirrored.
 */
__device__ uint32 mirror_bytes32_cu(uint32 x);


__device__ void serpent_cuda_decrypt_block(block128* block, uint32* subkey) {
	uint32 a, b, c, d, e;
	int j;

	// Change to little endian.
        a = mirror_bytes32_cu(block->x0);
        b = mirror_bytes32_cu(block->x1);
        c = mirror_bytes32_cu(block->x2);
        d = mirror_bytes32_cu(block->x3);

	// Decrypt the current block.
	j = 4;
	subkey += 96;
	beforeI7(KX);
	goto start;
	do
	{
		c = b;
		b = d;
		d = e;
		subkey -= 32;
		beforeI7(inverse_linear_transformation);
	start:
		beforeI7(I7); afterI7(KX);
		afterI7(inverse_linear_transformation); afterI7(I6); afterI6(KX);
		afterI6(inverse_linear_transformation); afterI6(I5); afterI5(KX);
		afterI5(inverse_linear_transformation); afterI5(I4); afterI4(KX);
		afterI4(inverse_linear_transformation); afterI4(I3); afterI3(KX);
		afterI3(inverse_linear_transformation); afterI3(I2); afterI2(KX);
		afterI2(inverse_linear_transformation); afterI2(I1); afterI1(KX);
		afterI1(inverse_linear_transformation); afterI1(I0); afterI0(KX);
	}
	while (--j != 0);

	// Restore to big endian based on algorithm-defined order.
	block->x0 = mirror_bytes32_cu(a);
	block->x1 = mirror_bytes32_cu(d);
	block->x2 = mirror_bytes32_cu(b);
	block->x3 = mirror_bytes32_cu(e);
}


__global__ void serpent_cuda_decrypt_blocks( block128* cuda_blocks, uint32* subkey, int block_count, int blocks_per_thread ) {
	int index = (blockIdx.x * blockDim.x) + (threadIdx.x * blocks_per_thread);
	int i;

	// Encrypted the minimal number of blocks.
	for ( i = 0; i < blocks_per_thread; i++ ) {
		serpent_cuda_decrypt_block(&(cuda_blocks[index + i]), subkey);
	}

	// Encrypt the extra blocks that fall outside the minimal number of block.s
	index = ( blockDim.x * blocks_per_thread ) + ((blockIdx.x * blockDim.x) + threadIdx.x); // (end of array) + (absolute thread #).
	if ( index < block_count ) {
		serpent_cuda_decrypt_block(&(cuda_blocks[index]), subkey);
	}
}


__device__ void serpent_cuda_encrypt_block(block128* block, uint32* subkey) {
	uint32 a, b, c, d, e;
	int j;

	// Change to little endian.
	a = mirror_bytes32_cu(block->x0);
	b = mirror_bytes32_cu(block->x1);
	c = mirror_bytes32_cu(block->x2);
	d = mirror_bytes32_cu(block->x3);

	// Encrypt the current block.
	j = 1;
	do {
		beforeS0(KX); beforeS0(S0); afterS0(linear_transformation);
		afterS0(KX); afterS0(S1); afterS1(linear_transformation);
		afterS1(KX); afterS1(S2); afterS2(linear_transformation);
		afterS2(KX); afterS2(S3); afterS3(linear_transformation);
		afterS3(KX); afterS3(S4); afterS4(linear_transformation);
		afterS4(KX); afterS4(S5); afterS5(linear_transformation);
		afterS5(KX); afterS5(S6); afterS6(linear_transformation);
		afterS6(KX); afterS6(S7);

		if (j == 4)
			break;

		++j;
		c = b;
		b = e;
		e = d;
		d = a;
		a = e;
		subkey += 32;
		beforeS0(linear_transformation);
	} while (1);
	afterS7(KX);

	// Restore to big endian based on algorithm-defined order.
	block->x0 = mirror_bytes32_cu(d);
	block->x1 = mirror_bytes32_cu(e);
	block->x2 = mirror_bytes32_cu(b);
	block->x3 = mirror_bytes32_cu(a);
}


__global__ void serpent_cuda_encrypt_blocks( block128* cuda_blocks, uint32* subkey, int block_count, int blocks_per_thread ) {
	int index = (blockIdx.x * blockDim.x) + (threadIdx.x * blocks_per_thread);
	int i;

	// Encrypted the minimal number of blocks.
	for ( i = 0; i < blocks_per_thread; i++ ) {
		serpent_cuda_encrypt_block(&(cuda_blocks[index + i]), subkey);
	}

	// Encrypt the extra blocks that fall outside the minimal number of block.s
	index = ( blockDim.x * blocks_per_thread ) + ((blockIdx.x * blockDim.x) + threadIdx.x); // (end of array) + (absolute thread #).
	if ( index < block_count ) {
		serpent_cuda_encrypt_block(&(cuda_blocks[index]), subkey);
	}
}


__device__ uint32 mirror_bytes32_cu(uint32 x) {
	uint32 out;

	// Change to Little Endian.
	out = (uint8_t) x;
       	out <<= 8; out |= (uint8_t) (x >> 8);
	out <<= 8; out |= (uint8_t) (x >> 16);
	out = (out << 8) | (uint8_t) (x >> 24);

	// Return out.
	return out;
}


extern "C"
int serpent_cuda_decrypt_cu(uint32* subkey, block128* blocks, int block_count) {
	//cudaDeviceProp cuda_device;
	block128* cuda_blocks;
	uint32* cuda_subkey;
	size_t total_global_memory;
	size_t blocks_global_memory;
	int count;
	int i;

	// Get the number of devices.
	if ( cudaGetDeviceCount( &count ) != cudaSuccess ) {
		fprintf(stderr, "Unable to get device count.");
		return -1;
	}
	if ( count == 0 ) {
		fprintf(stderr, "No CUDA-capable devices found.");
		return -1;
	}

	// Move subkey to constant memory.
	if ( cudaMalloc( (void**)&cuda_subkey, sizeof(uint32) * SUBKEY_LENGTH) != cudaSuccess ) {
		fprintf(stderr, "Unable to malloc subkey.");
		return -1;
	}
	if ( cudaMemcpy( cuda_subkey, subkey, sizeof(uint32) * SUBKEY_LENGTH, cudaMemcpyHostToDevice) != cudaSuccess ) {
		fprintf(stderr, "Unable to memcopy subkey.");
		return -1;
	}

	// Calculate the amount of global memory available for blocks.
	if ( cudaMemGetInfo(&blocks_global_memory, &total_global_memory) != cudaSuccess ) {
		fprintf(stderr, "Unable to get memory information.");
		return -1;
	}
	blocks_global_memory -= SERPENT_CUDA_MEMORY_BUFFER; // Magic number.
	fprintf(stderr, "Total global memory: %i.\n", total_global_memory);

	// Calculate number of blocks per thread.
	int thread_count = 440;
	int blocks_per_kernel = blocks_global_memory / sizeof(block128);
	int blocks_per_thread = blocks_per_kernel / thread_count;
	fprintf(stderr, "Blocks global memory: %i.\nBlocks per kernel: %i.\n", blocks_global_memory, blocks_per_kernel);

	// Allocate a buffer for the blocks on the GPU.
	if ( cudaMalloc( (void**)&cuda_blocks, (int)(sizeof(block128) * blocks_per_kernel) ) != cudaSuccess ) {
		fprintf(stderr, "Unable to malloc blocks.\n");
		fprintf(stderr, "Error message: %s.\n", cudaGetErrorString(cudaGetLastError()));
		return -1;
	}

	i = 0;
	while (i < block_count) {
		fprintf(stderr, "Running an iteration. i: %i. block_count: %i.\n", i, block_count);
		cudaError_t error;

		// Corner case.
		if ( i + blocks_per_kernel > block_count ) {
			blocks_per_kernel = block_count - i;
		}

		// Move blocks to global memory.
		if ( cudaMemcpy( cuda_blocks, &(blocks[i]), sizeof(block128) * blocks_per_kernel, cudaMemcpyHostToDevice ) != cudaSuccess ) {
			fprintf(stderr, "Unable to memcopy blocks.");
			return -1;
		}

		// Run encryption.
		serpent_cuda_decrypt_blocks<<<1,thread_count>>>(cuda_blocks, cuda_subkey, blocks_per_kernel, blocks_per_thread);
		error = cudaGetLastError();
		if ( error != cudaSuccess ) {
			fprintf(stderr, "ERROR on the GPU.");
			fprintf(stderr, "Error message: %s.\n", cudaGetErrorString(error));
			return -1;
		}

		// Get blocks from global memory.
		if ( cudaMemcpy( &(blocks[i]), cuda_blocks, sizeof(block128) * blocks_per_kernel, cudaMemcpyDeviceToHost ) != cudaSuccess ) {
			fprintf(stderr, "Unable to retrieve blocks.");
			return -1;
		}
	
		// Increment i by the number of blocks processed.
		i += blocks_per_kernel;
	}

	// Free blocks from global memory.
	cudaFree(cuda_blocks);

	// Free key from constant memory.
	cudaFree(cuda_subkey);

	// Return success.
	return 0;
}


extern "C"
int serpent_cuda_encrypt_cu(uint32* subkey, block128* blocks, int block_count) {
	//cudaDeviceProp cuda_device;
	block128* cuda_blocks;
	uint32* cuda_subkey;
	size_t total_global_memory;
	size_t blocks_global_memory;
	int count;
	int i;

	// Get the number of devices.
	if ( cudaGetDeviceCount( &count ) != cudaSuccess ) {
		fprintf(stderr, "Unable to get device count.");
		return -1;
	}
	if ( count == 0 ) {
		fprintf(stderr, "No CUDA-capable devices found.");
		return -1;
	}

	// Move subkey to constant memory.
	if ( cudaMalloc( (void**)&cuda_subkey, sizeof(uint32) * SUBKEY_LENGTH) != cudaSuccess ) {
		fprintf(stderr, "Unable to malloc subkey.");
		return -1;
	}
	if ( cudaMemcpy( cuda_subkey, subkey, sizeof(uint32) * SUBKEY_LENGTH, cudaMemcpyHostToDevice) != cudaSuccess ) {
		fprintf(stderr, "Unable to memcopy subkey.");
		return -1;
	}

	// Calculate the amount of global memory available for blocks.
	if ( cudaMemGetInfo(&blocks_global_memory, &total_global_memory) != cudaSuccess ) {
		fprintf(stderr, "Unable to get memory information.");
		return -1;
	}
	blocks_global_memory -= SERPENT_CUDA_MEMORY_BUFFER; // Magic number.
	fprintf(stderr, "Total global memory: %i.\n", total_global_memory);

	// Calculate number of blocks per thread.
	int thread_count = 500;
	int blocks_per_kernel = blocks_global_memory / sizeof(block128);
	int blocks_per_thread = blocks_per_kernel / thread_count;
	fprintf(stderr, "Blocks global memory: %i.\nBlocks per kernel: %i.\n", blocks_global_memory, blocks_per_kernel);

	// Allocate a buffer for the blocks on the GPU.
	if ( cudaMalloc( (void**)&cuda_blocks, (int)(sizeof(block128) * blocks_per_kernel) ) != cudaSuccess ) {
		fprintf(stderr, "Unable to malloc blocks.\n");
		fprintf(stderr, "Error message: %s.\n", cudaGetErrorString(cudaGetLastError()));
		return -1;
	}

	i = 0;
	while (i < block_count) {
		fprintf(stderr, "Running an iteration. i: %i. block_count: %i.\n", i, block_count);
		// Corner case.
		if ( i + blocks_per_kernel > block_count ) {
			blocks_per_kernel = block_count - i;
		}

		// Move blocks to global memory.
		if ( cudaMemcpy( cuda_blocks, &(blocks[i]), sizeof(block128) * blocks_per_kernel, cudaMemcpyHostToDevice ) != cudaSuccess ) {
			fprintf(stderr, "Unable to memcopy blocks.");
			return -1;
		}

		// Run encryption.
		serpent_cuda_encrypt_blocks<<<1,thread_count>>>(cuda_blocks, cuda_subkey, blocks_per_kernel, blocks_per_thread);
		if ( cudaSuccess != cudaGetLastError() ) {
			fprintf(stderr, "ERROR on the GPU.");
			return -1;
		}

		// Get blocks from global memory.
		if ( cudaMemcpy( &(blocks[i]), cuda_blocks, sizeof(block128) * blocks_per_kernel, cudaMemcpyDeviceToHost ) != cudaSuccess ) {
			fprintf(stderr, "Unable to retrieve blocks.");
			return -1;
		}
	
		// Increment i by the number of blocks processed.
		i += blocks_per_kernel;
	}

	// Free blocks from global memory.
	cudaFree(cuda_blocks);

	// Free key from constant memory.
	cudaFree(cuda_subkey);

	// Return success.
	return 0;
}