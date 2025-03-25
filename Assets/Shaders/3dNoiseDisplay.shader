Shader "Unlit/Slice3DShader"
{
    Properties
    {
        _VolumeTex ("Volume Texture", 3D) = "" {}
        _Slice ("Slice", Range(0,1)) = 0.5
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
                return tex3D(_VolumeTex, float3(i.uv, _Slice));
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}