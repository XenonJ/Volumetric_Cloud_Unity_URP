Shader "Unlit/Slice3DShader"
{
    Properties
    {
        _VolumeTex ("Volume Texture", 3D) = "white" {}
        _Slice ("Slice", Range(0,1)) = 0.5
        [Toggle] _UseColorMap ("Use Color Map", Float) = 0
        _ColorRamp ("Color Ramp", 2D) = "white" {}
        _Brightness ("Brightness", Range(0.1, 3.0)) = 1.0
        _Contrast ("Contrast", Range(0.1, 3.0)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler3D _VolumeTex;
            float _Slice;
            float _UseColorMap;
            sampler2D _ColorRamp;
            float _Brightness;
            float _Contrast;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 使用传入的 _Slice 作为 z 分量采样 3D 纹理
                float3 uvw = float3(i.uv.x, i.uv.y, _Slice);
                
                // 采样3D纹理
                float4 noise = tex3D(_VolumeTex, uvw);
                
                // 应用亮度和对比度调整
                float value = noise.r * _Brightness;
                value = (value - 0.5) * _Contrast + 0.5;
                value = saturate(value);
                
                // 根据设置决定是否使用颜色映射
                if (_UseColorMap > 0.5) {
                    // 使用颜色渐变纹理
                    return tex2D(_ColorRamp, float2(value, 0.5));
                } else {
                    // 使用灰度显示
                    return float4(value, value, value, 1.0);
                }
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}