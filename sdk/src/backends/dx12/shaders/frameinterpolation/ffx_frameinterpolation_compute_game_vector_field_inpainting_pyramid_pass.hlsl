// This file is part of the FidelityFX SDK.
//
// Copyright (C) 2024 Advanced Micro Devices, Inc.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and /or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#if defined(FFX_HLSL_5_0)

#define FFX_FRAMEINTERPOLATION_BIND_SRV_GAME_MOTION_VECTOR_FIELD_X              0
#define FFX_FRAMEINTERPOLATION_BIND_SRV_GAME_MOTION_VECTOR_FIELD_Y              1

#define FFX_FRAMEINTERPOLATION_BIND_CB_FRAMEINTERPOLATION                       0

#ifdef FFX_HALF
    #undef FFX_HALF
    #define FFX_HALF 0
#endif

#define FFX_FRAMEINTERPOLATION_BIND_CB_INPAINTING_PYRAMID                       1

#include "frameinterpolation/ffx_frameinterpolation_callbacks_hlsl.h"
#include "frameinterpolation/ffx_frameinterpolation_common.h"

RWTexture2D<FfxFloat32x4> rw_inpainting_pyramid_prev : FFX_DECLARE_UAV(0);
RWTexture2D<FfxFloat32x4> rw_inpainting_pyramid_dst  : FFX_DECLARE_UAV(1);

FfxFloat32x4 Dx11ReduceGameVector4(FfxFloat32x4 v0, FfxFloat32x4 v1, FfxFloat32x4 v2, FfxFloat32x4 v3)
{
    FfxFloat32x4 result = FfxFloat32x4(0.0, 0.0, 0.0, 0.0);
    FfxFloat32 weights[4] = {
        FfxFloat32(v0.z > 0.0f),
        FfxFloat32(v1.z > 0.0f),
        FfxFloat32(v2.z > 0.0f),
        FfxFloat32(v3.z > 0.0f)
    };

    result += v0 * weights[0];
    result += v1 * weights[1];
    result += v2 * weights[2];
    result += v3 * weights[3];

    FfxFloat32 weightSum = weights[0] + weights[1] + weights[2] + weights[3];
    return result / ((weightSum > FFX_FRAMEINTERPOLATION_EPSILON) ? weightSum : 1.0f);
}

FfxFloat32x4 Dx11LoadGameVectorSource(FfxInt32x2 tex)
{
    FfxInt32x2 renderSize = RenderSize();
    if (tex.x < 0 || tex.y < 0 || tex.x >= renderSize.x || tex.y >= renderSize.y) {
        return FfxFloat32x4(0.0, 0.0, 0.0, 0.0);
    }

    VectorFieldEntry gameMv;
    FfxUInt32x2 packedGameFieldMv = LoadGameFieldMv(tex);
    UnpackVectorFieldEntries(packedGameFieldMv, gameMv);

    return FfxFloat32x4(gameMv.fMotionVector, gameMv.uHighPriorityFactor, gameMv.uLowPriorityFactor) * FfxFloat32(DisplaySize().x > 0);
}

FfxFloat32x4 Dx11LoadGameVectorPrevMip(FfxInt32x2 tex, FfxInt32x2 sourceSize)
{
    if (tex.x < 0 || tex.y < 0 || tex.x >= sourceSize.x || tex.y >= sourceSize.y) {
        return FfxFloat32x4(0.0, 0.0, 0.0, 0.0);
    }

    return rw_inpainting_pyramid_prev[tex];
}

