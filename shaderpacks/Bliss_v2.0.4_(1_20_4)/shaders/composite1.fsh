#version 120
//Render sky, volumetric clouds, direct lighting
//#extension GL_EXT_gpu_shader4 : disable

#include "/lib/settings.glsl"

const bool colortex5MipmapEnabled = true;
const bool colortex12MipmapEnabled = true;

// #ifndef Rough_reflections
	// const bool colortex4MipmapEnabled = true;
// #endif

const bool shadowHardwareFiltering = true;

flat varying vec3 averageSkyCol_Clouds;
flat varying vec4 lightCol;

flat varying vec3 WsunVec;
flat varying vec2 TAA_Offset;


uniform float eyeAltitude;

flat varying vec3 zMults;
uniform sampler2D colortex0;//clouds
uniform sampler2D colortex1;//albedo(rgb),material(alpha) RGBA16
// uniform sampler2D colortex4;//Skybox
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex7; // normal
uniform sampler2D colortex6; // Noise
uniform sampler2D colortex8; // specular
// uniform sampler2D colortex9; // specular
uniform sampler2D colortex11; // specular
uniform sampler2D colortex10; // specular
uniform sampler2D colortex12; // specular
uniform sampler2D colortex13; // specular
uniform sampler2D colortex14; 
uniform sampler2D colortex15; // specular
uniform sampler2D colortex16; // specular
uniform sampler2D depthtex1;//depth
uniform sampler2D depthtex0;//depth
uniform sampler2D noisetex;//depth
uniform sampler2DShadow shadow;
varying vec4 normalMat;
uniform int heldBlockLightValue;
uniform int frameCounter;
uniform int isEyeInWater;
uniform float far;
uniform float near;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelView;
// uniform float viewWidth;
// uniform float viewHeight;
uniform int hideGUI;
uniform float aspectRatio;
uniform vec2 texelSize;
uniform vec3 cameraPosition;
uniform vec3 sunVec;
uniform ivec2 eyeBrightnessSmooth;
uniform ivec2 eyeBrightness;

uniform float screenBrightness;
flat varying vec2 rodExposureDepth;

flat varying float WinterTimeForSnow;

// uniform int worldTime;                    

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)

#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)


vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}

vec3 toScreenSpacePrev(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
vec3 worldToView(vec3 p3) {
    vec4 pos = vec4(p3, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}


float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}
vec3 ld(vec3 dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}
vec3 srgbToLinear2(vec3 srgb){
    return mix(
        srgb / 12.92,
        pow(.947867 * srgb + .0521327, vec3(2.4) ),
        step( .04045, srgb )
    );
}
vec3 blackbody2(float Temp)
{
    float t = pow(Temp, -1.5);
    float lt = log(Temp);

    vec3 col = vec3(0.0);
         col.x = 220000.0 * t + 0.58039215686;
         col.y = 0.39231372549 * lt - 2.44549019608;
         col.y = Temp > 6500. ? 138039.215686 * t + 0.72156862745 : col.y;
         col.z = 0.76078431372 * lt - 5.68078431373;
         col = clamp(col,0.0,1.0);
         col = Temp < 1000. ? col * Temp * 0.001 : col;

    return srgbToLinear2(col);
}

vec3 normVec (vec3 vec){
	return vec*inversesqrt(dot(vec,vec));
}
vec3 viewToWorld(vec3 viewPosition) {
    vec4 pos;
    pos.xyz = viewPosition;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}


#include "/lib/res_params.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/color_transforms.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/stars.glsl"
#include "/lib/volumetricClouds.glsl"
#include "/lib/waterBump.glsl"

#define OVERWORLD_SHADER
#include "/lib/specular.glsl"
#include "/lib/diffuse_lighting.glsl"

float lengthVec (vec3 vec){
	return sqrt(dot(vec,vec));
}
#define fsign(a)  (clamp((a)*1e35,0.,1.)*2.-1.)
float triangularize(float dither)
{
    float center = dither*2.0-1.0;
    dither = center*inversesqrt(abs(center));
    return clamp(dither-fsign(center),0.0,1.0);
}


float interleaved_gradientNoise(){
	// vec2 coord = gl_FragCoord.xy + (frameCounter%40000);
	vec2 coord = gl_FragCoord.xy + (frameCounter%40000);
	// vec2 coord = gl_FragCoord.xy;
	float noise = fract( 52.9829189 * fract( (coord.x * 0.06711056) + (coord.y * 0.00583715)) );
	return noise ;
}

vec2 R2_dither(){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return vec2(fract(alpha.x * gl_FragCoord.x + alpha.y * gl_FragCoord.y + 1.0/1.6180339887 * (frameCounter%40000)), fract((1.0-alpha.x) * gl_FragCoord.x + (1.0-alpha.y) * gl_FragCoord.y + 1.0/1.6180339887 * frameCounter));
}
float blueNoise(){
  return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * (frameCounter%40000)	);
}
vec4 blueNoise(vec2 coord){
  return texelFetch2D(colortex6, ivec2(coord)%512, 0) ;
}
vec3 fp10Dither(vec3 color,float dither){
	const vec3 mantissaBits = vec3(6.,6.,5.);
	vec3 exponent = floor(log2(color));
	return color + dither*exp2(-mantissaBits)*exp2(exponent);
}

vec3 decode (vec2 encn){
    vec3 n = vec3(0.0);
    encn = encn * 2.0 - 1.0;
    n.xy = abs(encn);
    n.z = 1.0 - n.x - n.y;
    n.xy = n.z <= 0.0 ? (1.0 - n.yx) * sign(encn) : encn;
    return clamp(normalize(n.xyz),-1.0,1.0);
}


vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}


vec2 tapLocation(int sampleNumber,int nb, float nbRot,float jitter,float distort){
	float alpha0 = sampleNumber/nb;
    float alpha = (sampleNumber+jitter)/nb;
    float angle = jitter*6.28 + alpha * 84.0 * 6.28;

    float sin_v, cos_v;

	sin_v = sin(angle);
	cos_v = cos(angle);

    return vec2(cos_v, sin_v)*sqrt(alpha);
}
vec3 toShadowSpaceProjected(vec3 p3){
    p3 = mat3(gbufferModelViewInverse) * p3 + gbufferModelViewInverse[3].xyz;
    p3 = mat3(shadowModelView) * p3 + shadowModelView[3].xyz;
    p3 = diagonal3(shadowProjection) * p3 + shadowProjection[3].xyz;
    return p3;
}

