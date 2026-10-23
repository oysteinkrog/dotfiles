// Star Nest by Pablo Roman Andrioli (Kali), MIT License.
// https://www.shadertoy.com/view/XlfGRj
//
// Themed variant for the Shader Wallpaper plugin. Every setting is a top-level
// const so the plugin's Shader Tweaks panel shows it. The colour grade maps the
// original brightness onto three colours. While followTheme is true,
// shader-wallpaper-theme-sync rewrites the lines tagged @theme(...) from
// ~/.config/kdeglobals whenever the Plasma colour scheme changes.

// Shape
const int   iterations = 17;    // @range(4, 24, 1) @label("Fractal iterations")
const float formuparam = 0.53;  // @range(0.3, 0.8, 0.005) @label("Formula parameter")
const int   volsteps   = 20;    // @range(4, 30, 1) @label("Volume steps")
const float stepsize   = 0.1;   // @range(0.02, 0.3, 0.005) @label("Step size")
const float zoom       = 0.8;   // @range(0.1, 3.0, 0.01) @label("Zoom")
const float tile       = 0.85;  // @range(0.3, 1.5, 0.005) @label("Tile size")
const float darkmatter = 0.3;   // @range(0.0, 1.0, 0.01) @label("Dark matter")
const float distfading = 0.73;  // @range(0.3, 1.0, 0.005) @label("Distance fading")

// Motion
const float speed      = 0.01;  // @range(0.0, 0.05, 0.0005) @label("Drift speed")
const float rotationX  = 0.5;   // @range(-3.14, 3.14, 0.01) @label("Rotation X")
const float rotationY  = 0.8;   // @range(-3.14, 3.14, 0.01) @label("Rotation Y")
const bool  useMouse   = true;  // @label("Rotate with the mouse")
const float mouseAmount = 0.1;  // @range(0.0, 1.0, 0.01) @label("Mouse rotation amount")

// Quality
const int   samples    = 2;     // @range(1, 3, 1) @label("Anti-aliasing (samples per side, less twinkling)")
const float aaSpread   = 0.5;   // @range(0.0, 1.0, 0.05) @label("Anti-aliasing spread (pixels, lower = more twinkling)")

// Original colouring
const float brightness = 0.0015; // @range(0.0002, 0.005, 0.0001) @label("Brightness")
const float saturation = 0.85;   // @range(0.0, 1.0, 0.01) @label("Saturation (original colours)")

// Colour grade
const bool  followTheme = true; // @label("Follow Plasma theme colours")
const vec3  deepColor   = vec3(0.078, 0.086, 0.094); // @color @label("Deep colour") @theme(View.BackgroundNormal)
const vec3  midColor    = vec3(0.239, 0.682, 0.914); // @color @label("Mid colour") @theme(Selection.BackgroundNormal)
const vec3  brightColor = vec3(0.988, 0.988, 0.988); // @color @label("Bright colour") @theme(View.ForegroundNormal)
const float themeMix    = 1.0;  // @range(0.0, 1.0, 0.01) @label("Theme colours (0 = original)")
const float deepLevel   = 0.4; // @range(0.0, 1.0, 0.01) @label("Deep colour brightness (0 = black)")
const float accentAmount = 0.35; // @range(0.0, 1.0, 0.01) @label("Mid colour strength (0 = grey)")
const float midPoint    = 0.75; // @range(0.1, 0.95, 0.01) @label("Mid colour position")
const float exposure    = 1.75; // @range(0.2, 8.0, 0.05) @label("Exposure")
const float gradeGamma  = 1.4;  // @range(0.3, 4.0, 0.01) @label("Contrast (gamma)")

vec3 grade(float t)
{
	vec3 deep=deepColor*deepLevel;
	float midLum=dot(midColor,vec3(0.2126,0.7152,0.0722));
	vec3 mid=mix(vec3(midLum),midColor,accentAmount);
	if (t < midPoint) return mix(deep, mid, t / midPoint);
	return mix(mid, brightColor, (t - midPoint) / (1.0 - midPoint));
}

vec3 render(vec2 fragCoord)
{
	//get coords and direction
	vec2 uv=fragCoord.xy/iResolution.xy-.5;
	uv.y*=iResolution.y/iResolution.x;
	vec3 dir=vec3(uv*zoom,1.);
	float time=iTime*speed+.25;

	//rotation; the original added iMouse/iResolution*2, which is 1.0 with the
	//cursor in the centre, so that 1.0 is kept and only the offset is scaled
	float a1=rotationX+1.;
	float a2=rotationY+1.;
	if (useMouse) {
		vec2 m=(iMouse.xy/iResolution.xy-.5)*2.*mouseAmount;
		a1+=m.x;
		a2+=m.y;
	}
	mat2 rot1=mat2(cos(a1),sin(a1),-sin(a1),cos(a1));
	mat2 rot2=mat2(cos(a2),sin(a2),-sin(a2),cos(a2));
	dir.xz*=rot1;
	dir.xy*=rot2;
	vec3 from=vec3(1.,.5,0.5);
	from+=vec3(time*2.,time,-2.);
	from.xz*=rot1;
	from.xy*=rot2;

	//volumetric rendering
	float s=0.1,fade=1.;
	vec3 v=vec3(0.);
	for (int r=0; r<volsteps; r++) {
		vec3 p=from+s*dir*.5;
		p = abs(vec3(tile)-mod(p,vec3(tile*2.))); // tiling fold
		float pa,a=pa=0.;
		for (int i=0; i<iterations; i++) {
			p=abs(p)/dot(p,p)-formuparam; // the magic formula
			a+=abs(length(p)-pa); // absolute sum of average change
			pa=length(p);
		}
		float dm=max(0.,darkmatter-a*a*.001); //dark matter
		a*=a*a; // add contrast
		if (r>6) fade*=1.-dm; // dark matter, don't render near
		v+=fade;
		v+=vec3(s,s*s,s*s*s*s)*a*brightness*fade; // coloring based on distance
		fade*=distfading; // distance fading
		s+=stepsize;
	}
	v=mix(vec3(length(v)),v,saturation); //color adjust
	vec3 original=v*.01;

	//colour grade: brightness onto deep -> mid -> bright
	float lum=dot(original,vec3(0.2126,0.7152,0.0722));
	float t=pow(clamp(1.-exp(-lum*exposure),0.,1.),gradeGamma);
	vec3 themed=grade(t);

	return mix(original,themed,themeMix);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
	//the far stars are smaller than a pixel and twinkle as the view drifts;
	//average samples x samples points spread over aaSpread of a pixel
	vec3 col=vec3(0.);
	for (int j=0; j<samples; j++) {
		for (int i=0; i<samples; i++) {
			col+=render(fragCoord+((vec2(i,j)+.5)/float(samples)-.5)*aaSpread);
		}
	}
	fragColor = vec4(col/float(samples*samples),1.);
}
