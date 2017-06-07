#version 410 compatibility
#define composite1
#define fsh
#define ShaderStage 1
#include "/lib/Syntax.glsl"

/* DRAWBUFFERS:145 */

const bool colortex5MipmapEnabled = true;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D gdepthtex;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;
uniform sampler2D shadowtex1;
uniform sampler2DShadow shadow;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 upPosition;

uniform float frameTimeCounter;
uniform float nightVision;
uniform float near;
uniform float far;

uniform ivec2 eyeBrightnessSmooth;

uniform int isEyeInWater;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

varying vec2 texcoord;
varying vec2 pixelSize;

#include "/lib/Settings.glsl"
#include "/lib/Utility.glsl"
#include "/lib/Debug.glsl"
#include "/lib/Uniform/Projection_Matrices.fsh"
#include "/lib/Uniform/Shading_Variables.glsl"
#include "/lib/Uniform/Shadow_View_Matrix.fsh"
#include "/lib/Fragment/Masks.fsh"

#include "/UserProgram/centerDepthSmooth.glsl" // Doesn't seem to be enabled unless it's initialized in a fragment.

vec3 GetDiffuse(vec2 coord) {
	return texture2D(colortex1, coord).rgb;
}

float GetDepth(vec2 coord) {
	return texture2D(gdepthtex, coord).x;
}

float GetTransparentDepth(vec2 coord) {
	return texture2D(depthtex1, coord).x;
}

float ExpToLinearDepth(float depth) {
	return 2.0 * near * (far + near - depth * (far - near));
}

vec3 CalculateViewSpacePosition(vec3 screenPos) {
	screenPos = screenPos * 2.0 - 1.0;
	
	return projMAD(projInverseMatrix, screenPos) / (screenPos.z * projInverseMatrix[2].w + projInverseMatrix[3].w);
}

#include "/lib/Fragment/Calculate_Shaded_Fragment.fsh"

void BilateralUpsample(vec3 normal, float depth, float waterMask, out vec3 GI, out vec2 VL) {
	GI = vec3(0.0);
	VL = vec2(1.0);
	
#if defined GI_ENABLED || defined VOLUMETRIC_LIGHT
	vec2 scaledCoord = texcoord * COMPOSITE0_SCALE;
	
	float expDepth = ExpToLinearDepth(depth);
	
	cfloat kernal = 2.0;
	cfloat range = kernal * 0.5 - 0.5;
	
	float totalWeight = 0.0;
	
	vec3 samples = vec3(0.0);
	
	#ifdef GI_ENABLED
	if (mix(waterMask, 1.0 - waterMask * float(depth < 1.0), isEyeInWater) + float(depth >= 1.0) < 0.5) {
		for(float y = -range; y <= range; y++) {
			for(float x = -range; x <= range; x++) {
				vec2 offset = vec2(x, y) * pixelSize;
				
				float sampleDepth  = ExpToLinearDepth(texture2D(gdepthtex, texcoord + offset * 8.0).x);
				vec3  sampleNormal =     DecodeNormal(texture2D(colortex4, texcoord + offset * 8.0).g, 11);
				
				float weight  = clamp01(1.0 - abs(expDepth - sampleDepth));
					  weight *= abs(dot(normal, sampleNormal)) * 0.5 + 0.5;
					  weight += 0.001;
				
				samples += pow2(texture2DLod(colortex5, scaledCoord + offset * 2.0, 1).rgb) * weight;
				
				totalWeight += weight;
			}
		} GI = samples * 5.0 / totalWeight;
		
		samples = vec3(0.0);
		totalWeight = 0.0;
	}
	
	GI.b *= 1.0 - isEyeInWater;
	#endif
	
	#ifdef VOLUMETRIC_LIGHT
	for(float y = -range; y <= range; y++) {
		for(float x = -range; x <= range; x++) {
			vec2 offset = vec2(x, y) * pixelSize;
			
			float sampleDepth = ExpToLinearDepth(texture2D(gdepthtex, texcoord + offset * 8.0).x);
			float weight = clamp01(1.0 - abs(expDepth - sampleDepth)) + 0.001;
			
			samples.xy += texture2DLod(colortex5, scaledCoord + offset, 0).ab * weight;
			
			totalWeight += weight;
		}
	} VL = samples.xy / totalWeight;
	
	VL.y *= mix(waterMask, 1.0f, isEyeInWater);
	#endif
#endif
}