vec2 R2_samples(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

vec2 tapLocation(int sampleNumber, float spinAngle,int nb, float nbRot,float r0){
    float alpha = (float(sampleNumber*1.0f + r0) * (1.0 / (nb)));
    float angle = alpha * (nbRot * 3.14) + spinAngle*3.14;

    float ssR = alpha;
    float sin_v, cos_v;

	sin_v = sin(angle);
	cos_v = cos(angle);

    return vec2(cos_v, sin_v)*ssR;
}


void waterVolumetrics(inout vec3 inColor, vec3 rayStart, vec3 rayEnd, float estEndDepth, float estSunDepth, float rayLength, float dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient, vec3 lightSource, float VdotL){
		inColor *= exp(-rayLength * waterCoefs);	//No need to take the integrated value
		int spCount = rayMarchSampleCount;
		vec3 start = toShadowSpaceProjected(rayStart);
		vec3 end = toShadowSpaceProjected(rayEnd);
		vec3 dV = (end-start);
		//limit ray length at 32 blocks for performance and reducing integration error
		//you can't see above this anyway
		float maxZ = min(rayLength,12.0)/(1e-8+rayLength);
		dV *= maxZ;


		rayLength *= maxZ;
		
		float dY = normalize(mat3(gbufferModelViewInverse) * rayEnd).y * rayLength;
		estEndDepth *= maxZ;
		estSunDepth *= maxZ;

		vec3 wpos = mat3(gbufferModelViewInverse) * rayStart  + gbufferModelViewInverse[3].xyz;
		vec3 dVWorld = (wpos-gbufferModelViewInverse[3].xyz);

		// float phase = (phaseg(VdotL,0.5) + phaseg(VdotL,0.8)) ;
		float phase = (phaseg(VdotL,0.6) + phaseg(VdotL,0.8)) * 0.5;
		// float phase = phaseg(VdotL, 0.7);
		
		vec3 absorbance = vec3(1.0);
		vec3 vL = vec3(0.0);

		float expFactor = 11.0;
		for (int i=0;i<spCount;i++) {
			float d = (pow(expFactor, float(i+dither)/float(spCount))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
			float dd = pow(expFactor, float(i+dither)/float(spCount)) * log(expFactor) / float(spCount)/(expFactor-1.0);
			vec3 spPos = start.xyz + dV*d;

			vec3 progressW = start.xyz+cameraPosition+dVWorld;

			//project into biased shadowmap space
			float distortFactor = calcDistort(spPos.xy);
			vec3 pos = vec3(spPos.xy*distortFactor, spPos.z);
			float sh = 1.0;
			if (abs(pos.x) < 1.0-0.5/2048. && abs(pos.y) < 1.0-0.5/2048){
				pos = pos*vec3(0.5,0.5,0.5/6.0)+0.5;
				sh =  shadow2D( shadow, pos).x;
			}

			#ifdef VL_CLOUDS_SHADOWS
				sh *= GetCloudShadow_VLFOG(progressW,WsunVec);
			#endif

			vec3 sunMul = exp(-max(estSunDepth * d,0.0) * waterCoefs) * 5.0;
			vec3 ambientMul = exp(-max(estEndDepth * d,0.0) * waterCoefs );

			vec3 Directlight = (lightSource * phase * sunMul) * sh;
			vec3 Indirectlight = ambientMul*ambient;

			vec3 light = (Directlight + Indirectlight) * scatterCoef;

			vL += (light - light * exp(-waterCoefs * dd * rayLength)) / waterCoefs * absorbance;
			absorbance *= exp(-dd * rayLength * waterCoefs);
		}
		inColor += vL;
}

float waterCaustics(vec3 wPos, vec3 lightSource) { // water waves

	vec2 pos = wPos.xz + (lightSource.xz/lightSource.y*wPos.y);
	if(isEyeInWater==1) pos = wPos.xz - (lightSource.xz/lightSource.y*wPos.y); // fix the fucky
	vec2 movement = vec2(-0.035*frameTimeCounter);
	float caustic = 0.0;
	float weightSum = 0.0;
	float radiance =  2.39996;
	mat2 rotationMatrix  = mat2(vec2(cos(radiance),  -sin(radiance)),  vec2(sin(radiance),  cos(radiance)));

	const vec2 wave_size[4] = vec2[](
		vec2(64.),
		vec2(32.,16.),
		vec2(16.,32.),
		vec2(48.)
	);

	for (int i = 0; i < 4; i++){
		pos = rotationMatrix * pos;

		vec2 speed = movement;
		float waveStrength = 1.0;

		if( i == 0) {
			speed *= 0.15;
			waveStrength = 2.0;
		}

		float small_wave = texture2D(noisetex, pos / wave_size[i] + speed ).b * waveStrength;

		caustic +=  max( 1.0-sin( 1.0-pow(	0.5+sin( small_wave*3.0	)*0.5,	25.0)	),	0);

		weightSum -= exp2(caustic*0.1);
	}
	return caustic / weightSum;
}


float rayTraceShadow(vec3 dir,vec3 position,float dither, bool outsideShadowMap){
    const float quality = 16.;
    vec3 clipPosition = toClipSpace3(position);
	//prevents the ray from going behind the camera
	float rayLength = ((position.z + dir.z * far*sqrt(3.)) > -near) ?
      					 (-near -position.z) / dir.z : far*sqrt(3.) ;
    vec3 direction = toClipSpace3(position+dir*rayLength)-clipPosition;  //convert to clip space
    direction.xyz = direction.xyz/max(abs(direction.x)/texelSize.x,abs(direction.y)/texelSize.y);	//fixed step size
    vec3 stepv = direction * 3.0 * clamp(MC_RENDER_QUALITY,1.,2.0)*vec3(RENDER_SCALE,1.0);
	
	vec3 spos = clipPosition*vec3(RENDER_SCALE,1.0);
	
	// this is to remove the "peterpanning" on things outside the shadowmap with SSS
	if(outsideShadowMap){
		spos += stepv*dither - stepv*0.9;
	}else{
		spos += stepv*dither ;
	} 


	for (int i = 0; i < int(quality); i++) {
		spos += stepv;
		
		float sp = texture2D(depthtex1,spos.xy).x;
	
        if( sp < spos.z) {
			float dist = abs(linZ(sp)-linZ(spos.z))/linZ(spos.z);
			if (dist < 0.015 ) return i / quality;
		}
	}
    return 1.0;
}

vec2 tapLocation_alternate(
	int sampleNumber, 
	float spinAngle,
	int nb, 
	float nbRot,
	float r0
){
    float alpha = (float(sampleNumber*1.0f + r0) * (1.0 / (nb)));
    float angle = alpha * (nbRot * 3.14) ;

    float ssR = alpha + spinAngle*3.14;
    float sin_v, cos_v;

	sin_v = sin(angle);
	cos_v = cos(angle);

    return vec2(cos_v, sin_v)*ssR;
}


void ssAO(inout vec3 lighting, inout float sss, vec3 fragpos,float mulfov, vec2 noise, vec3 normal, vec2 texcoord, vec3 ambientCoefs, vec2 lightmap, bool isleaves){

	ivec2 pos = ivec2(gl_FragCoord.xy);
	const float tan70 = tan(70.*3.14/180.);

	float dist = 1.0 + clamp(fragpos.z*fragpos.z/50.0,0,2); // shrink sample size as distance increases
	float mulfov2 = gbufferProjection[1][1]/(tan70  * dist);
	float maxR2 = fragpos.z*fragpos.z*mulfov2*2.*5/50.0;

	#ifdef Ambient_SSS
		// float dist3 = clamp(1.0 - exp( fragpos.z*fragpos.z / -50),0,1);
		// float maxR2_2 = mix(10.0, fragpos.z*fragpos.z*mulfov2*2./50.0, dist3);

		float maxR2_2 = fragpos.z*fragpos.z*mulfov2*2./50.0;
		float dist3 = clamp(1-exp( fragpos.z*fragpos.z / -50),0,1);
		if(isleaves) maxR2_2 = mix(10, maxR2_2, dist3);
	#endif
	
	float rd = mulfov2 * 0.1 ;

	vec2 acc = -(TAA_Offset*(texelSize/2))*RENDER_SCALE ;

	int seed = (frameCounter%40000)*2 + (1+frameCounter);
	float randomDir = fract(R2_samples(seed).y + noise.x ) * 1.61803398874 ;

	float n = 0.0;
	float occlusion = 0.0;
	for (int j = 0; j < 7; j++) {
		
		vec2 sp = tapLocation_alternate(j, 0.0, 7, 20, randomDir);

		vec2 sampleOffset = sp*rd;
		ivec2 offset = ivec2(gl_FragCoord.xy + sampleOffset*vec2(viewWidth,viewHeight*aspectRatio)*RENDER_SCALE);

		if (offset.x >= 0 && offset.y >= 0 && offset.x < viewWidth*RENDER_SCALE.x && offset.y < viewHeight*RENDER_SCALE.y ) {
			vec3 t0 = toScreenSpace(vec3(offset*texelSize+acc+0.5*texelSize,texelFetch2D(depthtex1,offset,0).x) * vec3(1.0/RENDER_SCALE, 1.0) );
			vec3 vec = (t0.xyz - fragpos);
			float dsquared = dot(vec,vec) ;


			if (dsquared > 1e-5){
				if (dsquared < maxR2){
					float NdotV = clamp(dot(vec*inversesqrt(dsquared), normalize(normal)),0.,1.);
					occlusion += NdotV * clamp(1.0-dsquared/maxR2,0.0,1.0);
				}
				
				#ifdef Ambient_SSS
					if(dsquared > maxR2_2){
						float NdotV = 1.0 - clamp(dot(vec*dsquared, normalize(normal)),0.,1.);
						sss += max((NdotV - (1.0-NdotV)) * clamp(1.0-maxR2_2/dsquared,0.0,1.0) ,0.0);
					}
				#endif

				n += 1;
			}
		}
	}

	#ifdef Ambient_SSS
		sss = max(1.0 - sss/n, 0.0) ;
	#endif
	occlusion *= AO_Strength;
	occlusion *= 2.0;
	occlusion = max(1.0 - occlusion/n, 0.0);


	lighting = lighting*max(occlusion,pow(lightmap.x,4));
}

vec3 rayTrace_GI(vec3 dir,vec3 position,float dither, float quality){

	vec3 clipPosition = toClipSpace3(position);
	float rayLength = ((position.z + dir.z * far*sqrt(3.)) > -near) ?
	                   (-near -position.z) / dir.z : far*sqrt(3.);
	vec3 direction = normalize(toClipSpace3(position+dir*rayLength)-clipPosition);  //convert to clip space
	direction.xy = normalize(direction.xy);

	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.,direction)-clipPosition) / direction;
	float mult = maxLengths.y;

	vec3 stepv = direction * mult / quality*vec3(RENDER_SCALE,1.0) * dither;
	vec3 spos = clipPosition*vec3(RENDER_SCALE,1.0) ;

	spos.xy += TAA_Offset*texelSize*0.5/RENDER_SCALE;

	float biasdist =  clamp(position.z*position.z/50.0,1,2); // shrink sample size as distance increases

	for(int i = 0; i < int(quality); i++){
		spos += stepv;
		float sp = sqrt(texelFetch2D(colortex4,ivec2(spos.xy/texelSize/4),0).w/65000.0);
		float currZ = linZ(spos.z);

		if( sp < currZ) {
			float dist = abs(sp-currZ)/currZ;
			if (abs(dist) < biasdist*0.05) return vec3(spos.xy, invLinZ(sp))/vec3(RENDER_SCALE,1.0);
		}
		spos += stepv;
	}
  return vec3(1.1);
}
vec3 RT(vec3 dir, vec3 position, float noise, float stepsizes){
	float dist = 1.0 + clamp(position.z*position.z/50.0,0,2); // shrink sample size as distance increases

	float stepSize = stepsizes / dist;
	int maxSteps = STEPS;
	vec3 clipPosition = toClipSpace3(position);
	float rayLength = ((position.z + dir.z * sqrt(3.0)*far) > -sqrt(3.0)*near) ?
	   								(-sqrt(3.0)*near -position.z) / dir.z : sqrt(3.0)*far;
	vec3 end = toClipSpace3(position+dir*rayLength) ;
	vec3 direction = end-clipPosition ;  //convert to clip space

	float len = max(abs(direction.x)/texelSize.x,abs(direction.y)/texelSize.y)/stepSize;
	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.,direction)-clipPosition) / direction;
	
	float mult = min(min(maxLengths.x,maxLengths.y),maxLengths.z)*2000.0;

	vec3 stepv = direction/len;

	int iterations = min(int(min(len, mult*len)-2), maxSteps);
	
	//Do one iteration for closest texel (good contact shadows)
	vec3 spos = clipPosition*vec3(RENDER_SCALE,1.0) ;
	spos.xy += TAA_Offset*texelSize*0.5*RENDER_SCALE;
	spos += stepv/(stepSize/2);
	
	float distancered = 1.0 + clamp(position.z*position.z/50.0,0,2); // shrink sample size as distance increases

  	for(int i = 0; i < iterations; i++){
		if (spos.x < 0.0 || spos.y < 0.0 || spos.z < 0.0 || spos.x > 1.0 || spos.y > 1.0 || spos.z > 1.0) return vec3(1.1);
		spos += stepv*noise;

		float sp = sqrt(texelFetch2D(colortex4,ivec2(spos.xy/ texelSize/4),0).w/65000.0);
		float currZ = linZ(spos.z);
		
		if( sp < currZ) {
			float dist = abs(sp-currZ)/currZ;
			if (dist <= 0.1) return vec3(spos.xy, invLinZ(sp))/vec3(RENDER_SCALE,1.0);
		}
	}
	return vec3(1.1);
}

