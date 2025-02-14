#include <curand_kernel.h>
#include <iostream>

#include "BVH.hpp"
#include "Image.hpp"
#include "Ray.hpp"
#include "RayTracingCamera.hpp"
#include "Sphere.hpp"

#define float_precision float
#include "TestMaterial.hpp"
#include "geommath.hpp"
#include "ColorSpaceConversion.hpp"

using hitable = My::Hitable<float_precision>;
using hitable_ptr = hitable *;
using image = My::Image;

using bvh = My::SimpleBVHNode<float_precision>;

using camera = My::RayTracingCamera<float_precision>;

using sphere = My::Sphere<float_precision, material *>;

// help functions 
#define checkCudaErrors(val) check_cuda((val), #val, __FILE__, __LINE__)
void check_cuda(cudaError_t result, char const *const func,
                const char *const file, int const line) {
    if (result) {
        std::cerr << "CUDA error = " << static_cast<unsigned int>(result)
                  << " (" << cudaGetErrorString(result) << ") "
                  << " at " << file << ":" << line << " '" << func << "' \n";
        cudaDeviceReset();
        exit(99);
    }
}

// Render
__device__ color ray_color(const ray &r, bvh **d_world,
                           curandStateMRG32k3a_t *local_rand_state) {
    const color white({1.0, 1.0, 1.0});
    const color black({0.0, 0.0, 0.0});
    const color bg_color({0.5, 0.7, 1.0});

    ray cur_ray = r;
    color cur_attenuation(white);
    for (int i = 0; i < 50; i++) {
        hit_record rec;
        if ((*d_world)->Intersect(cur_ray, rec, 0.001f, FLT_MAX)) {
            ray scattered;
            color attenuation;

            const material *pMat =
                *reinterpret_cast<material *const *>(rec.getMaterial());
            if (pMat->scatter(cur_ray, rec, attenuation, scattered,
                                      local_rand_state)) {
                cur_attenuation = cur_attenuation * attenuation;
                cur_ray = scattered;
                if (My::LengthSquared(cur_attenuation) < 0.0002f) return black; // roughly squre of (1.0 / 256)
            } else {
                return black;
            }
        } else {
            vec3 unit_direction = cur_ray.getDirection();
            float_precision t = 0.5f * (unit_direction[1] + 1.0f);
            vec3 c = (1.0f - t) * white +
                     t * bg_color;
            return cur_attenuation * c;
        }
    }

    return black;
}

__global__ void rand_init(curandStateMRG32k3a_t *rand_state) {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        curand_init(2023, 0, 0, rand_state);
    }
}

__global__ void render_init(curandStateMRG32k3a_t *rand_state) {
    // Each thread in a block gets unique seed
    curand_init(2023 + threadIdx.x, 0, 0, &rand_state[threadIdx.x]);
}


static const int samples_per_pixel = 512;

__global__ void render(vec3 *fb, int max_x, int max_y, int number_of_samples,
                       camera **cam, bvh **d_world, curandStateMRG32k3a_t *rand_state) {
    int i = blockIdx.x;
    int j = blockIdx.y;
    if ((i > max_x) || (j > max_y)) return;
    curandStateMRG32k3a_t* local_rand_state = &rand_state[threadIdx.x];
    __shared__ vec3 col[samples_per_pixel];

    //printf("[%d %d](%d %d)", blockIdx.x, blockIdx.y, threadIdx.x, threadIdx.y);
    float_precision u = float_precision(i + curand_uniform(local_rand_state)) / float_precision(max_x);
    float_precision v = float_precision(j + curand_uniform(local_rand_state)) / float_precision(max_y);
    ray r = (*cam)->get_ray(u, v, local_rand_state);
    col[threadIdx.x] = vec3({0.0f, 0.0f, 0.0f});
    col[threadIdx.x] += ray_color(r, d_world, local_rand_state);

    __syncthreads();

    for (int k = samples_per_pixel / 2; k > 0; k/=2) {
        if (threadIdx.x < k) {
            col[threadIdx.x] += col[threadIdx.x + k];
        }
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        fb[j * max_x + i] = My::Linear2SRGB(col[0] / float_precision(number_of_samples));
    }
}

