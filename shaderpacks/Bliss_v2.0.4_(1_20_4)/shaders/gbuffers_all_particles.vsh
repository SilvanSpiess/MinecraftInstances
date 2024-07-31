// #version 120
//#extension GL_EXT_gpu_shader4 : disable
#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

varying vec4 lmtexcoord;
varying vec4 color;
varying vec4 normalMat;

#ifdef MC_NORMAL_MAP
	varying vec4 tangent;
	attribute vec4 at_tangent;
	varying vec3 FlatNormals; 
#endif

flat varying vec3 WsunVec;
flat varying vec4 lightCol; //main light source color (rgb),used light source(1=sun,-1=moon)

flat varying vec3 averageSkyCol_Clouds;
// flat varying vec3 averageSkyCol;

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform float sunElevation;
uniform sampler2D colortex4;

uniform int frameCounter;
uniform float far;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform int hideGUI;
uniform float screenBrightness;

uniform vec2 texelSize;
uniform int framemod8;
		const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
									vec2(-1.,3.)/8.,
									vec2(5.0,1.)/8.,
									vec2(-3,-5.)/8.,
									vec2(-5.,5.)/8.,
									vec2(-7.,-1.)/8.,
									vec2(3,7.)/8.,
									vec2(7.,-7.)/8.);
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	lmtexcoord.xy = (gl_MultiTexCoord0).xy;

	vec2 lmcoord = gl_MultiTexCoord1.xy/255.;
	lmtexcoord.zw = lmcoord;

	gl_Position = ftransform();
	color = gl_Color;

	averageSkyCol_Clouds = texelFetch2D(colortex4,ivec2(0,37),0).rgb;
	// averageSkyCol = texelFetch2D(colortex4,ivec2(1,37),0).rgb;

	vec3 sc = texelFetch2D(colortex4,ivec2(6,37),0).rgb;
	lightCol.a = float(sunElevation > 1e-5)*2-1.;
	lightCol.rgb = sc;

	WsunVec = lightCol.a*normalize(mat3(gbufferModelViewInverse) *sunPosition);


	FlatNormals = normalize(gl_NormalMatrix *gl_Normal);

	#ifdef MC_NORMAL_MAP
		tangent = vec4(normalize(gl_NormalMatrix *at_tangent.rgb),at_tangent.w);
	#endif

	normalMat = vec4(normalize(gl_NormalMatrix *gl_Normal),1.0);
	
	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	#ifdef TAA
	gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
	#endif

	#if DOF_QUALITY == 5
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(radians(float(frameCounter))) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if MANUAL_FOCUS == -2
		float focusMul = 0;
		#elif MANUAL_FOCUS == -1
		float focusMul = gl_Position.z - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
		float focusMul = gl_Position.z - MANUAL_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}
