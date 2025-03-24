Shader "Custom/RayMarchingCloud"
{
    Properties
    {
        _NoiseTex ("Noise Texture", 2D) = "white" {}
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

            // 片元着色器：利用 Worley noise 采样实现体积云的效果
            float4 frag (Varyings IN) : SV_Target
            {
                // 获取相机在世界空间的位置
                float3 camPos = _WorldSpaceCameraPos;
                // 计算从相机指向当前片元的方向（归一化）
                float3 rayDir = normalize(IN.worldPos - camPos);
                
                // 初始化累加颜色或密度
                float densityAccum = 1.0;
                float t = 0.0;
                float stepSize = 0.5;   // 步进大小
                for (int i = 0; i < _StepCount; i++)
                {
                    t += stepSize;
                    // 计算采样位置：从相机出发沿射线前进
                    float3 samplePos = camPos + rayDir * t;
                    // 判断采样位置是否在AABB内部
                    if (all(samplePos >= _BoxMin.xyz - epsilon) && all(samplePos <= _BoxMax.xyz + epsilon))
                    {
                        // 将采样位置从世界坐标转换为纹理 UV 坐标
                        float2 uv = (samplePos.xz - _BoxMin.xz) / ((_BoxMax - _BoxMin).xz);
                        // 从 Worley noise 纹理采样（这里取 red 通道作为噪声值）
                        float noise = tex2D(_NoiseTex, uv).r;
                        // 你可以根据需要对噪声值做非线性映射或者其它处理
                        densityAccum += noise * stepSize;
                    }
                }
                // 根据累积的密度生成最终颜色，alpha 也可以基于 densityAccum 计算
                float3 finalColor = densityAccum * _Color.rgb;
                return float4(finalColor, saturate(densityAccum * _Color.a));
            }
            ENDHLSL
        }
    }
    FallBack "Universal Forward"
}