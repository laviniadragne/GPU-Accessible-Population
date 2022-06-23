all: gpu_sol

gpu_sol: helper.o
	nvcc -g -arch=sm_35 -rdc=true main.cu helper.o -o gpu_sol -O0

helper.o:
	nvcc -g -arch=sm_35 -rdc=true helper.cu -c -O0

clean:
	rm -f gpu_sol *.o