// World
#define RND curand_uniform(local_rand_state)
__global__ void create_scene(bvh **d_world, camera **d_camera,
                             float_precision aspect_ratio, curandStateMRG32k3a_t *local_rand_state) {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        const int scene_obj_num = 22 * 22 + 1 + 3;
        hitable_ptr *pList = new hitable_ptr[scene_obj_num];
        pList[0] = new sphere(1000.0f, point3({0, -1000, -1}),
                              new lambertian(vec3({0.5, 0.5, 0.5})));

        int i = 1;
        for (int a = -11; a < 11; a++) {
            for (int b = -11; b < 11; b++) {
                float_precision choose_mat = RND;
                vec3 center({a + 0.9f * RND, 0.2f, b + 0.9f * RND});
                if (choose_mat < 0.8f) {
                    pList[i++] = new sphere(
                        0.2f, center,
                        new lambertian(
                            color({RND * RND, RND * RND, RND * RND})));
                } else if (choose_mat < 0.95f) {
                    pList[i++] = new sphere(
                        0.2f, center,
                        new metal(
                            color({0.5f * (1.0f + RND), 0.5f * (1.0f + RND),
                                   0.5f * (1.0f + RND)}),
                            0.5f * RND));
                } else {
                    pList[i++] = new sphere(0.2f, center, new dielectric(1.5f));
                }
            }
        }

        pList[i++] = new sphere(1.0f, vec3({0, 1, 0}), new dielectric(1.5f));
        pList[i++] = new sphere(1.0f, vec3({-4, 1, 0}),
                                new lambertian(color({0.4, 0.2, 0.1})));
        pList[i++] = new sphere(1.0f, vec3({4, 1, 0}),
                                new metal(color({0.7, 0.6, 0.5}), 0.0));

        (*d_world) = new bvh(pList, 0, scene_obj_num, local_rand_state);
        delete pList;

        point3 lookfrom{13, 2, 3};
        point3 lookat{0, 0, 0};
        vec3 vup{0, 1, 0};
        auto dist_to_focus = 10.0f;
        auto aperture = 0.1f;

        *d_camera = new camera(lookfrom, lookat, vup, 20.0f, aspect_ratio,
                               aperture, dist_to_focus);
    }
}

__global__ void free_scene(bvh **d_world, camera **d_camera) {
    delete *d_world;
    delete *d_camera;
}

int main() {
    // Render Settings
    const float_precision aspect_ratio = 16.0 / 9.0;
    const int image_width = 1920;
    const int image_height = static_cast<int>(image_width / aspect_ratio);

    // Canvas
    image img;
    img.Width = image_width;
    img.Height = image_height;
    img.bitcount = 96;
    img.bitdepth = 32;
    img.pixel_format = My::PIXEL_FORMAT::RGB32;
    img.pitch = (img.bitcount >> 3) * img.Width;
    img.compressed = false;
    img.compress_format = My::COMPRESSED_FORMAT::NONE;
    img.data_size = img.Width * img.Height * (img.bitcount >> 3);

    checkCudaErrors(cudaMallocManaged((void **)&img.data, img.data_size));

    // Camera
    camera **d_camera;
    checkCudaErrors(cudaMalloc((void **)&d_camera, sizeof(camera *)));

    // World
    bvh **d_world;
    checkCudaErrors(cudaMalloc((void **)&d_world, sizeof(bvh *)));

    curandStateMRG32k3a_t *d_rand_state_1;

    checkCudaErrors(cudaMalloc((void **)&d_rand_state_1, sizeof(curandStateMRG32k3a_t)));

    rand_init<<<1, 1>>>(d_rand_state_1);

    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    create_scene<<<1, 1>>>(d_world, d_camera, aspect_ratio, d_rand_state_1);

    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    // Pre-rendering
    curandStateMRG32k3a_t *d_rand_state_2;
    checkCudaErrors(
        cudaMalloc((void **)&d_rand_state_2, samples_per_pixel * sizeof(curandStateMRG32k3a_t)));

    // Rendering
    int tile_width = samples_per_pixel;
    int tile_height = 1;

    dim3 blocks(image_width, image_height);
    dim3 threads(tile_width, tile_height);

    render_init<<<1, threads>>>(d_rand_state_2);
    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    cudaEventRecord(start);
    render<<<blocks, threads>>>(reinterpret_cast<vec3 *>(img.data), image_width,
                                image_height, samples_per_pixel, d_camera,
                                d_world, d_rand_state_2);
    cudaEventRecord(stop);

    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    printf("Rendering time: %f ms\n", milliseconds);

    img.SaveTGA("raytracing_cuda.tga");

    // clean up
    checkCudaErrors(cudaDeviceSynchronize());
    free_scene<<<1, 1>>>(d_world, d_camera);
    checkCudaErrors(cudaGetLastError());

    checkCudaErrors(cudaFree(d_rand_state_1));
    checkCudaErrors(cudaFree(d_rand_state_2));
    checkCudaErrors(cudaFree(d_camera));
    checkCudaErrors(cudaFree(d_world));
    checkCudaErrors(cudaFree(img.data));
    img.data = nullptr;  // to avoid double free

    return 0;
}