#include "/lib/Misc/Calculate_Fogfactor.glsl"
#include "/lib/Fragment/Water_Depth_Fog.fsh"
#include "/lib/Fragment/AerialPerspective.fsh"

float CalculateSunglow(vec3 worldSpaceVector) {
	float sunglow = max0(dot(worldSpaceVector, worldLightVector) - 0.01);
	      sunglow = pow(sunglow, 8.0);
	
	return sunglow;
}

float Luma(vec3 color) {
  return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 ColorSaturate(vec3 base, float saturation) {
    return mix(base, vec3(Luma(base)), -saturation);
}

vec3 LightDesaturation(vec3 color, vec2 lightmap){
	cvec3 nightColor = vec3(0.25, 0.35, 0.7);
	cvec3 torchColor = vec3(0.5, 0.33, 0.15) * 0.1;
	vec3  desatColor = vec3(color.x + color.y + color.z);
	
	desatColor = mix(desatColor * nightColor, mix(desatColor, color, 0.5) * ColorSaturate(torchColor, 0.35) * 40.0, clamp01(lightmap.r * 2.0));
	
	float moonFade = smoothstep(0.0, 0.3, max0(-worldLightVector.y));
	
	float coeff = clamp01(min(moonFade, 0.65) + pow(1.0 - lightmap.g, 1.4));
	
	return mix(color, desatColor, coeff);
}

void main() {
	vec2 texure4 = ScreenTex(colortex4).rg;
	
	vec4  decode4       = Decode4x8F(texure4.r);
	Mask  mask          = CalculateMasks(decode4.r);
	float smoothness    = decode4.g;
	float torchLightmap = decode4.b;
	float skyLightmap   = decode4.a;
	
	float depth0 = (mask.hand > 0.5 ? 0.9 : GetDepth(texcoord));
	
	vec3 normal = DecodeNormal(texure4.g, 11) * mat3(gbufferModelViewInverse);
	vec3 waterNormal;
	
	float depth1 = mask.hand > 0.5 ? depth0 : GetTransparentDepth(texcoord);
	
	if (depth0 != depth1) {
		vec2 texure0 = texture2D(colortex0, texcoord).rg;
		
		vec4 decode0 = Decode4x8F(texure0.r);
		waterNormal = DecodeNormalU(texure0.g) * mat3(gbufferModelViewInverse);
		
		mask.transparent = 1.0;
		mask.water       = DecodeWater(texure0.g);
		mask.bits.xy     = vec2(1.0, mask.water);
		mask.materialIDs = EncodeMaterialIDs(1.0, mask.bits);

		texure4 = vec2(Encode4x8F(vec4(mask.materialIDs, decode0.r, 0.0, decode0.g)), ReEncodeNormal(texure0.g, 11.0));
	}
	
	vec3 GI; vec2 VL;
	BilateralUpsample(mat3(gbufferModelViewInverse) * normal, depth1, mask.water, GI, VL);
	
	gl_FragData[1] = vec4(texure4.rg, 0.0, 1.0);
	gl_FragData[2] = vec4(VL.xy, 0.0, 1.0);
	
	if (depth1 - mask.hand >= 1.0) { exit(); return; }
	
	
	vec3 diffuse = GetDiffuse(texcoord);
	vec3 viewSpacePosition0 = CalculateViewSpacePosition(vec3(texcoord, depth0));
	
	mat2x3 backPos;
	backPos[0] = CalculateViewSpacePosition(vec3(texcoord, depth1));
	backPos[1] = mat3(gbufferModelViewInverse) * backPos[0];
	
	
	vec3 composite  = CalculateShadedFragment(mask, torchLightmap, skyLightmap, GI, normal, smoothness, backPos);
	     composite *= pow(diffuse, vec3(2.8));
	     composite  = LightDesaturation(composite, vec2(torchLightmap, skyLightmap));
	
	if (mask.water > 0.5 || isEyeInWater == 1)
		composite = WaterFog(composite, waterNormal, viewSpacePosition0, backPos[0]);
	
	composite += AerialPerspective(length(backPos[0]), skyLightmap) * (1.0 - mask.water);
	
	gl_FragData[0] = vec4(max0(composite), 1.0);
	
	exit();
}
