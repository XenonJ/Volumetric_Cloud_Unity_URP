Shader "Custom/RayMarchingCloudIntegrated_NoBg"
{
    Properties
    {
        _NoiseTex ("Noise Texture", 2D) = "white" {}
        _VolumeTex ("Volume Texture", 3D) = "" {}
        _StepCount ("Step Count", Int) = 64
        _BoxMin ("Box Min", Vector) = (-0.5, -0.5, -0.5, 0)
        _BoxMax ("Box Max", Vector) = (0.5, 0.5, 0.5, 0)
        _NoiseThreshold ("Noise Threshold", Float) = 0.4
        _DensityThreshold ("Cloud Density", Float) = 0.8
        _CloudSpeed ("Cloud Speed", Float) = 1.0
        _FrameCounter ("Frame Counter", Float) = 0
        _SampleRange ("Sample Range", Float) = 1.0
        _SampleJitter ("Sample Jitter", Float) = 0.1
        _LightDir ("Light Direction", Vector) = (0,1,0,0)
        _LightColor0 ("Light Color", Color) = (1,1,1,1)
        _LightAbsorptionTowardSun ("Light Absorption Toward Sun", Float) = 0.5
        _LightAbsorptionThroughCloud ("Light Absorption Through Cloud", Float) = 0.5
        _DarknessThreshold ("Darkness Threshold", Float) = 0.1
        _PhaseParams ("Phase Params", Vector) = (0.5, 0.5, 0.0, 1.0)
        _LightSteps ("Light Steps", Int) = 16
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "RayMarchingCloudIntegratedPass"
            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #define MAX_STEPS 128
            #define MAX_LIGHT_STEPS 16

            // 属性声明
            int _StepCount;
            float4 _BoxMin;
            float4 _BoxMax;
            sampler2D _NoiseTex;
            sampler3D _VolumeTex;
            float _NoiseThreshold;
            float _DensityThreshold;
            float _CloudSpeed;
            float _FrameCounter;
            float _SampleRange;
            float _SampleJitter;
            float4 _LightDir;

            float4 _LightColor0;
            float _LightAbsorptionTowardSun;
            float _LightAbsorptionThroughCloud;
            float _DarknessThreshold;
            float4 _PhaseParams;
            int _LightSteps;

            // 用于浮点比较的微小偏移
            float epsilon = 0.02;

            // 顶点属性结构体
            struct Attributes
            {
                float3 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            // 顶点与片元之间传递的数据结构
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 worldPos    : TEXCOORD0;
                float2 uv          : TEXCOORD1;
            };

            // 顶点着色器：转换顶点到裁剪空间和世界空间，并传递 UV
            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
                OUT.worldPos = TransformObjectToWorld(IN.positionOS);
                OUT.uv = IN.uv;
                return OUT;
            }

            // 计算射线与轴对齐包围盒（AABB）的交点，返回 (tNear, tFar)
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

            // 从 3D 纹理中采样噪声（取 red 通道）
            float Noise(float3 coord)
            {
                return tex3D(_VolumeTex, coord).r;
            }

            // 多重 octave 噪声采样，加入运动偏移，用于云细节的生成
            float GetCloudNoise(float3 worldPos, float distanceFromCamera)
            {
                float3 coord = worldPos * (_SampleRange * 0.01);
                coord.x += _FrameCounter * (_CloudSpeed * 0.01);
                coord.z += _FrameCounter * (_CloudSpeed * 0.01);
                coord.y -= _FrameCounter * (_CloudSpeed * 0.01);

                float detailFactor = 1.0 - saturate(distanceFromCamera / 1000.0);
                float n = Noise(coord) * 0.5;
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
                return max(n - _NoiseThreshold, 0.0);
            }

            // 计算云密度，结合噪声与边缘衰减
            float GetDensity(float3 pos, float distanceFromCamera)
            {
                float3 boxMin = _BoxMin.xyz;
                float3 boxMax = _BoxMax.xyz;
                float3 boxSize = boxMax - boxMin;
                float transitionWidth = boxSize.x * 0.3;
                float transitionHeight = boxSize.y * 0.5;
                float distToEdgeX = min(abs(pos.x - boxMin.x), abs(pos.x - boxMax.x));
                float distToEdgeZ = min(abs(pos.z - boxMin.z), abs(pos.z - boxMax.z));
                float distToEdgeY = min(abs(pos.y - boxMin.y), abs(pos.y - boxMax.y));
                float horizontalEdgeFade = min(distToEdgeX, distToEdgeZ);
                float horizontalWeight = saturate(horizontalEdgeFade / transitionWidth);
                float verticalWeight = saturate(distToEdgeY / transitionHeight);
                float edgeWeight = pow(verticalWeight, 1.0);
                float noiseVal = GetCloudNoise(pos, distanceFromCamera);
                noiseVal *= edgeWeight;
                float density = noiseVal;
                if (density < 1.0 / _DensityThreshold)
                    density = 0.0;
                return density;
            }

            // 为采样位置添加随机偏移，降低采样带来的伪影
            float3 RandomJitter(float3 seed)
            {
                seed = frac(seed * 0.1031);
                seed += dot(seed, seed.yzx + 33.33);
                return frac((seed.xxy + seed.yzz) * seed.zyx);
            }

            // Henyey-Greenstein 相位函数（描述散射方向性）
            float hg(float a, float g)
            {
                float g2 = g * g;
                return (1.0 - g2) / (4.0 * 3.1415 * pow(1.0 + g2 - 2.0 * g * a, 1.5));
            }

            // 计算最终相位函数，模拟光在云中的散射
            float PhaseFunction(float a)
            {
                float blend = 0.5;
                float hgBlend = hg(a, _PhaseParams.x) * (1.0 - blend) + hg(a, -_PhaseParams.y) * blend;
                return _PhaseParams.z + hgBlend * _PhaseParams.w;
            }

            // 沿光线方向积分，计算从采样点到光源方向上的光透射率
            float LightMarch(float3 position)
            {
                float3 dirToLight = normalize(_LightDir.xyz);
                float2 tBox = IntersectAABB(position, dirToLight, _BoxMin.xyz, _BoxMax.xyz);
                float dstInsideBox = tBox.y;
                float stepSize = dstInsideBox / _LightSteps;
                float totalDensity = 0.0;
                float3 pos = position;
                [loop]
                for (int i = 0; i < MAX_LIGHT_STEPS; i++)
                {
                    if (i >= _LightSteps)
                        break;
                    pos += dirToLight * stepSize;
                    float density = GetDensity(pos, length(pos - _WorldSpaceCameraPos));
                    totalDensity += max(0.0, density * stepSize);
                    if (totalDensity > 1.0)
                        break;
                }
                float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                return _DarknessThreshold + transmittance * (1.0 - _DarknessThreshold);
            }

            // 片元着色器：沿视线射线采样云体积，累计光照，计算最终颜色与透明度
            float4 frag (Varyings IN) : SV_Target
            {
                float3 camPos = _WorldSpaceCameraPos;
                float3 rayDir = normalize(IN.worldPos - camPos);

                // 计算射线与包围盒的交点
                float2 tNearFar = IntersectAABB(camPos, rayDir, _BoxMin.xyz, _BoxMax.xyz);
                if (tNearFar.x < 0 || tNearFar.x > tNearFar.y)
                    discard;

                float t = tNearFar.x;
                float stepSize = (tNearFar.y - tNearFar.x) / _StepCount;
                
                float densityAccum = 0.0;
                float3 lightEnergy = float3(0.0, 0.0, 0.0);
                float transmittance = 1.0;
                
                // 根据视线和光线夹角预计算相位函数
                float cosAngle = dot(rayDir, normalize(_LightDir.xyz));
                float phaseVal = PhaseFunction(cosAngle);
                
                // 沿射线均匀采样
                [loop]
                for (int i = 0; i < MAX_STEPS; i++)
                {
                    if (i >= _StepCount)
                        break;
                    t += stepSize;
                    float3 samplePos = camPos + rayDir * t;
                    // 添加随机抖动，减少采样伪影
                    float3 jitter = RandomJitter(samplePos + _FrameCounter) * _SampleJitter;
                    samplePos += jitter;
                    
                    // 若采样点在体积范围内，则进行密度与光照计算
                    if (all(samplePos >= _BoxMin.xyz - epsilon) && all(samplePos <= _BoxMax.xyz + epsilon))
                    {
                        float distanceFromCamera = length(samplePos - camPos);
                        float density = GetDensity(samplePos, distanceFromCamera);
                        densityAccum += density * stepSize;
                        
                        if (density > 0.0)
                        {
                            float lightTransmittance = LightMarch(samplePos);
                            lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                            transmittance *= exp(-density * stepSize * _LightAbsorptionThroughCloud);
                        }

                        if (transmittance < 0.01)
                        {
                            break;
                        }
                    }
                }
                
                // 最终云光颜色，乘以光源颜色
                float3 cloudCol = lightEnergy * _LightColor0.rgb;
                // 使用 1 - transmittance 作为 alpha 值，与背景混合
                float finalAlpha = saturate(1.0 - transmittance);
                return float4(cloudCol, finalAlpha);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Forward"
}