vec3 cosineHemisphereSample(vec2 Xi, float roughness){
    float r = sqrt(Xi.x);
    float theta = 2.0 * 3.14159265359 * Xi.y;

    float x = r * cos(theta);
    float y = r * sin(theta);

    return vec3(x, y, sqrt(clamp(1.0 - Xi.x,0.,1.)));
}

vec3 TangentToWorld(vec3 N, vec3 H, float roughness){
    vec3 UpVector = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(UpVector, N));
    vec3 B = cross(N, T);

    return vec3((T * H.x) + (B * H.y) + (N * H.z));
}

void ApplySSRT(inout vec3 lighting, vec3 normal,vec2 noise,vec3 fragpos, vec2 lightmaps, vec3 skylightcolor, vec3 torchcolor, bool isGrass){
	int nrays = RAY_COUNT;

	vec3 radiance = vec3(0.0);

	vec3 occlusion = vec3(0.0);
	vec3 skycontribution = vec3(0.0);

	vec3 occlusion2 = vec3(0.0);
	vec3 skycontribution2 = vec3(0.0);
	
    float skyLM = 0.0;
	vec3 torchlight = vec3(0.0);
	DoRTAmbientLighting(torchcolor, lightmaps, skyLM, torchlight, skylightcolor);

	for (int i = 0; i < nrays; i++){
		int seed = (frameCounter%40000)*nrays+i;
		vec2 ij = fract(R2_samples(seed) + noise );

		vec3 rayDir = TangentToWorld(normal, normalize(cosineHemisphereSample(ij,1.0)) ,1.0);

		#ifdef HQ_SSGI
			vec3 rayHit = rayTrace_GI( mat3(gbufferModelView) * rayDir, fragpos,  blueNoise(), 50.); // ssr rt
		#else
			vec3 rayHit = RT(mat3(gbufferModelView)*rayDir, fragpos, blueNoise(), 30.);  // choc sspt 
		#endif

		#ifdef SKY_CONTRIBUTION_IN_SSRT
			if(isGrass) rayDir.y = clamp(rayDir.y +  0.5,-1,1);
			skycontribution = (skyCloudsFromTex(rayDir, colortex4).rgb / 15.0) * skyLM + torchlight;
		#else
			if(isGrass) rayDir.y = clamp(rayDir.y +  0.25,-1,1);
			
			skycontribution = skylightcolor * 2 * (max(rayDir.y,0.0)*0.9+0.1) + torchlight;

			#if indirect_effect == 4
				skycontribution2 = skylightcolor + torchlight;
			#endif

		#endif

		if (rayHit.z < 1.){
			
			#if indirect_effect == 4
				vec3 previousPosition = mat3(gbufferModelViewInverse) * toScreenSpace(rayHit) + gbufferModelViewInverse[3].xyz + cameraPosition-previousCameraPosition;
				previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
				previousPosition.xy = projMAD(gbufferPreviousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;
				
				if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.x < 1.0){
					radiance += (texture2D(colortex5,previousPosition.xy).rgb + skycontribution) * GI_Strength;
				} else{
					radiance += skycontribution;
				}

			#else
				radiance += skycontribution;
			#endif

			occlusion += skycontribution * GI_Strength;
			
			#if indirect_effect == 4
				occlusion2 += skycontribution2 * GI_Strength;
			#endif
				
		} else {
			radiance += skycontribution;
		}
	}
	
	occlusion *= AO_Strength;
	
	#if indirect_effect == 4
		lighting = max(radiance/nrays - max(occlusion, occlusion2*0.5)/nrays, 0.0);
	#else
		lighting = max(radiance/nrays - occlusion/nrays, 0.0);
	#endif

}


