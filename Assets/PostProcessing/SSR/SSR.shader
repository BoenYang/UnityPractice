﻿Shader "Hidden/SSR"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
				float3 csRay : TEXCOORD1;
            };

			sampler2D _CameraDepthTexture;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;
			float3x3 _WorldToView;
			sampler2D _MainTex;
			sampler2D _BackfaceTex;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
				float4 cameraRay = float4(o.uv * 2.0 - 1.0, 1.0, 1.0);
				cameraRay = mul(unity_CameraInvProjection, cameraRay);
				o.csRay = cameraRay / cameraRay.w;
                return o;
            }


#define RAY_LENGTH 40.0
#define STEP_COUNT 64

			bool intersect(float raya, float rayb, float2 screenCoord) {

				float camDepth = Linear01Depth(tex2Dlod(_CameraDepthTexture, float4(screenCoord.xy / 2 + 0.5, 0, 0)));
				float backZ = tex2Dlod(_BackfaceTex, float4(screenCoord.xy / 2 + 0.5, 0, 0)).r;

				if (raya > rayb) {
					float t = raya;
					raya = rayb;
					rayb = t;
				}

				return raya < backZ && rayb > camDepth;
			}


			bool tracyRay(float3 start, float3 dir, out float2 hitPixel,out half3 debug) {

				float rayLength = ((start.z + dir.z * RAY_LENGTH) > -_ProjectionParams.y) ?
					(-_ProjectionParams.y - start.z) / dir.z : RAY_LENGTH;

				float3 end = start + dir * rayLength;

				float stepDelta = abs(end.z - start.z) / STEP_COUNT;
				float preDepth = start.z / -_ProjectionParams.z;

				float currentPos = start;

				debug = 0;
				UNITY_LOOP
				for (int i = 1; i <= STEP_COUNT; i++) {
					currentPos = start + i * stepDelta  * dir;
					float currentDepth = currentPos.z / -_ProjectionParams.z;
					float4 screenCoord = mul(unity_CameraProjection, float4(p, 1));
					screenCoord /= screenCoord.w;
					if (intersect(currentDepth, preDepth, screenCoord)) {

						float3 startPos = currentPos - stepDelta * dir;
						float2 screen = mul(unity_CameraProjection, float4(startPos, 1));
						
						preDepth = startPos.z / -_ProjectionParams.z;

						hitPixel = screenCoord.xy / 2 + 0.5;
						//		debugCol = float3(hitPixel, 0);
						return true;
					}
				}	 //view space ray trace
				return false;

			}
		


			fixed4 frag(v2f i) : SV_Target
			{
				float depth = Linear01Depth(tex2D(_CameraDepthTexture,i.uv).r);
				//反射的那个点在viewspace的坐标
				float3 csRayOrigin = depth * i.csRay;
				float3 wsNormal = tex2D(_CameraGBufferTexture2, i.uv).rgb * 2.0 - 1.0;
				float3 csNormal = normalize(mul((float3x3)_WorldToView, wsNormal));
				float3 reflectDir = normalize(reflect(csRayOrigin, csNormal));

				float2 hixPixel = 0;

				half3 reflection = 0;
				half3 debug = 0;

				if (tracyRay(csRayOrigin, reflectDir, hixPixel,debug)) {
					reflection = tex2D(_MainTex, hixPixel);
				}
				//return half4(debug,1);
                return tex2D(_MainTex, i.uv) + half4(reflection,1);
            }

			ENDCG
		}

    }
}