[numthreads(8, 8, 1)]
void CS(FfxUInt32x3 DispatchThreadId : SV_DispatchThreadID)
{
    FfxUInt32 dstWidth;
    FfxUInt32 dstHeight;
    rw_inpainting_pyramid_dst.GetDimensions(dstWidth, dstHeight);

    if (DispatchThreadId.x >= dstWidth || DispatchThreadId.y >= dstHeight) {
        return;
    }

    FfxUInt32 targetMip = NumMips();
    FfxInt32x2 srcBase = FfxInt32x2(DispatchThreadId.xy) * 2;

    FfxFloat32x4 samples[4];
    if (targetMip == 0) {
        samples[0] = Dx11LoadGameVectorSource(srcBase + FfxInt32x2(0, 0));
        samples[1] = Dx11LoadGameVectorSource(srcBase + FfxInt32x2(1, 0));
        samples[2] = Dx11LoadGameVectorSource(srcBase + FfxInt32x2(0, 1));
        samples[3] = Dx11LoadGameVectorSource(srcBase + FfxInt32x2(1, 1));
    } else {
        FfxUInt32 srcWidth;
        FfxUInt32 srcHeight;
        rw_inpainting_pyramid_prev.GetDimensions(srcWidth, srcHeight);
        FfxInt32x2 sourceSize = FfxInt32x2(srcWidth, srcHeight);

        samples[0] = Dx11LoadGameVectorPrevMip(srcBase + FfxInt32x2(0, 0), sourceSize);
        samples[1] = Dx11LoadGameVectorPrevMip(srcBase + FfxInt32x2(1, 0), sourceSize);
        samples[2] = Dx11LoadGameVectorPrevMip(srcBase + FfxInt32x2(0, 1), sourceSize);
        samples[3] = Dx11LoadGameVectorPrevMip(srcBase + FfxInt32x2(1, 1), sourceSize);
    }

    rw_inpainting_pyramid_dst[DispatchThreadId.xy] = Dx11ReduceGameVector4(samples[0], samples[1], samples[2], samples[3]);
}

#else

#define FFX_FRAMEINTERPOLATION_BIND_SRV_GAME_MOTION_VECTOR_FIELD_X              0
#define FFX_FRAMEINTERPOLATION_BIND_SRV_GAME_MOTION_VECTOR_FIELD_Y              1

#define FFX_FRAMEINTERPOLATION_BIND_UAV_COUNTERS                                0
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_0             1
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_1             2
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_2             3
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_3             4
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_4             5
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_5             6
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_6             7
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_7             8
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_8             9
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_9             10
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_10            11
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_11            12
#define FFX_FRAMEINTERPOLATION_BIND_UAV_INPAINTING_PYRAMID_MIPMAP_12            13

#define FFX_FRAMEINTERPOLATION_BIND_CB_FRAMEINTERPOLATION                       0

#ifdef FFX_HALF
    #undef FFX_HALF
    #define FFX_HALF 0
#endif

#define FFX_FRAMEINTERPOLATION_BIND_CB_INPAINTING_PYRAMID                       1

#include "frameinterpolation/ffx_frameinterpolation_callbacks_hlsl.h"
#include "frameinterpolation/ffx_frameinterpolation_common.h"
#include "frameinterpolation/ffx_frameinterpolation_compute_game_vector_field_inpainting_pyramid.h"

#ifndef FFX_FRAMEINTERPOLATION_THREAD_GROUP_WIDTH
#define FFX_FRAMEINTERPOLATION_THREAD_GROUP_WIDTH 256
#endif // #ifndef FFX_FRAMEINTERPOLATION_THREAD_GROUP_WIDTH
#ifndef FFX_FRAMEINTERPOLATION_THREAD_GROUP_HEIGHT
#define FFX_FRAMEINTERPOLATION_THREAD_GROUP_HEIGHT 1
#endif // #ifndef FFX_FRAMEINTERPOLATION_THREAD_GROUP_HEIGHT
#ifndef FFX_FRAMEINTERPOLATION_THREAD_GROUP_DEPTH
#define FFX_FRAMEINTERPOLATION_THREAD_GROUP_DEPTH 1
#endif // #ifndef FFX_FRAMEINTERPOLATION_THREAD_GROUP_DEPTH
#ifndef FFX_FRAMEINTERPOLATION_NUM_THREADS
#define FFX_FRAMEINTERPOLATION_NUM_THREADS [numthreads(FFX_FRAMEINTERPOLATION_THREAD_GROUP_WIDTH, FFX_FRAMEINTERPOLATION_THREAD_GROUP_HEIGHT, FFX_FRAMEINTERPOLATION_THREAD_GROUP_DEPTH)]
#endif // #ifndef FFX_FRAMEINTERPOLATION_NUM_THREADS

FFX_FRAMEINTERPOLATION_NUM_THREADS
void CS(FfxUInt32x3 WorkGroupId : SV_GroupID, FfxUInt32 LocalThreadIndex : SV_GroupIndex)
{
    computeFrameinterpolationGameVectorFieldInpaintingPyramid(WorkGroupId, LocalThreadIndex);
}

#endif