vec3 SubsurfaceScattering_sun(vec3 albedo, float Scattering, float Density, float lightPos){

	float labcurve = pow(Density,LabSSS_Curve);
	float density = sqrt(30 - labcurve*15);

	vec3 absorbed = max(1.0 - albedo,0.0);
	vec3 scatter = exp(absorbed * -sqrt(Scattering * 5)) * exp(Scattering * -density);

	scatter *= labcurve;
	scatter *= 0.5 + CustomPhase(lightPos, 1.0,30.0)*20;

	return scatter;

}

vec3 SubsurfaceScattering_sky(vec3 albedo, float Scattering, float Density){

	vec3 absorbed = max(luma(albedo) - albedo,0.0);
	vec3 scatter =   sqrt(exp(-(absorbed * Scattering * 15))) * (1.0 - Scattering);

	// scatter *= pow(Density,LabSSS_Curve);
	scatter *= clamp(1 - exp(Density * -10),0,1);

	return scatter;
}

void ScreenSpace_SSS(inout float sss, vec3 fragpos, vec2 noise, vec3 normal, bool isleaves){
	ivec2 pos = ivec2(gl_FragCoord.xy);
	const float tan70 = tan(70.*3.14/180.);

	float dist = 1.0 + (clamp(fragpos.z*fragpos.z/50.0,0,2)); // shrink sample size as distance increases
	float mulfov2 = gbufferProjection[1][1]/(tan70 * dist);

	float maxR2_2 = fragpos.z*fragpos.z*mulfov2*2./50.0;

	float dist3 = clamp(1-exp( fragpos.z*fragpos.z / -50),0,1);
	if(isleaves) maxR2_2 = mix(10, maxR2_2, dist3);

	float rd = mulfov2 * 0.1;


	vec2 acc = -(TAA_Offset*(texelSize/2))*RENDER_SCALE ;

	int seed = (frameCounter%40000)*2 + (1+frameCounter);
	float randomDir = fract(R2_samples(seed).y + noise.x ) * 1.61803398874 ;

	float n = 0.0;
	for (int j = 0; j < 7 ;j++) {
		
		vec2 sp = tapLocation_alternate(j, 0.0, 7, 20, randomDir);
		vec2 sampleOffset = sp*rd;
		ivec2 offset = ivec2(gl_FragCoord.xy + sampleOffset*vec2(viewWidth,viewHeight*aspectRatio)*RENDER_SCALE);

		if (offset.x >= 0 && offset.y >= 0 && offset.x < viewWidth*RENDER_SCALE.x && offset.y < viewHeight*RENDER_SCALE.y ) {
			vec3 t0 = toScreenSpace(vec3(offset*texelSize+acc+0.5*texelSize,texelFetch2D(depthtex1,offset,0).x) * vec3(1.0/RENDER_SCALE, 1.0) );
			vec3 vec = t0.xyz - fragpos;
			float dsquared = dot(vec,vec);

			if (dsquared > 1e-5){
				if(dsquared > maxR2_2){
					float NdotV = 1.0 - clamp(dot(vec*dsquared, normalize(normal)),0.,1.);
					sss += max((NdotV - (1.0-NdotV)) * clamp(1.0-maxR2_2/dsquared,0.0,1.0) ,0.0);
				}
				n += 1;
			}
		}
	}
	sss = max(1.0 - sss/n, 0.0);
}


