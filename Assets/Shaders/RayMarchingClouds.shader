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

            // 引入URP核心库，确保正确转换空间坐标
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _Color;
            int _StepCount;
            float4 _BoxMin;
            float4 _BoxMax;
            sampler2D _NoiseTex;
            sampler3D _VolumeTex;

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
                float densityAccum = 1.0;
                float t = tNearFar.x;   // 起始位置
                float stepSize = (tNearFar.y - tNearFar.x) / _StepCount;   // 步长，根据 StepCount 均匀采样
                for (int i = 0; i < _StepCount; i++)
                {
                    t += stepSize;
                    // 计算采样位置：从相机出发沿射线前进
                    float3 samplePos = camPos + rayDir * t;
                    // 判断采样位置是否在AABB内部
                    if (all(samplePos >= _BoxMin.xyz - epsilon) && all(samplePos <= _BoxMax.xyz + epsilon))
                    {
                        // // 将采样位置从世界坐标转换为纹理 UV 坐标
                        // float2 uv = (samplePos.xy - _BoxMin.xy) / ((_BoxMax - _BoxMin).xy);
                        // // 从 Worley noise 纹理采样（这里取 red 通道作为噪声值）
                        // float noise = 0;
                        // noise += tex2D(_NoiseTex, uv).r * 0.5;
                        // noise += tex2D(_NoiseTex, uv * 2).r * 0.25;
                        // noise += tex2D(_NoiseTex, uv * 4).r * 0.125;
                        // noise += tex2D(_NoiseTex, uv * 8).r * 0.0625;
                        // // 你可以根据需要对噪声值做非线性映射或者其它处理
                        // densityAccum += noise * stepSize;

                        // 从 3D 纹理采样（这里取 red 通道作为噪声值）
                        float3 uvw = (samplePos - _BoxMin.xyz) / (_BoxMax.xyz - _BoxMin.xyz);
                        float noise = 0;
                        noise += tex3D(_VolumeTex, uvw).r * 0.5;
                        noise += tex3D(_VolumeTex, uvw * 2).r * 0.25;
                        noise += tex3D(_VolumeTex, uvw * 4).r * 0.125;
                        noise += tex3D(_VolumeTex, uvw * 8).r * 0.0625;
                        // 你可以根据需要对噪声值做非线性映射或者其它处理
                        densityAccum += noise * stepSize;
                    }
                }
                // 根据累积的密度生成最终颜色，alpha 也可以基于 densityAccum 计算
                // if (densityAccum > 1.0)
                //     densityAccum = 1.0;
                if (densityAccum < 1.2) // magic number
                    densityAccum = 0.0;
                float3 finalColor = densityAccum * _Color.rgb;
                return float4(finalColor, saturate(densityAccum * _Color.a));
            }
            ENDHLSL
        }
    }
    FallBack "Universal Forward"
}