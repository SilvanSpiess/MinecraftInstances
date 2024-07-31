#include "/lib/settings.glsl"

#include "/lib/diffuse_lighting.glsl"


varying vec2 texcoord;



const bool colortex5MipmapEnabled = true;
const bool colortex4MipmapEnabled = true;

uniform sampler2D noisetex;//depth

uniform sampler2D depthtex1;//depth
uniform sampler2D depthtex0;//depth

uniform sampler2D colortex0;//clouds
uniform sampler2D colortex1;//albedo(rgb),material(alpha) RGBA16
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;//Skybox
uniform sampler2D colortex5;
uniform sampler2D colortex6;//Skybox
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex10;
uniform sampler2D colortex15;


uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float far;
uniform float near;

uniform vec2 texelSize;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

flat varying vec2 TAA_Offset;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform float rainStrength;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

uniform vec3 sunVec;

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}

#include "/lib/color_transforms.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/sky_gradient.glsl"


float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}

vec2 RENDER_SCALE = vec2(1.0);

#include "/lib/end_fog.glsl"

#undef LIGHTSOURCE_REFLECTION
#define ENDSPECULAR
#include "/lib/specular.glsl"


vec3 normVec (vec3 vec){
	return vec*inversesqrt(dot(vec,vec));
}
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

vec3 fp10Dither(vec3 color,float dither){
	const vec3 mantissaBits = vec3(6.,6.,5.);
	vec3 exponent = floor(log2(color));
	return color + dither*exp2(-mantissaBits)*exp2(exponent);
}



float facos(float sx){
    float x = clamp(abs( sx ),0.,1.);
    return sqrt( 1. - x ) * ( -0.16882 * x + 1.56734 );
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
// float linZ(float depth) {
//     return (2.0 * near) / (far + near - depth * (far - near));
// 	// l = (2*n)/(f+n-d(f-n))
// 	// f+n-d(f-n) = 2n/l
// 	// -d(f-n) = ((2n/l)-f-n)
// 	// d = -((2n/l)-f-n)/(f-n)

// }
// float invLinZ (float lindepth){
// 	return -((2.0*near/lindepth)-far-near)/(far-near);
// }

// vec3 toClipSpace3(vec3 viewSpacePosition) {
//     return projMAD(gbufferProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
// }




vec2 tapLocation(int sampleNumber,int nb, float nbRot,float jitter,float distort)
{
		float alpha0 = sampleNumber/nb;
    float alpha = (sampleNumber+jitter)/nb;
    float angle = jitter*6.28 + alpha * 4.0 * 6.28;

    float sin_v, cos_v;

	sin_v = sin(angle);
	cos_v = cos(angle);

    return vec2(cos_v, sin_v)*sqrt(alpha);
}



vec3 BilateralFiltering(sampler2D tex, sampler2D depth,vec2 coord,float frDepth,float maxZ){
  vec4 sampled = vec4(texelFetch2D(tex,ivec2(coord),0).rgb,1.0);

  return vec3(sampled.x,sampled.yz/sampled.w);
}
float interleaved_gradientNoise(){
	// vec2 coord = gl_FragCoord.xy + (frameCounter%40000);
	vec2 coord = gl_FragCoord.xy + frameTimeCounter;
	// vec2 coord = gl_FragCoord.xy;
	float noise = fract( 52.9829189 * fract( (coord.x * 0.06711056) + (coord.y * 0.00583715)) );
	return noise ;
}

vec2 R2_dither(){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return vec2(fract(alpha.x * gl_FragCoord.x + alpha.y * gl_FragCoord.y + 1.0/1.6180339887 * frameCounter), fract((1.0-alpha.x) * gl_FragCoord.x + (1.0-alpha.y) * gl_FragCoord.y + 1.0/1.6180339887 * frameCounter));
}
float blueNoise(){
  return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * (frameCounter*0.5+0.5)	);
}
vec4 blueNoise(vec2 coord){
  return texelFetch2D(colortex6, ivec2(coord)%512 , 0) ;
}
vec3 toShadowSpaceProjected(vec3 p3){
    p3 = mat3(gbufferModelViewInverse) * p3 + gbufferModelViewInverse[3].xyz;
    p3 = mat3(shadowModelView) * p3 + shadowModelView[3].xyz;
    p3 = diagonal3(shadowProjection) * p3 + shadowProjection[3].xyz;

    return p3;
}
vec2 tapLocation(int sampleNumber, float spinAngle,int nb, float nbRot,float r0)
{
    float alpha = (float(sampleNumber*1.0f + r0) * (1.0 / (nb)));
    float angle = alpha * (nbRot * 6.28) + spinAngle*6.28;

    float ssR = alpha;
    float sin_v, cos_v;

	sin_v = sin(angle);
	cos_v = cos(angle);

    return vec2(cos_v, sin_v)*ssR;
}


