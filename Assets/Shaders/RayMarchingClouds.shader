Shader "Custom/RayMarchingCloud"
{
    Properties
    {
        _NoiseTex ("Noise Texture", 2D) = "white" {}
        _VolumeTex ("Volume Texture", 3D) = "" {}
        _Color ("Base Color", Color) = (1,1,1,1)
        _StepCount ("Step Count", Int) = 64
        _BoxMin ("Box Min", Vector) = (-0.5, -0.5, -0.5, 0)
        _BoxMax ("Box Max", Vector) = (0.5, 0.5, 0.5, 0)
        _NoiseThreshold ("Noise Threshold", Float) = 0.4
        _DensityThreshold ("Cloud Density", Float) = 0.8
        _AccumulateThreshold ("Accumulate Threshold", Float) = 0.2
        _CloudSpeed ("Cloud Speed", Float) = 1.0
        _FrameCounter ("Frame Counter", Float) = 0
        _SampleRange ("Sample Range", Float) = 1.0
        _SampleJitter ("Sample Jitter", Float) = 0.1
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "RayMarchingCloudPass"
            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _Color;
            int _StepCount;
            float4 _BoxMin;
            float4 _BoxMax;
            sampler2D _NoiseTex;
            sampler3D _VolumeTex;
            float _NoiseThreshold;
            float _DensityThreshold;
            float _AccumulateThreshold;
            float _CloudSpeed;
            float _FrameCounter;
            float _SampleRange;
            float _SampleJitter;

            // 用于判断浮点比较的边界偏移
            float epsilon = 0.02;

            struct Attributes
            {
                float3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 worldPos    : TEXCOORD0;
            };

            // 顶点着色器：完成对象到裁剪空间和世界空间的转换
            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
                OUT.worldPos = TransformObjectToWorld(IN.positionOS);
                return OUT;
            }

            // 计算光线与包围盒 AABB 的交点
            float2 IntersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax)
            {
                float3 tMin = (boxMin - rayOrigin) / rayDir;
                float3 tMax = (boxMax - rayOrigin) / rayDir;
                float3 t1 = min(tMin, tMax);
                float3 t2 = max(tMin, tMax);
                float tNear = max(max(t1.x, t1.y), t1.z);
                float tFar = min(min(t2.x, t2.y), t2.z);
                return float2(tNear, tFar);
            }

            /////////////////////////////////
            // 以下函数实现 density 采样逻辑
            /////////////////////////////////

            // Noise: 从 3D 纹理采样噪声（取 red 通道）
            float Noise(float3 coord)
            {
                return tex3D(_VolumeTex, coord).r;
            }

            // GetCloudNoise: 基于世界坐标和距离采样噪声，多重 octave 叠加并加入运动偏移
            float GetCloudNoise(float3 worldPos, float distanceFromCamera)
            {
                float3 coord = worldPos * (_SampleRange * 0.01);
                coord.x += _FrameCounter * (_CloudSpeed * 0.1);
                coord.z += _FrameCounter * (_CloudSpeed * 0.1);
                coord.y -= _FrameCounter * (_CloudSpeed * 0.1);

                // detailFactor 根据距离做平滑衰减（近处增加细节层）
                float detailFactor = 1.0 - saturate(distanceFromCamera / 1000.0);
                float n = Noise(coord) * 0.55;
                if (detailFactor > 0.3)
                {
                    coord *= 3.0;
                    n += Noise(coord) * 0.25 * detailFactor;
                    if (detailFactor > 0.6)
                    {
                        coord *= 3.0;
                        n += Noise(coord) * 0.125 * detailFactor;
                        if (detailFactor > 0.8)
                        {
                            coord *= 3.0;
                            n += Noise(coord) * 0.0625 * detailFactor;
                        }
                    }
                }
                // 通过阈值调整噪声范围
                return max(n - _NoiseThreshold, 0.0) * (1.0 / (1.0 - _NoiseThreshold));
            }

            // GetDensity: 结合噪声采样与边界衰减计算云密度
            float GetDensity(float3 pos, float distanceFromCamera)
            {
                float3 boxMin = _BoxMin.xyz;
                float3 boxMax = _BoxMax.xyz;
                float3 boxSize = boxMax - boxMin;
                // 设定边缘过渡宽度（水平和垂直）
                float transitionWidth = boxSize.x * 0.3;
                float transitionHeight = boxSize.y * 0.5;
                // 计算当前点到各边界的距离
                float distToEdgeX = min(abs(pos.x - boxMin.x), abs(pos.x - boxMax.x));
                float distToEdgeZ = min(abs(pos.z - boxMin.z), abs(pos.z - boxMax.z));
                float distToEdgeY = min(abs(pos.y - boxMin.y), abs(pos.y - boxMax.y));
                float horizontalEdgeFade = min(distToEdgeX, distToEdgeZ);
                float horizontalWeight = saturate(horizontalEdgeFade / transitionWidth);
                float verticalWeight = saturate(distToEdgeY / transitionHeight);
                // 使用较高次幂强化边缘衰减
                float edgeWeight = pow(verticalWeight, 1.0);
                // 基础噪声采样
                float noiseVal = GetCloudNoise(pos, distanceFromCamera);
                noiseVal *= edgeWeight;
                float density = noiseVal;
                // 设定低密度门槛（防止噪声引入过多微弱云雾）
                if (density < 1 / _DensityThreshold)
                    density = 0.0;
                return density;
            }

            // 根据输入的 seed 生成一个随机的 float3，返回值在 [0,1) 内
            float3 RandomJitter(float3 seed)
            {
                seed = frac(seed * 0.1031);
                seed += dot(seed, seed.yzx + 33.33);
                return frac((seed.xxy + seed.yzz) * seed.zyx);
            }

            /////////////////////////////////
            // 片元着色器：沿射线采样计算累积密度并生成最终颜色
            /////////////////////////////////
            float4 frag (Varyings IN) : SV_Target
            {
                float3 camPos = _WorldSpaceCameraPos;
                float3 rayDir = normalize(IN.worldPos - camPos);

                // 计算射线与包围盒交点
                float2 tNearFar = IntersectAABB(camPos, rayDir, _BoxMin.xyz, _BoxMax.xyz);
                // 判断射线是否与盒子相交
                if (tNearFar.x < 0 || tNearFar.x > tNearFar.y)
                    discard;

                float t = tNearFar.x;
                float stepSize = (tNearFar.y - tNearFar.x) / _StepCount;
                float densityAccum = 0.0;

                // 沿射线均匀采样
                for (int i = 0; i < _StepCount; i++)
                {
                    t += stepSize;
                    float3 samplePos = camPos + rayDir * t;
                    float3 jitter = RandomJitter(samplePos + _FrameCounter) * _SampleJitter;
                    samplePos += jitter;
                    // 判断采样点是否仍在盒子内部（加上 epsilon 容差）
                    if (all(samplePos >= _BoxMin.xyz - epsilon) && all(samplePos <= _BoxMax.xyz + epsilon))
                    {
                        float distanceFromCamera = length(samplePos - camPos);
                        float density = GetDensity(samplePos, distanceFromCamera);
                        densityAccum += density * stepSize;
                    }
                }

                // 简单阈值判断，低密度部分不参与显示
                if (densityAccum < _AccumulateThreshold)
                    densityAccum = 0.0;

                float3 finalColor = densityAccum * _Color.rgb;
                return float4(finalColor, saturate(densityAccum * _Color.a));
            }
            ENDHLSL
        }
    }
    FallBack "Universal Forward"
}