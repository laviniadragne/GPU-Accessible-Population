#include <math.h>
#include <fstream>
#include <bits/stdc++.h>

#include "helper.h"

#define MAX_CITIES		(1024 * 1024)

using namespace std;

// Fiecare thread calculeaza si stocheaza sinusul si cosinusul pentru
// latitudini si longitudini, pentru calculul ulterior de distante
// intre orase
__global__ void calcSinCos(float *lat, float *lon, float* sin_angle, float* cos_angle, 
    float* sin_angle_90, float* cos_angle_90, int N) {

    register unsigned int i = threadIdx.x + blockDim.x * blockIdx.x;

    if (i < N) {
        register float phi = (90.f - lat[i]) * DEGREE_TO_RADIANS;
        register float theta = lon[i] * DEGREE_TO_RADIANS;

        sin_angle[i] = sin(theta);
        cos_angle[i] = sqrt (1 - sin_angle[i] * sin_angle[i]);
        sin_angle_90[i] = sin(phi);
        cos_angle_90[i] = sqrt (1 - sin_angle_90[i] * sin_angle_90[i]);
    }
}

__global__ void compareDist(float *lat, float *lon,
                            unsigned long long int *pop, unsigned long long int *copy_pop,
                            int kmRange, int N, float* sin_angle, float* cos_angle, 
                            float* sin_angle_90, float* cos_angle_90) 
{
    register unsigned int i = threadIdx.x + blockDim.x * blockIdx.x;

    register float res;

    if (i < N) {
        register int j;

        register unsigned long long int *pop_i = &pop[i];
        register unsigned long long int copy_pop_i = copy_pop[i];
        j = i + 1;
        register unsigned long long int *pop_j = &pop[j];
        register unsigned long long int *copy_pop_j = &copy_pop[j];
        register float *lat_j = &lat[j];
        register float *lon_j = &lon[j]; 

        register float sin_angle_90_var = sin_angle_90[i];
        register float cos_angle_90_var = cos_angle_90[i];
        register float sin_angle_var = sin_angle[i];
        register float cos_angle_var = cos_angle[i];
    
        j = i + 1;
        register float *sin_angle_90_ptr = &sin_angle_90[j];
        register float *cos_angle_90_ptr = &cos_angle_90[j];
        register float *sin_angle_ptr = &sin_angle[j];
        register float *cos_angle_ptr = &cos_angle[j];
    
        // Calculez toate distantele de la orasul i la cele mai mari
        // decat el in lista de orase
        for (j = i + 1; j < N; j++) {
            // Calculul distantei efective pe baza latitudinii si longitudinii
            register float cs = sin_angle_90_var * (*sin_angle_90_ptr) * (cos_angle_var * (*cos_angle_ptr) + 
                                sin_angle_var * (*sin_angle_ptr)) + cos_angle_90_var * (*cos_angle_90_ptr);
            if (cs > 1) {
                cs = 1;
            } else if (cs < -1) {
                cs = -1;
            }
        
            res = 6371.f * acos(cs);

            if (res <= kmRange) {
                atomicAdd(pop_i, *copy_pop_j);
                atomicAdd(pop_j, copy_pop_i);
            }
            pop_j++;
            copy_pop_j++;
            lat_j++;
            lon_j++;

            sin_angle_90_ptr++;
            cos_angle_90_ptr++;
            sin_angle_ptr++;
            cos_angle_ptr++;
        }
    }
}

