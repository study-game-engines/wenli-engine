#include <curand_kernel.h>
#include "geommath.hpp"
#include "RayTracingCamera.hpp"
#include "Image.hpp"
#include "Color.hpp"
#include "TestMaterial.hpp"

struct Params{
    My::Image*                      image;
    My::RayTracingCamera<float>*    cam;
    curandStateMRG32k3a*            rand_state;
    OptixTraversableHandle          handle;
    int32_t                         max_depth;
    int32_t                         num_of_samples;
};

struct RayGenData{
};

struct MissData {
    My::RGBf bg_color;
};

struct HitGroupData {
    Material material_type;
    My::RGBf base_color;
    float    fuzz;
    float    ir;
};

template <typename T>
struct SbtRecord
{
    __align__( OPTIX_SBT_RECORD_ALIGNMENT ) char header[OPTIX_SBT_RECORD_HEADER_SIZE];
    T data;
};

using RayGenSbtRecord   =   SbtRecord<RayGenData>;
using MissSbtRecord     =   SbtRecord<MissData>;
using HitGroupSbtRecord =   SbtRecord<HitGroupData>;
