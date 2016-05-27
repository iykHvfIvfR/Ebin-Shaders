#version 410 compatibility
#define gbuffers_textured_lit
#define fsh
#define ShaderStage -1
#include "/lib/Syntax.glsl"


/* DRAWBUFFERS:2305 */

uniform sampler2D texture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform sampler2D noisetex;
uniform sampler2D shadowtex1;
uniform sampler2DShadow shadow;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;

uniform float frameTimeCounter;
uniform float far;
uniform float wetness;

uniform float viewWidth;
uniform float viewHeight;

varying mat4 shadowView;
#define shadowModelView shadowView

varying vec3 color;
varying vec2 texcoord;
varying vec2 lightmapCoord;

varying vec3 vertNormal;
varying mat3 tbnMatrix;
varying vec2 vertLightmap;

varying float mcID;
varying float materialIDs;
varying vec4  materialIDs1;

varying vec4 viewSpacePosition;
varying vec3 worldPosition;

#include "/lib/MenuInitializer.glsl"
#include "/lib/Settings.glsl"
#include "/lib/Util.glsl"
#include "/lib/DebugSetup.glsl"
#include "/lib/CalculateFogFactor.glsl"
#include "/lib/Masks.glsl"
#ifdef FORWARD_SHADING
#include "/lib/GlobalCompositeVariables.glsl"
#include "/lib/ShadingFunctions.fsh"
#endif


vec4 GetDiffuse() {
	vec4 diffuse = vec4(color.rgb, 1.0);
	     diffuse *= texture2D(texture, texcoord);
	
	return diffuse;
}

vec4 GetNormal() {
	vec4 normal     = texture2D(normals, texcoord);
		 normal.xyz = normalize((normal.xyz * 2.0 - 1.0) * tbnMatrix);
	
	return normal;
}

void DoWaterFragment() {
	gl_FragData[0] = vec4(0.0, 0.0, 0.0, 0.11);
}

vec2 GetSpecularity(in float height, in float skyLightmap) {
	vec2 specular = texture2D(specular, texcoord).rg;
	
	float smoothness = specular.r;
	float metalness = specular.g;
	
	float wetfactor = wetness * pow(skyLightmap, 10.0);
	
	smoothness *= 1.0 + wetfactor;
	smoothness += (wetfactor - 0.5) * wetfactor;
	smoothness += (1 - height) * 0.5 * wetfactor;
	
	smoothness = clamp01(smoothness);
	
	return vec2(smoothness, metalness);
}


void main() {
	if (CalculateFogFactor(viewSpacePosition, FOG_POWER) >= 1.0) discard;
	
	
	if (abs(materialIDs - 4.0) < 0.5) { DoWaterFragment(); return; }
	
	vec4 diffuse     = GetDiffuse();    if (diffuse.a < 0.1000003) discard; // Non-transparent surfaces will be invisible if their alpha is less than ~0.1000004. This basically throws out invisible leaf and tall grass fragments.
	vec4 normal      = GetNormal();
	vec2 specularity = GetSpecularity(normal.a, vertLightmap.t);	
	
	
	float encodedMaterialIDs = EncodeMaterialIDs(materialIDs, specularity.g, materialIDs1.g, materialIDs1.b, materialIDs1.a);
	
	
	#ifdef DEFERRED_SHADING
		vec3 Colortex3 = vec3(Encode8to32(vertLightmap.s, vertLightmap.t, encodedMaterialIDs),
		                      Encode8to32(specularity.r, 0.0, 0.0), 0.0);
		
		gl_FragData[0] = vec4(pow(diffuse.rgb, vec3(2.2)) * 0.05, diffuse.a);
		gl_FragData[1] = vec4(Colortex3.rgb, 1.0);
		gl_FragData[2] = vec4(EncodeNormal(normal.xyz), 0.0, 1.0);
	#else
		Mask mask; mask.materialIDs = encodedMaterialIDs;
		CalculateMasks(mask);
		
		float sunlight;
		
		vec3 composite = CalculateShadedFragment(pow(diffuse.rgb, vec3(2.2)), mask, vertLightmap.r, vertLightmap.g, normal.xyz, specularity.r, viewSpacePosition, sunlight);
		
		vec3 Colortex3 = vec3(Encode8to32(vertLightmap.s, vertLightmap.t, encodedMaterialIDs),
		                      Encode8to32(specularity.r, sunlight, 0.0), 0.0);
		
		gl_FragData[0] = vec4(EncodeColor(composite), diffuse.a);
		gl_FragData[1] = vec4(Colortex3.rgb, 1.0);
		gl_FragData[2] = vec4(EncodeNormal(normal.xyz).xy, 0.0, 1.0);
		gl_FragData[3] = vec4(diffuse.rgb, 1.0);
	#endif
	
	exit();
}