// sampleFileIO demos reading test files and writing output
void sampleFileIO(float kmRange, const char* fileIn, const char* fileOut)
{
    register string geon;
    register float lat, lon;
    register int pop;
    register float *device_lat = 0;
    register float *device_lon = 0;
    register float *cos_angle = 0;
    register float *sin_angle = 0;
    register float *cos_angle_90 = 0;
    register float *sin_angle_90 = 0;
    register unsigned long long int *device_pop = 0;
    register unsigned long long int *copy_pop_device;
    register float *host_lat = 0;
    register float *host_lon = 0;
    register unsigned long long int *host_pop = 0;
    register unsigned long long int N = 0;
    register int i;

    // Aloc datele pentru host
    host_lat = (float *) malloc(MAX_CITIES * sizeof(float));
    host_lon = (float *) malloc(MAX_CITIES * sizeof(float));
    host_pop = (unsigned long long int *) malloc(MAX_CITIES * sizeof(unsigned long long int));

    // Aloc datele pentru device
    cudaMalloc((void **) &device_lat, MAX_CITIES * sizeof(float));
    cudaMalloc((void **) &device_lon, MAX_CITIES * sizeof(float));
    cudaMalloc((void **) &device_pop, MAX_CITIES * sizeof(unsigned long long int));
    cudaMalloc((void **) &copy_pop_device, MAX_CITIES * sizeof(unsigned long long int));

    if (host_lat == 0 || host_lon == 0 || host_pop == 0 ||
        device_lat == 0 || device_lon == 0 || device_pop == 0 ||
        copy_pop_device == 0) {
        printf("[*] Error!\n");
        return;
    }

    ifstream ifs(fileIn);
    ofstream ofs(fileOut);

    // Memorez datele de intrare
    while(ifs >> geon >> lat >> lon >> pop)
    {
        host_pop[N] = pop;
        host_lat[N] = lat;
        host_lon[N] = lon;

        N++;
    }

    // Copiez datele din host in device (din CPU in GPU)
    cudaMemcpy(device_lat, host_lat, N * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(device_lon, host_lon, N * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(device_pop, host_pop, N * sizeof(unsigned long long int), cudaMemcpyHostToDevice);
    cudaMemcpy(copy_pop_device, host_pop, N * sizeof(unsigned long long int), cudaMemcpyHostToDevice);

    // Aloc memorie pentru vectorii in care voi retine sinusul si cosinusul
    // pentru latitudini si longitudini
    cudaMalloc((void **) &cos_angle, N * sizeof(unsigned long long int));
    cudaMalloc((void **) &sin_angle, N * sizeof(unsigned long long int));
    cudaMalloc((void **) &cos_angle_90, N * sizeof(unsigned long long int));
    cudaMalloc((void **) &sin_angle_90, N * sizeof(unsigned long long int));

    if (cos_angle == 0 || sin_angle == 0 ||
        cos_angle_90 == 0 || sin_angle_90 == 0) {
        printf("[*] Error!\n");
        return;
    }

    // Calculez numarul de blocuri de care am nevoie
    // pentru a lansa N thread-uri
    register const size_t block_size = 256;
    register size_t num_blocks = N / block_size;

    if (N % block_size) 
    ++num_blocks;

    // Calculez sin si cos necesare
    calcSinCos<<<num_blocks, block_size>>>(device_lat, device_lon, sin_angle, cos_angle,
         sin_angle_90, cos_angle_90, N);
    cudaDeviceSynchronize();
    if (cudaSuccess != cudaGetLastError()) {
        printf("[*] Error!\n");
        return;
    }

    // Calculez distantele si actualizez populatiile in functie de ele
    compareDist<<<num_blocks, block_size>>>(device_lat, device_lon, device_pop,
                copy_pop_device, kmRange, N, sin_angle, cos_angle,
                sin_angle_90, cos_angle_90);

    cudaDeviceSynchronize();
    if (cudaSuccess != cudaGetLastError()) {
        printf("[*] Error!\n");
        return;
    }

    // Copiez populatiile din device in host
    cudaMemcpy(host_pop, device_pop, N * sizeof(unsigned long long int), cudaMemcpyDeviceToHost);

    // Scriu in fisier populatiile
    for (i = 0; i < N; i++) {
        ofs << host_pop[i] << endl;
    }

    ifs.close();
    ofs.close();

    free(host_lon);
    free(host_lat);
    free(host_pop);

    cudaFree(device_lon);
    cudaFree(device_lat);
    cudaFree(device_pop);
    cudaFree(copy_pop_device);
    cudaFree(cos_angle);
    cudaFree(sin_angle);
    cudaFree(cos_angle_90);
    cudaFree(sin_angle_90);
}