float densityAtPosSNOW(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	f = (f*f) * (3.-2.*f);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture2D(noisetex, coord).yx;
	return mix(xy.r,xy.g, f.y);
}

// Emin's and Gri's combined ideas to stop peter panning and light leaking, also has little shadowacne so thats nice
// https://www.complementary.dev/reimagined
// https://github.com/gri573
void GriAndEminShadowFix(
	inout vec3 WorldPos,
	vec3 FlatNormal,
	float VanillaAO,
	float SkyLightmap,
	bool Entities
){

	float DistanceOffset = clamp(0.1 + length(WorldPos) / (shadowMapResolution*0.20), 0.0,1.0) ;
	vec3 Bias = FlatNormal * DistanceOffset; // adjust the bias thingy's strength as it gets farther away.
	
	vec3 finalBias = Bias;

	// stop lightleaking
	vec2 scale = vec2(0.5); scale.y *= 0.5;
	vec3 zoomShadow =  scale.y - scale.x * fract(WorldPos + cameraPosition + Bias*scale.y);
	if(SkyLightmap < 0.1 && !Entities) finalBias = mix(Bias, zoomShadow, clamp(VanillaAO*5,0,1));

	WorldPos += finalBias;
}

void Emission(
	inout vec3 Lighting,
	vec3 Albedo,
	float Emission
){
	// if( Emission < 255.0/255.0 ) Lighting = mix(Lighting, Albedo * Emissive_Brightness, pow(Emission, Emissive_Curve)); // old method.... idk why
	if( Emission < 255.0/255.0 ) Lighting += (Albedo * Emissive_Brightness) * pow(Emission, Emissive_Curve);
}

vec3 Moon(vec3 PlayerPos, vec3 WorldSunVec, vec3 Color, inout vec3 occludeStars){

	float Shape = clamp((exp(1 + -1000 * dot(WorldSunVec+PlayerPos,PlayerPos)) - 1.5),0.0,25.0);
	occludeStars *= max(1.0-Shape*5,0.0);

	float shape2 = pow(exp(Shape * -10),0.15) * 255.0;

	vec3 sunNormal = vec3(dot(WorldSunVec+PlayerPos, vec3(shape2,0,0)), dot(PlayerPos+WorldSunVec, vec3(0,shape2,0)), -dot(WorldSunVec, PlayerPos) * 15.0);


	// even has a little tilt approximation haha.... yeah....
	vec3[8] phase = vec3[8](vec3( -1.0,	 -0.5,	 1.0	),
							vec3( -1.0,	 -0.5,	 0.35	),
							vec3( -1.0,	 -0.5,   0.2	),
							vec3( -1.0,	 -0.5,   0.1	),
							vec3(  1.0,	 0.25,	-1.0	),
							vec3(  1.0,	 0.25,	 0.1	),
							vec3(  1.0,	 0.25,	 0.2	),
							vec3(  1.0,	 0.25,	 0.35	)
	);
	
	vec3 LightDir = phase[moonPhase];

	return Shape * pow(clamp(dot(sunNormal,LightDir)/5,0.0,1.5),5) * Color  + clamp(Shape * 4.0 * pow(shape2/200,2.0),0.0,1.0)*0.004;
}

vec3 applyContrast(vec3 color, float contrast){
  return (color - 0.5) * contrast + 0.5;
}


#include "/lib/PhotonGTAO.glsl"