float ssao(vec3 fragpos, float dither,vec3 normal)
{
	float mulfov = 1.0;
	ivec2 pos = ivec2(gl_FragCoord.xy);
	const float tan70 = tan(70.*3.14/180.);
	float mulfov2 = gbufferProjection[1][1]/tan70;

	const float PI = 3.14159265;
	const float samplingRadius = 0.712;
	float angle_thresh = 0.05;




	float rd = mulfov2*0.05;
	//pre-rotate direction
	float n = 0.;

	float occlusion = 0.0;

	vec2 acc = -vec2(TAA_Offset)*texelSize*0.5;
	float mult = (dot(normal,normalize(fragpos))+1.0)*0.5+0.5;

	vec2 v = fract(vec2(dither,interleaved_gradientNoise()) + (frameCounter%10000) * vec2(0.75487765, 0.56984026));
	for (int j = 0; j < 7+2 ;j++) {
			vec2 sp = tapLocation(j,v.x,7+2,2.,v.y);
			vec2 sampleOffset = sp*rd;
			ivec2 offset = ivec2(gl_FragCoord.xy + sampleOffset*vec2(viewWidth,viewHeight));
			if (offset.x >= 0 && offset.y >= 0 && offset.x < viewWidth && offset.y < viewHeight ) {
				vec3 t0 = toScreenSpace(vec3(offset*texelSize+acc+0.5*texelSize,texelFetch2D(depthtex1,offset,0).x));

				vec3 vec = t0.xyz - fragpos;
				float dsquared = dot(vec,vec);
				if (dsquared > 1e-5){
					if (dsquared < fragpos.z*fragpos.z*0.05*0.05*mulfov2*2.*1.412){
						float NdotV = clamp(dot(vec*inversesqrt(dsquared), normalize(normal)),0.,1.);
						occlusion += NdotV;
					}
					n += 1.0;
				}
			}
		}




		return clamp(1.0-occlusion/n*2.0,0.,1.0);
}
vec3 viewToWorld(vec3 viewPosition) {
    vec4 pos;
    pos.xyz = viewPosition;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}
vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}
void waterVolumetrics(inout vec3 inColor, vec3 rayStart, vec3 rayEnd, float estEndDepth, float estSunDepth, float rayLength, float dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient){
		inColor *= exp(-rayLength * waterCoefs);	//No need to take the integrated value
		int spCount = rayMarchSampleCount;
		vec3 start = toShadowSpaceProjected(rayStart);
		vec3 end = toShadowSpaceProjected(rayEnd);
		vec3 dV = (end-start);
		//limit ray length at 32 blocks for performance and reducing integration error
		//you can't see above this anyway
		float maxZ = min(rayLength,12.0)/(1e-8+rayLength);
		dV *= maxZ;
		vec3 dVWorld = -mat3(gbufferModelViewInverse) * (rayEnd - rayStart) * maxZ;
		rayLength *= maxZ;
		float dY = normalize(mat3(gbufferModelViewInverse) * rayEnd).y * rayLength;
		estEndDepth *= maxZ;
		estSunDepth *= maxZ;
		vec3 absorbance = vec3(1.0);
		vec3 vL = vec3(0.0);


		float expFactor = 11.0;
		vec3 progressW = gbufferModelViewInverse[3].xyz+cameraPosition;
		for (int i=0;i<spCount;i++) {
			float d = (pow(expFactor, float(i+dither)/float(spCount))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
			float dd = pow(expFactor, float(i+dither)/float(spCount)) * log(expFactor) / float(spCount)/(expFactor-1.0);
			vec3 spPos = start.xyz + dV*d;
			progressW = gbufferModelViewInverse[3].xyz+cameraPosition + d*dVWorld;

			vec3 ambientMul = exp(-max(estEndDepth * d,0.0) * waterCoefs);

			vec3 light =  (ambientMul*ambient) * scatterCoef;

			vL += (light - light * exp(-waterCoefs * dd * rayLength)) / waterCoefs *absorbance;
			absorbance *= exp(-dd * rayLength * waterCoefs);
		}
		inColor += vL;
}

void Emission(
	inout vec3 Lighting,
	vec3 Albedo,
	float Emission
){
	// if( Emission < 255.0/255.0 ) Lighting = mix(Lighting, Albedo * Emissive_Brightness, pow(Emission, Emissive_Curve)); // old method.... idk why
	if( Emission < 255.0/255.0 ) Lighting += (Albedo * Emissive_Brightness * 0.25) * pow(Emission, Emissive_Curve);
}

float rayTraceShadow(vec3 dir,vec3 position,float dither){
    const float quality = 16.;
    vec3 clipPosition = toClipSpace3(position);
	//prevents the ray from going behind the camera
	float rayLength = ((position.z + dir.z * far*sqrt(3.)) > -near) ?
      					 (-near -position.z) / dir.z : far*sqrt(3.) ;
    vec3 direction = toClipSpace3(position+dir*rayLength)-clipPosition;  //convert to clip space
    direction.xyz = direction.xyz/max(abs(direction.x)/texelSize.x,abs(direction.y)/texelSize.y);	//fixed step size
    vec3 stepv = direction * 3.0 * clamp(MC_RENDER_QUALITY,1.,2.0);
	
	vec3 spos = clipPosition;
	spos += stepv*dither ;

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
vec2 R2_samples(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

void ApplySSRT(inout vec3 lighting, vec3 normal,vec2 noise,vec3 fragpos, float lightmaps, vec3 torchcolor){
	int nrays = RAY_COUNT;

	vec3 radiance = vec3(0.0);
	vec3 occlusion = vec3(0.0);
	vec3 skycontribution = vec3(0.0);

    // float skyLM = 0.0;
	// vec3 torchlight = vec3(0.0);
	// vec3 blank = vec3(0.0);
	// DoRTAmbientLighting(torchcolor, vec2(lightmaps,1.0), skyLM, torchlight, blank);

	for (int i = 0; i < nrays; i++){
		int seed = (frameCounter%40000)*nrays+i;
		vec2 ij = fract(R2_samples(seed) + noise );

		vec3 rayDir = TangentToWorld(normal, normalize(cosineHemisphereSample(ij,1.0)) ,1.0);

		#ifdef HQ_SSGI
			vec3 rayHit = rayTrace_GI( mat3(gbufferModelView) * rayDir, fragpos,  blueNoise(), 50.); // ssr rt
		#else
			vec3 rayHit = RT(mat3(gbufferModelView)*rayDir, fragpos, blueNoise(), 30.);  // choc sspt 
		#endif

		skycontribution = lighting;

		if (rayHit.z < 1.){
			
			#if indirect_effect == 4
				vec3 previousPosition = mat3(gbufferModelViewInverse) * toScreenSpace(rayHit) + gbufferModelViewInverse[3].xyz + cameraPosition-previousCameraPosition;
				previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
				previousPosition.xy = projMAD(gbufferPreviousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;
				if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.x < 1.0){
					radiance += (texture2D(colortex5,previousPosition.xy).rgb + skycontribution) * GI_Strength;
				}else{
					radiance += skycontribution;
				}
			#else
				radiance += skycontribution;
			#endif

			occlusion += skycontribution * GI_Strength;
				
		} else {
			radiance += skycontribution;
		}
	}
	
	occlusion *= AO_Strength;

	lighting = max(radiance/nrays - occlusion/nrays, 0.0); 
}

void main() {

	////// --------------- SETUP COORDINATE SPACES --------------- //////
	
		float z0 = texture2D(depthtex0,texcoord).x;
		float z = texture2D(depthtex1,texcoord).x;

		vec2 tempOffset=TAA_Offset;
		float noise = blueNoise();

		vec3 fragpos = toScreenSpace(vec3(texcoord-vec2(tempOffset)*texelSize*0.5,z));
		vec3 p3 = mat3(gbufferModelViewInverse) * fragpos;
		vec3 np3 = normVec(p3);

	////// --------------- UNPACK OPAQUE GBUFFERS --------------- //////
	
		vec4 data = texture2D(colortex1,texcoord);
		vec4 dataUnpacked0 = vec4(decodeVec2(data.x),decodeVec2(data.y)); // albedo, masks
		vec4 dataUnpacked1 = vec4(decodeVec2(data.z),decodeVec2(data.w)); // normals, lightmaps
		// vec4 dataUnpacked2 = vec4(decodeVec2(data.z),decodeVec2(data.w));

		vec3 albedo = toLinear(vec3(dataUnpacked0.xz,dataUnpacked1.x));
		vec2 lightmap = dataUnpacked1.yz;
		vec3 normal = decode(dataUnpacked0.yw);

	////// --------------- UNPACK MISC --------------- //////
	
		vec4 SpecularTex = texture2D(colortex8,texcoord);
		float LabSSS = clamp((-65.0 + SpecularTex.z * 255.0) / 190.0 ,0.0,1.0);	

		vec4 normalAndAO = texture2D(colortex15,texcoord);
		vec3 FlatNormals = normalAndAO.rgb * 2.0 - 1.0;
		vec3 slopednormal = normal;

		#ifdef POM
			#ifdef Horrible_slope_normals
    			vec3 ApproximatedFlatNormal = normalize(cross(dFdx(p3), dFdy(p3))); // it uses depth that has POM written to it.
				slopednormal = normalize(clamp(normal, ApproximatedFlatNormal*2.0 - 1.0, ApproximatedFlatNormal*2.0 + 1.0) );
			#endif
		#endif

		float vanilla_AO = clamp(normalAndAO.a,0,1);
		normalAndAO.a = clamp(pow(normalAndAO.a*5,4),0,1);


	////// --------------- MASKS/BOOLEANS --------------- //////

		bool iswater = texture2D(colortex7,texcoord).a > 0.99;
		bool lightningBolt = abs(dataUnpacked1.w-0.5) <0.01;
		bool isLeaf = abs(dataUnpacked1.w-0.55) <0.01;
		bool entities = abs(dataUnpacked1.w-0.45) < 0.01;	
		bool hand = abs(dataUnpacked1.w-0.75) < 0.01;
		// bool blocklights = abs(dataUnpacked1.w-0.8) <0.01;


	////// --------------- COLORS --------------- //////

		float dirtAmount = Dirt_Amount;
		vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
		vec3 totEpsilon = dirtEpsilon*dirtAmount + waterEpsilon;
		vec3 scatterCoef = dirtAmount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

		vec3 Indirect_lighting = vec3(1.0);
		vec3 Direct_lighting = vec3(0.0);

	///////////////////////////// start drawin :D

	if (z >= 1.0) {
		
		gl_FragData[0].rgb = vec3(0.0);

	} else {

		p3 += gbufferModelViewInverse[3].xyz;
	
	////////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	MAJOR LIGHTSOURCE STUFF 	////////////////////////
	////////////////////////////////////////////////////////////////////////////////////

	#ifdef END_SHADER
        vec3 LightColor = LightSourceColor(clamp(sqrt(length(p3+cameraPosition) / 150.0 - 1.0)  ,0.0,1.0));
        vec3 LightPos = LightSourcePosition(p3+cameraPosition, cameraPosition);

	    float LightFalloff = max(exp2(4.0 + length(LightPos) / -25),0.0);

		float NdotL = clamp( dot(normal,normalize(-LightPos)),0.0,1.0);
		NdotL = clamp((-15 + NdotL*255.0) / 240.0  ,0.0,1.0);

		float fogshadow = GetCloudShadow(p3+cameraPosition, LightPos, blueNoise());
		Direct_lighting = (LightColor * max(LightColor - (1-fogshadow) ,0.0)) * LightFalloff * NdotL;
		// vec3 LightSource = LightColor * fogshadow * LightFalloff * NdotL ;



        float LightFalloff2 = max(1.0-length(LightPos)/120,0.0);
		LightFalloff2 = pow(1.0-pow(1.0-LightFalloff2,0.5),2.0);
		LightFalloff2 *= 25;

		Direct_lighting += (LightColor * max(LightColor - 0.6,0.0)) * vec3(1.0,1.3,1.0) * LightFalloff2 * (NdotL*0.7+0.3);

		// float RT_Shadows = rayTraceShadow(worldToView(normalize(-LightPos)), fragpos_RTSHADOW, blueNoise());
		// if(!hand) LightSource *= RT_Shadows*RT_Shadows;
	#endif
	
	/////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	INDIRECT LIGHTING 	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////////////

		#ifdef END_SHADER
			Indirect_lighting = DoAmbientLighting_End(gl_Fog.color.rgb, vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, normal, np3);
		#endif

		#ifdef NETHER_SHADER
			vec3 AmbientLightColor = skyCloudsFromTexLOD2(normal, colortex4, 6).rgb / 10;

			vec3 up 	= skyCloudsFromTexLOD2(vec3( 0, 1, 0), colortex4, 6).rgb / 10;
			vec3 down 	= skyCloudsFromTexLOD2(vec3( 0,-1, 0), colortex4, 6).rgb / 10;

			up   *= pow( max( slopednormal.y, 0), 2);
			down *= pow( max(-slopednormal.y, 0), 2);
			AmbientLightColor += up + down;

			// do all ambient lighting stuff
			Indirect_lighting = DoAmbientLighting_Nether(AmbientLightColor, vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, normal, np3, p3 );
		#endif
	/////////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	EFFECTS FOR INDIRECT	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////////////////

		#if indirect_effect == 0
			vec3 AO = vec3( exp( (vanilla_AO*vanilla_AO) * -5) )  ;
			if(!hand) Indirect_lighting *= AO;
		#endif

		#if indirect_effect == 1
			vec3 AO = vec3( exp( (vanilla_AO*vanilla_AO) * -5) )  ;
			if(!hand) Indirect_lighting *= ssao(fragpos,noise,FlatNormals) * AO;
		#endif
		
		// RTAO and/or SSGI
		#if indirect_effect == 3 || indirect_effect == 4
			if (!hand) ApplySSRT(Indirect_lighting, normal, blueNoise(gl_FragCoord.xy).rg, fragpos, lightmap.x,vec3(TORCH_R,TORCH_G,TORCH_B));
		#endif

	/////////////////////////////////////////////////////////////////////////
	/////////////////////////////	FINALIZE	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////

		gl_FragData[0].rgb = (Indirect_lighting + Direct_lighting) * albedo;

		#ifdef Specular_Reflections	
			vec3 specNoise = vec3(blueNoise(gl_FragCoord.xy).rg, interleaved_gradientNoise());
			DoSpecularReflections(gl_FragData[0].rgb, fragpos, np3, vec3(0.0), specNoise, normal, SpecularTex.r, SpecularTex.g, albedo, vec3(0.0), 1.0, hand);
		#endif

		Emission(gl_FragData[0].rgb, albedo, SpecularTex.a);

		if(lightningBolt) gl_FragData[0].rgb = vec3(1);
	
	}
	
	if (iswater && isEyeInWater == 0){
		vec3 fragpos0 = toScreenSpace(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z0));
		float Vdiff = distance(fragpos,fragpos0);
		float VdotU = np3.y;
		float estimatedDepth = Vdiff * abs(VdotU) ;	//assuming water plane

		vec3 ambientColVol =  max(vec3(1.0,0.5,1.0) * 0.3, vec3(0.2,0.4,1.0) * (MIN_LIGHT_AMOUNT*0.01 + nightVision));

		waterVolumetrics(gl_FragData[0].rgb, fragpos0, fragpos, estimatedDepth , estimatedDepth, Vdiff, noise, totEpsilon, scatterCoef, ambientColVol);
	}

/* DRAWBUFFERS:3 */
}
