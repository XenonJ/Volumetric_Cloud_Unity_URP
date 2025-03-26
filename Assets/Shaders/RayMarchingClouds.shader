Shader "Custom/RayMarchingCloud"
{
    Properties
    {
        _NoiseTex ("Noise Texture", 2D) = "white" {}
        _VolumeTex ("Volume Texture", 3D) = "" {}
        _Color ("Base Color", Color) = (1,1,1,1)
        _StepCount ("Step Count", Range(8, 64)) = 32
        _MaxSteps ("Max Steps", Int) = 64
        _BoxMin ("Box Min", Vector) = (-0.5, -0.5, -0.5, 0)
        _BoxMax ("Box Max", Vector) = (0.5, 0.5, 0.5, 0)
        _FlowSpeed ("Flow Speed", Vector) = (0.1, 0.05, 0.08, 0)
        _TimeScale ("Time Scale", Float) = 1.0
        _FlowDirection ("Flow Direction", Vector) = (1, 0, 0.5, 0)
        _TurbulenceScale ("Turbulence Scale", Float) = 0.5
        _DensityThreshold ("Density Threshold", Range(0, 2)) = 1.2
        _DensityMultiplier ("Density Multiplier", Range(0.1, 20)) = 1.0
        _CloudSharpness ("Cloud Sharpness", Range(0.1, 10)) = 1.0
        _DetailStrength ("Detail Strength", Range(0.1, 2.0)) = 0.5
        _NoiseScale ("Noise Scale", Range(0.1, 5.0)) = 1.0
        _HeightFalloff ("Height Falloff", Range(0, 10)) = 2.0
        _TransparencyThreshold ("Early Exit Threshold", Range(0.01, 0.5)) = 0.1
    }
    SubShader
    {
        // 使用URP标准标签和队列（此处队列和混合方式可根据需求调整）
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "RayMarchingCloudPass"
            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            // 声明顶点和片元函数
            #pragma vertex vert
            #pragma fragment frag
            
            // 开启编译器优化
            #pragma target 3.0

            // 引入URP核心库，确保正确转换空间坐标
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _Color;
            int _StepCount;
            int _MaxSteps;
            float4 _BoxMin;
            float4 _BoxMax;
            sampler2D _NoiseTex;
            sampler3D _VolumeTex;
            float4 _FlowSpeed;
            float _TimeScale;
            float4 _FlowDirection;
            float _TurbulenceScale;
            float _DensityThreshold;
            float _DensityMultiplier;
            float _CloudSharpness;
            float _DetailStrength;
            float _NoiseScale;
            float _HeightFalloff;
            float _TransparencyThreshold;

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

            // 添加简单的扰动函数，增强流动的自然性
            float3 ApplyTurbulence(float3 baseUVW, float time)
            {
                // 使用简单的正弦函数创建波动效果
                float3 turbulence;
                turbulence.x = sin(baseUVW.z * 10.0 + time * 0.5) * _TurbulenceScale * 0.03;
                turbulence.y = sin(baseUVW.x * 8.0 + time * 0.4) * _TurbulenceScale * 0.02;
                turbulence.z = sin(baseUVW.y * 12.0 + time * 0.6) * _TurbulenceScale * 0.04;
                return turbulence;
            }

            // 添加基于高度的衰减函数
            float HeightBasedDensity(float3 uvw)
            {
                // 使云在顶部和底部更稀疏
                float height = uvw.y; // 假设y轴是高度
                float heightGradient = 1.0 - pow(abs(height - 0.5) * 2.0, _HeightFalloff);
                return max(0.0, heightGradient);
            }

            // 添加Remap函数，将值从一个范围重新映射到另一个范围
            float CustomRemap(float value, float oldMin, float oldMax, float newMin, float newMax)
            {
                return newMin + (value - oldMin) / (oldMax - oldMin) * (newMax - newMin);
            }

            // 顶点着色器：完成对象到裁剪空间和世界空间的转换
            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
                OUT.worldPos = TransformObjectToWorld(IN.positionOS);
                return OUT;
            }

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

            // 片元着色器：利用 Worley noise 采样实现体积云的效果
            float4 frag (Varyings IN) : SV_Target
            {
                // 获取相机在世界空间的位置
                float3 camPos = _WorldSpaceCameraPos;
                // 计算从相机指向当前片元的方向（归一化）
                float3 rayDir = normalize(IN.worldPos - camPos);

                // 计算射线与 AABB 的交点
                float2 tNearFar = IntersectAABB(camPos, rayDir, _BoxMin.xyz, _BoxMax.xyz);
                
                // 初始化累加颜色或密度
                float densityAccum = 0.0; // 从0开始累积，而不是1.0
                float transmittance = 1.0; // 透明度
                float t = tNearFar.x;   // 起始位置
                float stepSize = (tNearFar.y - tNearFar.x) / _StepCount;   // 步长，根据 StepCount 均匀采样
                
                // 计算时间和主流向
                float time = _Time.y * _TimeScale;
                float3 normalizedFlowDir = normalize(_FlowDirection.xyz);
                float3 timeOffset = time * _FlowSpeed.xyz * normalizedFlowDir;
                
                // 初始化颜色
                float3 cloudColor = float3(0, 0, 0);
                
                // 使用常量预设的最大步数，避免循环展开问题
                int actualSteps = min(_StepCount, _MaxSteps);
                
                // 设置为 loop，告诉编译器这是一个需要保留的循环而非展开
                [loop]
                for (int i = 0; i < actualSteps; i++)
                {
                    t += stepSize;
                    // 计算采样位置：从相机出发沿射线前进
                    float3 samplePos = camPos + rayDir * t;
                    
                    // 判断采样位置是否在AABB内部
                    bool insideBox = all(samplePos >= _BoxMin.xyz - epsilon) && all(samplePos <= _BoxMax.xyz + epsilon);
                    if (!insideBox) continue; // 跳过AABB外的采样点，提高效率
                    
                    // 从 3D 纹理采样（这里取 red 通道作为噪声值）
                    float3 uvw = (samplePos - _BoxMin.xyz) / (_BoxMax.xyz - _BoxMin.xyz);
                    
                    // 应用高度梯度，使云在上下更稀疏
                    float heightFactor = HeightBasedDensity(uvw);
                    
                    // 如果高度因子太小，跳过计算，提高效率
                    if (heightFactor < 0.01) continue;
                    
                    // 应用湍流扰动
                    float3 turbulence = ApplyTurbulence(uvw, time);
                    
                    // 对采样坐标应用时间偏移和湍流 - 实现流动效果
                    float3 flowUVW = uvw + timeOffset + turbulence;
                    
                    // 确保纹理坐标在 [0,1] 范围内循环采样（解决边界问题）
                    flowUVW = frac(flowUVW);
                    
                    // 调整噪声比例
                    flowUVW *= _NoiseScale;
                    
                    // 多尺度分形噪声采样（FBM - Fractal Brownian Motion）
                    // 基础形状噪声 (低频)
                    float baseShape = tex3D(_VolumeTex, flowUVW * 0.5).r;
                    
                    // 快速检测 - 如果基础形状太小，跳过后续计算
                    if (baseShape < _DensityThreshold * 0.5) continue;
                    
                    // 应用非线性变换以创建更分明的云块
                    baseShape = pow(baseShape, _CloudSharpness);
                    
                    // 详细结构噪声 (高频)
                    float detailNoise = 0;
                    detailNoise += tex3D(_VolumeTex, flowUVW * 2 + timeOffset * 0.7).r * 0.25;
                    detailNoise += tex3D(_VolumeTex, flowUVW * 4 + timeOffset * 0.4).r * 0.125;
                    detailNoise += tex3D(_VolumeTex, flowUVW * 8 + timeOffset * 0.2).r * 0.0625;
                    
                    // 细节噪声侵蚀基础形状边缘
                    float detailModifier = CustomRemap(detailNoise, 0, 0.5, 1.0 - _DetailStrength, 1.0);
                    
                    // 最终云密度
                    float cloudDensity = baseShape * detailModifier * heightFactor * _DensityMultiplier;
                    
                    // 应用密度阈值，创建更分散的云
                    cloudDensity = max(0, cloudDensity - _DensityThreshold);
                    
                    // 如果密度为0，跳过后续计算
                    if (cloudDensity <= 0.0) continue;
                    
                    // 应用Beer定律模拟光的散射
                    float transmittanceStep = exp(-cloudDensity * stepSize);
                    
                    // 累积颜色和透明度
                    float contributionForThisStep = cloudDensity * transmittance;
                    cloudColor += _Color.rgb * contributionForThisStep;
                    
                    // 更新透明度
                    transmittance *= transmittanceStep;
                    
                    // 累积总密度
                    densityAccum += contributionForThisStep;
                    
                    // 如果已经非常不透明，提前退出循环
                    if (transmittance < _TransparencyThreshold)
                        break;
                }
                
                // 确保Alpha不超过1
                float alpha = 1.0 - transmittance;
                
                // 如果密度太低就直接透明
                if (alpha < 0.01)
                    discard;
                
                return float4(cloudColor, alpha);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Forward"
}