uniform float detectThunderStorm;
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
void main() {

	vec2 texcoord = gl_FragCoord.xy*texelSize;

	float z0 = texture2D(depthtex0,texcoord).x;
	float z = texture2D(depthtex1,texcoord).x;
    float TranslucentDepth = clamp( ld(z0)-ld(z0),0.0,1.0);

	vec2 tempOffset=TAA_Offset;
	vec3 fragpos = toScreenSpace(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z));
	vec3 fragpos_rtshadow = toScreenSpace(vec3(texcoord/RENDER_SCALE,z));
	vec3 fragpos_handfix = fragpos;

	if ( z < 0.56) fragpos_handfix.z /= MC_HAND_DEPTH; // fix lighting on hand
	
	vec3 p3 = mat3(gbufferModelViewInverse) * fragpos;
	vec3 np3 = normVec(p3);

	p3 += gbufferModelViewInverse[3].xyz;


	float dirtAmount = Dirt_Amount;
	vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);

	vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
	vec3 totEpsilon = dirtEpsilon*dirtAmount + waterEpsilon;
	vec3 scatterCoef = dirtAmount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / pi;

	#ifdef AEROCHROME_MODE
		totEpsilon *= 10.0;
		scatterCoef *= 0.1;
	#endif

	float noise = blueNoise();

	float iswaterstuff = texture2D(colortex7,texcoord).a ;
	bool iswater = iswaterstuff > 0.99;

	////// --------------- UNPACK OPAQUE GBUFFERS --------------- //////
	vec4 data = texture2D(colortex1,texcoord);
	vec4 dataUnpacked0 = vec4(decodeVec2(data.x),decodeVec2(data.y)); // albedo, masks
	vec4 dataUnpacked1 = vec4(decodeVec2(data.z),decodeVec2(data.w)); // normals, lightmaps
	// vec4 dataUnpacked2 = vec4(decodeVec2(data.z),decodeVec2(data.w));
	
	vec3 albedo = toLinear(vec3(dataUnpacked0.xz,dataUnpacked1.x));
	vec2 lightmap = dataUnpacked1.yz;
	vec3 normal = decode(dataUnpacked0.yw);
	

	////// --------------- UNPACK TRANSLUCENT GBUFFERS --------------- //////
	// vec4 dataTranslucent = texture2D(colortex11,texcoord); 
	// vec4 dataT_Unpacked0 = vec4(decodeVec2(dataTranslucent.x),decodeVec2(dataTranslucent.y));
	// vec4 dataT_Unpacked1 = vec4(decodeVec2(dataTranslucent.z),decodeVec2(dataTranslucent.w));
	// vec4 dataT_Unpacked2 = vec4(decodeVec2(dataTranslucent.z),decodeVec2(dataTranslucent.w));

	////// --------------- UNPACK MISC --------------- //////
	vec4 SpecularTex = texture2D(colortex8,texcoord);
	float LabSSS = clamp((-64.0 + SpecularTex.z * 255.0) / 191.0 ,0.0,1.0);

	vec4 normalAndAO = texture2D(colortex15,texcoord);
	vec3 FlatNormals = normalAndAO.rgb * 2.0 - 1.0;
	vec3 slopednormal = normal;

	#ifdef POM
		#ifdef Horrible_slope_normals
    		vec3 ApproximatedFlatNormal = normalize(cross(dFdx(p3), dFdy(p3))); // it uses depth that has POM written to it.
			slopednormal = normalize(clamp(normal, ApproximatedFlatNormal*2.0 - 1.0, ApproximatedFlatNormal*2.0 + 1.0) );
		#endif
	#endif

	// masks
	bool isLeaf = abs(dataUnpacked1.w-0.55) <0.01;
	bool lightningBolt = abs(dataUnpacked1.w-0.50) <0.01;
	bool entities = abs(dataUnpacked1.w-0.45) < 0.01;	
	bool hand = abs(dataUnpacked1.w-0.75) < 0.01;
	// bool blocklights = abs(dataUnpacked1.w-0.8) <0.01;
	bool isGrass = abs(dataUnpacked1.w-0.60) < 0.01;

	float vanilla_AO = normalAndAO.a;

	vec3 filtered = vec3(1.412,1.0,0.0);
	if (!hand) filtered = texture2D(colortex3,texcoord).rgb;

	vec3 ambientCoefs = slopednormal/dot(abs(slopednormal),vec3(1.));

	vec3 DirectLightColor = lightCol.rgb/80.0;
	vec3 Direct_SSS = vec3(0.0);

	#ifdef ambientLight_only
		DirectLightColor = vec3(0.0);
	#endif

	#ifdef OLD_LIGHTLEAK_FIX
		DirectLightColor *= pow(clamp(eyeBrightnessSmooth.y/240. + lightmap.y,0.0,1.0),2.0);
	#else
		if(hand) DirectLightColor *= pow(clamp(eyeBrightnessSmooth.y/240. + lightmap.y,0.0,1.0),2.0);
	#endif
	
	int shadowmapindicator = 0;
	float cloudShadow = 1.0;

	vec3 AmbientLightColor = averageSkyCol_Clouds;
	vec3 Indirect_SSS = vec3(0.0);

	vec3 debug = vec3(0.0);

	if ( z >= 1.) {//sky
	
	////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	SKY STUFF	////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////

	#ifdef Compositing_Sky

		gl_FragData[0].rgb = vec3(CompSky_R, CompSky_G, CompSky_B);

	#else

		vec3 background = vec3(0.0);
		vec3 orbitstar = vec3(np3.x,abs(np3.y),np3.z);
		orbitstar.x -= WsunVec.x*0.2; 
		background += stars(orbitstar) * 10.0	;

		#ifndef ambientLight_only
			background += Moon(np3, -WsunVec, DirectLightColor*20, background); // moon
			background += drawSun(dot(lightCol.a * WsunVec, np3),0, DirectLightColor,vec3(0.0)) ; // sun 
			// vec3 moon = drawSun(dot(lightCol.a * -WsunVec, np3),0, DirectLightColor/5,vec3(0.0)) ; // moon
		#endif
		
		background *= clamp( (np3.y+ 0.02)*5.0 + (eyeAltitude - 319)/800000  ,0.0,1.0);

		vec3 skyTEX = skyFromTex(np3,colortex4)/150.0 * 5.0;
		background += skyTEX;

		vec4 cloud = texture2D_bicubic(colortex0,texcoord*CLOUDS_QUALITY);
		if(eyeAltitude < 25000) background = background*cloud.a + cloud.rgb;

		gl_FragData[0].rgb = clamp(fp10Dither(background ,triangularize(noise)),0.0,65000.);

	#endif

	}else{//land

	////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	DIRECT LIGHTING		////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////

		vec3 Direct_lighting = vec3(1.0);

		float Shadows = clamp(1.0 - filtered.b,0.0,1.0);
		float SHADOWBLOCKERDEPTBH = filtered.y;

		float NdotL = dot(slopednormal,WsunVec);
		NdotL = clamp((-15 + NdotL*255.0) / 240.0  ,0.0,1.0);
		

		float shadowNDOTL = NdotL;
		#ifndef Variable_Penumbra_Shadows
			shadowNDOTL += LabSSS;
		#endif
		
		vec3 p3_shadow = mat3(gbufferModelViewInverse) * fragpos_handfix + gbufferModelViewInverse[3].xyz;

		if(!hand) GriAndEminShadowFix(p3_shadow, viewToWorld(FlatNormals), vanilla_AO, lightmap.y, entities);
		
		vec3 projectedShadowPosition = mat3(shadowModelView) * p3_shadow  + shadowModelView[3].xyz;
		projectedShadowPosition = diagonal3(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

		//apply distortion
		float distortFactor = calcDistort(projectedShadowPosition.xy);
		projectedShadowPosition.xy *= distortFactor;
		

		bool ShadowBounds = false;
		if(shadowDistanceRenderMul > 0.0) ShadowBounds = length(p3_shadow) < max(shadowDistance - 20,0.0);
		
		if(shadowDistanceRenderMul < 0.0) ShadowBounds = abs(projectedShadowPosition.x) < 1.0-1.5/shadowMapResolution && abs(projectedShadowPosition.y) < 1.0-1.5/shadowMapResolution && abs(projectedShadowPosition.z) < 6.0;

		//do shadows only if on shadow map
		if(ShadowBounds){
			if (shadowNDOTL >= -0.001){
				Shadows = 0.0;
				projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5);

				#ifdef BASIC_SHADOW_FILTER
					float rdMul = filtered.x*distortFactor*d0*k/shadowMapResolution;

					for(int i = 0; i < SHADOW_FILTER_SAMPLE_COUNT; i++){
						vec2 offsetS = tapLocation(i,SHADOW_FILTER_SAMPLE_COUNT,1.618,noise,0.0);

						float isShadow = shadow2D(shadow,projectedShadowPosition + vec3(rdMul*offsetS, 0.0)	).x;
						Shadows += isShadow/SHADOW_FILTER_SAMPLE_COUNT;
					}
				#else
					Shadows = shadow2D(shadow, projectedShadowPosition).x;
				#endif
			}
			shadowmapindicator = 1;
		}

		bool outsideShadowMap = shadowmapindicator < 1;

		if(outsideShadowMap && !iswater) Shadows = min(max(lightmap.y-0.8, 0.0) * 25,1.0);

	////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	SUN SSS		////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////

		#if SSS_TYPE != 0
			#ifndef Variable_Penumbra_Shadows
				if(LabSSS > 0 ) {
					SHADOWBLOCKERDEPTBH = pow(1.0 - Shadows,2);
				}
			#endif

			if (outsideShadowMap) SHADOWBLOCKERDEPTBH = 0.0;

			float sunSSS_density = LabSSS;
			
			#ifndef RENDER_ENTITY_SHADOWS
				if(entities) sunSSS_density = 0.0;
			#endif


			Direct_SSS = SubsurfaceScattering_sun(albedo, SHADOWBLOCKERDEPTBH, sunSSS_density, clamp(dot(np3, WsunVec),0.0,1.0)) ;

			if (isEyeInWater == 0) Direct_SSS *= clamp(pow(eyeBrightnessSmooth.y/240. + lightmap.y,2.0) ,0.0,1.0); // light leak fix
		#endif

		if (!hand){
			#ifdef SCREENSPACE_CONTACT_SHADOWS
				bool dodistantSSS = outsideShadowMap && LabSSS > 0.0;
				float screenShadow = rayTraceShadow(lightCol.a*sunVec, fragpos_rtshadow, interleaved_gradientNoise(), dodistantSSS);
				screenShadow *= screenShadow;

				Shadows = min(screenShadow, Shadows);

				if (outsideShadowMap) Direct_SSS *= Shadows;

			#else

				if (outsideShadowMap) Direct_SSS = vec3(0.0);
			#endif
		}

		#if SSS_TYPE != 0
			Direct_SSS *= 1.0-clamp(NdotL*Shadows,0,1);
		#endif

		#ifdef VOLUMETRIC_CLOUDS
		#ifdef CLOUDS_SHADOWS
			cloudShadow = GetCloudShadow(p3);
			Shadows *= cloudShadow;
			Direct_SSS *= cloudShadow;
		#endif
		#endif
			 
	////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	INDIRECT LIGHTING	////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////

		vec3 Indirect_lighting = vec3(1.0);

		if(isGrass) ambientCoefs.y = 0.75;
		float skylight = clamp(ambientCoefs.y + 0.5,0.25,2.0) * 1.35;
	
		AmbientLightColor += (lightningEffect * 10) * skylight * pow(lightmap.y,2);

		#ifndef ambientSSS_view
		
			#if indirect_effect == 2
				skylight = 1.0;
			#endif

			#if indirect_effect != 3 || indirect_effect != 4
				Indirect_lighting = DoAmbientLighting(AmbientLightColor, vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.xy, skylight);
			#endif

		#else
			Indirect_lighting = vec3(0.0);
		#endif

	////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	UNDER WATER SHADING		////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////

 		if ((isEyeInWater == 0 && iswater) || (isEyeInWater == 1 && !iswater)){

			vec3 fragpos0 = toScreenSpace(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z0));
			float Vdiff = distance(fragpos,fragpos0);
			float VdotU = np3.y;
			float estimatedDepth = Vdiff * abs(VdotU);	//assuming water plane
			estimatedDepth = estimatedDepth;
			// make it such that the estimated depth flips to be correct when entering water.

			if (isEyeInWater == 1) estimatedDepth = (1.0-lightmap.y)*16.0;
			
			float estimatedSunDepth = Vdiff; //assuming water plane
			vec3 Absorbtion = exp2(-totEpsilon*estimatedDepth);

			// caustics...
			float Direct_caustics  = waterCaustics(p3 + cameraPosition, WsunVec) * cloudShadow;
			// float Ambient_Caustics = waterCaustics(p3 + cameraPosition, vec3(0.5, 1, 0.5));
			
			// apply caustics to the lighting
			DirectLightColor *= 1.0 + max(pow(Direct_caustics * 3.0, 2.0),0.0);
			// Indirect_lighting *= 0.5 + max(pow(Ambient_Caustics, 2.0),0.0); 

			DirectLightColor *= Absorbtion;
			if(isEyeInWater == 1 ) Indirect_lighting = (Indirect_lighting/exp2(-estimatedDepth*0.5))  * Absorbtion;

			if(isEyeInWater == 0) DirectLightColor *= max(eyeBrightnessSmooth.y/240., 0.0);
			DirectLightColor *= cloudShadow;
		}
		
	////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	EFFECTS FOR INDIRECT	////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////

		vec3 AO = vec3(1.0);
		float SkySSS = 0.0;

		// vanilla AO
		#if indirect_effect == 0
			AO = vec3( exp( (vanilla_AO*vanilla_AO) * -5) ) ;
		#endif

		// SSAO + vanilla AO
		#if indirect_effect == 1
			AO = vec3( exp( (vanilla_AO*vanilla_AO) * -3) )  ;
			if (!hand) ssAO(AO, SkySSS, fragpos, 1.0, blueNoise(gl_FragCoord.xy).rg,   FlatNormals , texcoord, ambientCoefs, lightmap.xy, isLeaf);
		#endif

		// GTAO
		#if indirect_effect == 2
			int seed = (frameCounter%40000);
			vec2 r2 = fract(R2_samples(seed) + blueNoise(gl_FragCoord.xy).rg);
			if (!hand) AO = ambient_occlusion(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z), fragpos, worldToView(slopednormal), r2, debug) * vec3(1.0);
		#endif

		// RTAO and/or SSGI
		#if indirect_effect == 3 || indirect_effect == 4
			AO = vec3(1.0);
			if (!hand) ApplySSRT(Indirect_lighting, normal, blueNoise(gl_FragCoord.xy).rg, fragpos, lightmap.xy, AmbientLightColor, vec3(TORCH_R,TORCH_G,TORCH_B), isGrass);
		#endif

		#ifndef AO_in_sunlight
			AO = mix(AO,vec3(1.0),  min(NdotL*Shadows,1.0));
		#endif
		
		Indirect_lighting *= AO;
		
	////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	SKY SSS		////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////

		#ifdef Ambient_SSS
			if (!hand){

				vec3 SSS_forSky = vec3(0.0);

				#if indirect_effect != 1
					ScreenSpace_SSS(SkySSS, fragpos, blueNoise(gl_FragCoord.xy).rg, FlatNormals, isLeaf);
				#endif

				vec3 ambientColor = ((AmbientLightColor * ambient_brightness) / 30.0 ) * 1.5;
				float skylightmap =  pow(lightmap.y,3);
				float uplimit = clamp(1.0-pow(clamp(ambientCoefs.y + 0.5,0.0,1.0),2),0,1);

				SSS_forSky = SubsurfaceScattering_sky(albedo, SkySSS, LabSSS);
				SSS_forSky *= ambientColor;
				SSS_forSky *= skylightmap;
				SSS_forSky *= uplimit;

				// Combine with the other SSS
				Indirect_SSS += SSS_forSky;

				SSS_forSky = vec3((1.0 - SkySSS) * LabSSS);
				SSS_forSky *= ambientColor;
				SSS_forSky *= skylightmap;

				////light up dark parts so its more visible
				Indirect_lighting = max(Indirect_lighting, SSS_forSky);
			}
		#endif

	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	FINALIZE	////////////////////////////////
	//////////////////////////////// 				////////////////////////////////

		#ifdef Seasons
		#ifdef Snowy_Winter

			vec3 snow_p3 = p3 + cameraPosition ;

			snow_p3 /= 75.0;

			// float resolution = 1000.;
			// snow_p3 = (fract(snow_p3 * resolution) / resolution) - snow_p3;

			float SnowPatches = texture2D(noisetex,	snow_p3.xz).r;
			// float SnowPatches = densityAtPosSNOW(snow_p3);

			SnowPatches = 1.0 - clamp( exp(pow(SnowPatches,3.5) * -100.0) ,0,1);
			SnowPatches *= clamp(sqrt(normal.y),0,1) * clamp(pow(lightmap.y,25)*25,0,1);

			SnowPatches = mix(0.0, SnowPatches, WinterTimeForSnow);

			if(!hand && !iswater && !entities && isEyeInWater == 0){
				albedo = mix(albedo, vec3(0.8,0.9,1.0), SnowPatches);
				SpecularTex.rg = mix(SpecularTex.rg, vec2(1,0.05), SnowPatches);
			}
		#endif
		#endif

		Direct_lighting = DoDirectLighting(DirectLightColor, Shadows, NdotL, 0.0);
		Direct_SSS *= DirectLightColor; // do this here so it gets underwater absorbtion.

		vec3 FINAL_COLOR = Indirect_lighting + Indirect_SSS + Direct_lighting + Direct_SSS ;

		#ifndef ambientSSS_view
			FINAL_COLOR *= albedo;
		#endif

		#ifdef Specular_Reflections	
			// MaterialReflections(FINAL_COLOR, SpecularTex.r, SpecularTex.ggg, albedo, WsunVec, (Shadows*NdotL)*DirectLightColor, lightmap.y, slopednormal, np3, fragpos, vec3(blueNoise(gl_FragCoord.xy).rg, interleaved_gradientNoise()), hand, entities);

			vec3 specNoise = vec3(blueNoise(gl_FragCoord.xy).rg, interleaved_gradientNoise());

			DoSpecularReflections(FINAL_COLOR, fragpos, np3, WsunVec, specNoise, slopednormal, SpecularTex.r, SpecularTex.g, albedo, DirectLightColor*NdotL*Shadows, lightmap.y, hand);
		#endif

		Emission(FINAL_COLOR, albedo, SpecularTex.a);

		if(lightningBolt) FINAL_COLOR.rgb += vec3(77.0, 153.0, 255.0);

		gl_FragData[0].rgb =  FINAL_COLOR;

	}

	////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	UNDERWATER FOG	////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////

	if (iswater && isEyeInWater == 0){
		vec3 fragpos0 = toScreenSpace(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z0));
		float Vdiff = distance(fragpos,fragpos0);
		float VdotU = np3.y;
		float estimatedDepth = Vdiff * abs(VdotU) ;	//assuming water plane
		float estimatedSunDepth = estimatedDepth/abs(WsunVec.y); //assuming water plane
	
		float custom_lightmap_T = clamp(pow(texture2D(colortex14, texcoord).a,3.0),0.0,1.0);

		vec3 lightColVol = lightCol.rgb / 80.;
		// if(shadowmapindicator < 1) lightColVol *= clamp((custom_lightmap_T-0.8) * 15,0,1)

		vec3 lightningColor = (lightningEffect / 3) * (max(eyeBrightnessSmooth.y,0)/240.);
		vec3 ambientColVol =  max((averageSkyCol_Clouds / 30.0) *  custom_lightmap_T, vec3(0.2,0.4,1.0) * (MIN_LIGHT_AMOUNT*0.01 + nightVision)) + lightningColor;

		 waterVolumetrics(gl_FragData[0].rgb, fragpos0, fragpos, estimatedDepth , estimatedSunDepth, Vdiff, noise, totEpsilon, scatterCoef, ambientColVol, lightColVol, dot(np3, WsunVec));		
	}

	////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	MISC EFFECTS	////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////
	
	
	#if DOF_QUALITY == 5
		vec3 laserColor;
		#if FOCUS_LASER_COLOR == 0 // Red
		laserColor = vec3(25, 0, 0);
		#elif FOCUS_LASER_COLOR == 1 // Green
		laserColor = vec3(0, 25, 0);
		#elif FOCUS_LASER_COLOR == 2 // Blue
		laserColor = vec3(0, 0, 25);
		#elif FOCUS_LASER_COLOR == 3 // Pink
		laserColor = vec3(25, 10, 15);
		#elif FOCUS_LASER_COLOR == 4 // Yellow
		laserColor = vec3(25, 25, 0);
		#elif FOCUS_LASER_COLOR == 5 // White
		laserColor = vec3(25);
		#endif
		
		#if MANUAL_FOCUS == -2
		float focusDist = rodExposureDepth.y*far;
		#elif MANUAL_FOCUS == -1
		float focusDist = mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
		float focusDist = MANUAL_FOCUS;
		#endif

		if( hideGUI < 1.0) gl_FragData[0].rgb += laserColor * pow( clamp( 	 1.0-abs(focusDist-abs(fragpos.z))		,0,1),25) ;
	#endif
	
/* DRAWBUFFERS:3 */
}