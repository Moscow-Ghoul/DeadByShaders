#include "ReShade.fxh"

uniform float Brightness <
    ui_type = "slider";
    ui_label = "Brightness";
    ui_tooltip = "Makes the game brighter, duh";
    ui_category = "Overall";
    ui_min = 0.8; ui_max = 1.5;
    ui_step = 0.01;
> = 1.15;

uniform bool sharpyn <
    ui_label = "Enable sharpening";
    ui_tooltip = "Make it krispy";
    ui_category = "Overall";
> = true;

uniform bool AntiYellow <
    ui_label = "Enable Anti-Yellow Filter";
    ui_tooltip = "Makes Coldwind, Eyrie and DDS a little less piss-colored";
    ui_category = "Overall";
> = false;

uniform bool AntiGreen <
    ui_label = "Enable Anti-Green Filter";
    ui_tooltip = "Makes Autoheaven less sickly-looking (why do i even  have to do this, bhvr, it was fine before)";
    ui_category = "Overall";
> = false;

uniform bool VibrantMode <
    ui_label = "Comp shaders";
    ui_tooltip = "Makes colors (awfully) more saturated, duh";
    ui_category = "Overall";
> = false;

uniform bool EnableBloom <
    ui_label = "Enable Bloom";
    ui_tooltip = "Add a glowing effect to your scratchies";
    ui_category = "Overall";
> = true;

static const float BLOOM_THICKNESS = 1;
static const float BLOOM_INTENSITY = 1.5;

uniform float3 TargetColor <
    ui_type = "color";
    ui_label = "Target Color";
    ui_tooltip = "Pick the exact color you want to enhance (e.g., scratch marks, blood)";
    ui_category = "Red Enhancement + colorshift";
> = float3(1.0, 0.5, 0.5);

uniform float ColorLikeness <
    ui_type = "slider";
    ui_label = "Color Likeness";
    ui_tooltip = "Determines how similar a color can be to the target color in order to be changed, lesser values are more strict and greater values are more inclusive";
    ui_category = "Red Enhancement + colorshift";
    ui_min = 0.00; ui_max = 2;
    ui_step = 0.01;
> = 1;

uniform float TargetHueShift <
    ui_type = "slider";
    ui_label = "Target Color Hue Shift";
    ui_tooltip = "Determines the outcome color; think of it as the number of degrees by which you shift the color wheel";
    ui_category = "Red Enhancement + colorshift";
    ui_min = -180.0; ui_max = 180.0;
    ui_step = 1.0;
> = 180.0;

uniform bool ChromaMode <
    ui_label = "Enable Chroma Mode";
    ui_tooltip = "Automatically cycle through hue shifts (rainbow effect)";
    ui_category = "Red Enhancement + colorshift";
> = false;

uniform float ChromaPeriod <
    ui_type = "slider";
    ui_label = "Chroma Cycle Speed";
    ui_tooltip = "Time in seconds for one full color cycle";
    ui_category = "Red Enhancement + colorshift";
    ui_min = 0.1; ui_max = 10.0;
    ui_step = 0.5;
> = 5.0;

uniform float timer < source = "timer"; >;

uniform bool ShowCrosshair <
    ui_label = "Show Deathslinger Crosshair";
    ui_category = "Crosshairs";
> = false;

uniform bool ShowHuntressCrosshair <
    ui_label = "Show Huntress Crosshair";
    ui_category = "Crosshairs";
> = false;

uniform bool ShowDashLine <
    ui_label = "Show Wesker Crosshair";
    ui_category = "Crosshairs";
> = false;

uniform float3 CrosshairColor <
    ui_type = "color";
    ui_label = "Crosshair Color";
    ui_category = "Crosshairs";
> = float3(1.0, 1.0, 1.0);

uniform float DashLineOpacity <
    ui_type = "slider";
    ui_label = "Crosshair Opacity";
    ui_category = "Crosshairs";
    ui_min = 0.0; ui_max = 1.0;
    ui_step = 0.05;
> = 0.5;

static const float SHARPNESS_STRENGTH = 1.30;
static const float SHARPNESS_RADIUS = 0.5;
static const float SHARPNESS_CLAMP = 0.3;
static const float CrosshairThickness = 1.0;
static const float CrosshairSize = 5.0;
static const float HuntressCrosshairVerticalOffset = 0.527;

texture BloomExtractTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler BloomExtractSampler { Texture = BloomExtractTex; MinFilter = LINEAR; MagFilter = LINEAR; };

texture BloomDown1Tex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler BloomDown1Sampler { Texture = BloomDown1Tex; MinFilter = LINEAR; MagFilter = LINEAR; };

texture BloomDown2Tex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler BloomDown2Sampler { Texture = BloomDown2Tex; MinFilter = LINEAR; MagFilter = LINEAR; };

texture BloomDown3Tex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; };
sampler BloomDown3Sampler { Texture = BloomDown3Tex; MinFilter = LINEAR; MagFilter = LINEAR; };

texture BloomUp1Tex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler BloomUp1Sampler { Texture = BloomUp1Tex; MinFilter = LINEAR; MagFilter = LINEAR; };

texture BloomUp2Tex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler BloomUp2Sampler { Texture = BloomUp2Tex; MinFilter = LINEAR; MagFilter = LINEAR; };

texture ColorMaskTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler ColorMaskSampler { Texture = ColorMaskTex; };

float cheapDither(float2 uv) {
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

float3 RGB2HSV(float3 rgb)
{
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(rgb.bg, K.wz), float4(rgb.gb, K.xy), step(rgb.b, rgb.g));
    float4 q = lerp(float4(p.xyw, rgb.r), float4(rgb.r, p.yzx), step(p.x, rgb.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSV2RGB(float3 hsv)
{
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(hsv.xxx + K.xyz) * 6.0 - K.www);
    return hsv.z * lerp(K.xxx, saturate(p - K.xxx), hsv.y);
}

float GetColorMask(float3 color, float3 target, float likeness)
{
    float3 colorHSV = RGB2HSV(color);
    float3 targetHSV = RGB2HSV(target);
    
    // Calculate hue distance (wrapping around color wheel)
    float hueDist = abs(colorHSV.x - targetHSV.x);
    if (hueDist > 0.5) hueDist = 1.0 - hueDist;
    
    // Soft hue gate: 0.075 = full pass, 0.075-0.085 = smooth falloff, >0.085 = zero
    float hueRangeCore = 0.075;
    float hueRangeEdge = 0.09;
    float hueMask = 1.0 - smoothstep(hueRangeCore, hueRangeEdge, hueDist);
    if (hueMask <= 0.0)
        return 0.0;
    
    // Target-relative saturation gate
    // Accept colors within a range around the target's saturation
    float satRange = 0.90; // how far from target saturation to accept (widened)
    float minSatCore = max(0.0, targetHSV.y - satRange);
    float minSatEdge = max(0.0, targetHSV.y - satRange - 0.15);
    float maxSatCore = min(1.0, targetHSV.y + satRange);
    float maxSatEdge = min(1.0, targetHSV.y + satRange + 0.15);
    
    // Saturation mask: 1.0 if within core range, smooth falloff at edges
    float satMask = 1.0;
    if (colorHSV.y < minSatCore)
        satMask = smoothstep(minSatEdge, minSatCore, colorHSV.y);
    else if (colorHSV.y > maxSatCore)
        satMask = 1.0 - smoothstep(maxSatCore, maxSatEdge, colorHSV.y);
    
    if (satMask <= 0.0)
        return 0.0;
    
    // Target-relative value gate
    // Accept colors within a range around the target's value/brightness
    float valRange = 0.80; // how far from target value to accept (widened)
    float minValCore = max(0.0, targetHSV.z - valRange);
    float minValEdge = max(0.0, targetHSV.z - valRange - 0.20);
    float maxValCore = min(1.0, targetHSV.z + valRange);
    float maxValEdge = min(1.0, targetHSV.z + valRange + 0.20);
    
    // Value mask: 1.0 if within core range, smooth falloff at edges
    float valMask = 1.0;
    if (colorHSV.z < minValCore)
        valMask = smoothstep(minValEdge, minValCore, colorHSV.z);
    else if (colorHSV.z > maxValCore)
        valMask = 1.0 - smoothstep(maxValCore, maxValEdge, colorHSV.z);
    
    if (valMask <= 0.0)
        return 0.0;
    
    // Calculate weighted distance in HSV space
    float satDist = abs(colorHSV.y - targetHSV.y) * 0.5;
    float valDist = abs(colorHSV.z - targetHSV.z) * 0.15;
    float totalDist = 2.0 * hueDist + 0.3 * satDist + 0.3 * valDist;
    
    // Normalization: calculate maximum expected distance for normalization
    // This represents the furthest color that should still get some mask value
    float maxExpectedDist = likeness * 0.5;
    
    // Remap distance to 0-1 range, normalized by likeness
    float normalizedDist = saturate(totalDist / maxExpectedDist);
    
    // Create gradient: 0 distance = 1.0 mask, max distance = 0.0 mask
    float distanceMask = 1.0 - normalizedDist;
    
    // Combine all masks
    float finalMask = hueMask * satMask * valMask * distanceMask;
    
    // Apply subtle curve for smoother tonal distribution
    return pow(finalMask, 0.9);
}

float3 PS_BrightnessEnhance(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    float shadowMask = luma * pow(1.0 - luma, 1.8);
    float shadowLift = (Brightness - 1.0) * 4.0;
    color += shadowLift * shadowMask;
    
    float midpoint = 0.5;
    color = (color - midpoint) * 1.1 + midpoint;
    
    return saturate(color);
}

float PS_StoreColorMask(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    return GetColorMask(color, TargetColor, ColorLikeness);
}

float3 PS_RedEnhance(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float3 originalColor = color;
    
    float colorMask = tex2D(ColorMaskSampler, texcoord).r;
    
    float saturationBoost = VibrantMode ? 2.2 : 1.3;
    float hueShiftFalloff = VibrantMode ? 2.3 : 1.8;
    
    if (colorMask > 0.00)
    {
        float3 hsv = RGB2HSV(color);
        
        float hueShift = TargetHueShift;
        
        if (ChromaMode)
        {
            float timeInSeconds = timer * 0.001;
            float cycle = frac(timeInSeconds / ChromaPeriod);
            hueShift = (cycle * 360.0) - 180.0;
        }
        
        if (abs(hueShift) > 0.1)
        {
            float hueShiftAmount = (hueShift / 360.0);
            hsv.x = frac(hsv.x + hueShiftAmount);
        }
        
        hsv.y = saturate(hsv.y * saturationBoost);
        hsv.z = saturate(hsv.z * 1.1);
        
        float3 shiftedColor = HSV2RGB(hsv);
        float mixAmount = colorMask * hueShiftFalloff;
        color = lerp(originalColor, shiftedColor, mixAmount);
    }
    
    return saturate(color);
}

float4 KawaseDown(sampler sourceSampler, float2 texcoord, float2 pixelSize, float offset)
{
    float4 sum = 0.0;
    
    // Kawase pattern - samples in a + pattern with offset
    sum += tex2D(sourceSampler, texcoord + float2(-offset, -offset) * pixelSize);
    sum += tex2D(sourceSampler, texcoord + float2(offset, -offset) * pixelSize);
    sum += tex2D(sourceSampler, texcoord + float2(-offset, offset) * pixelSize);
    sum += tex2D(sourceSampler, texcoord + float2(offset, offset) * pixelSize);
    
    return sum * 0.25;
}

// Kawase Blur Upsample - spreads the bloom while upscaling
float4 KawaseUp(sampler sourceSampler, float2 texcoord, float2 pixelSize, float offset)
{
    float4 sum = 0.0;
    
    // Tent filter weights for smooth upsampling
    sum += tex2D(sourceSampler, texcoord + float2(-offset, -offset) * pixelSize) * 0.25;
    sum += tex2D(sourceSampler, texcoord + float2(offset, -offset) * pixelSize) * 0.25;
    sum += tex2D(sourceSampler, texcoord + float2(-offset, offset) * pixelSize) * 0.25;
    sum += tex2D(sourceSampler, texcoord + float2(offset, offset) * pixelSize) * 0.25;
    
    return sum;
}

// Extract masked colors for blooming
float4 PS_ExtractBloom(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0, 0, 0, 0);
    
    float colorMask = tex2D(ColorMaskSampler, texcoord).r;
    
    float dither = cheapDither(texcoord);
    float threshold = 0.15 + (dither - 0.5) * 0.09;
    
    if (colorMask <= threshold)
        return float4(0, 0, 0, 0);
    
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float smoothMask = pow((colorMask - threshold) / (1.0 - threshold), 2.5);
    
    // SUPER-SATURATE before blurring so it stays vibrant after dilution
    float3 hsv = RGB2HSV(color);
    hsv.y = saturate(hsv.y * 3.0); // Crank saturation way up
    hsv.z = saturate(hsv.z * 1.2); // Slight brightness boost too
    float3 superSaturated = HSV2RGB(hsv);
    
    return float4(superSaturated * smoothMask, smoothMask);
}

// Downsample passes
float4 PS_BloomDown1(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0, 0, 0, 0);
    return KawaseDown(BloomExtractSampler, texcoord, ReShade::PixelSize * 2.0, 1.0 * BLOOM_THICKNESS);
}

float4 PS_BloomDown2(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0, 0, 0, 0);
    return KawaseDown(BloomDown1Sampler, texcoord, ReShade::PixelSize * 4.0, 1.0 * BLOOM_THICKNESS);
}

float4 PS_BloomDown3(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0, 0, 0, 0);
    return KawaseDown(BloomDown2Sampler, texcoord, ReShade::PixelSize * 8.0, 1.0 * BLOOM_THICKNESS);
}

// Upsample passes
float4 PS_BloomUp1(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0, 0, 0, 0);
    float4 up = KawaseUp(BloomDown3Sampler, texcoord, ReShade::PixelSize * 8.0, 1.0 * BLOOM_THICKNESS);
    float4 current = tex2D(BloomDown2Sampler, texcoord);
    return up + current;
}

float4 PS_BloomUp2(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0, 0, 0, 0);
    float4 up = KawaseUp(BloomUp1Sampler, texcoord, ReShade::PixelSize * 4.0, 1.0 * BLOOM_THICKNESS);
    float4 current = tex2D(BloomDown1Sampler, texcoord);
    return up + current;
}

// Soft Screen blend mode - like screen but less bright
float3 SoftScreenBlend(float3 base, float3 blend)
{
    // Modified screen blend with reduced brightness
    // Original screen: 1.0 - (1.0 - a) * (1.0 - b)
    // Soft screen: 1.0 - (1.0 - a) * (1.0 - b * softness)
    
    float softness = 0.65; // Controls how much less bright it is than regular screen
    float3 result = 1.0 - (1.0 - base) * (1.0 - blend * softness);
    
    // Additional brightness reduction for very bright areas
    float brightness = dot(result, float3(0.2126, 0.7152, 0.0722));
    if (brightness > 0.9)
    {
        float overBright = saturate((brightness - 0.9) / 0.1);
        result = lerp(result, base, overBright * 0.3);
    }
    
    return result;
}

// Final composite with soft screen blend mode
float3 PS_BloomComposite(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!EnableBloom)
        return color;
    
    float4 bloomUp = KawaseUp(BloomUp2Sampler, texcoord, ReShade::PixelSize * 2.0, 1.0 * BLOOM_THICKNESS);
    
    // The bloom is already super-saturated from extraction
    float3 bloomColor = bloomUp.rgb * BLOOM_INTENSITY * 0.5;
    
    // Use soft screen blend mode (less bright than regular screen)
    float3 result = SoftScreenBlend(color, bloomColor);
    
    return saturate(result);
}

float3 PS_AntiYellow(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!AntiYellow)
        return color;
    
    float3 hsv = RGB2HSV(color);
    
    float yellowHueCenter = 0.125;
    float yellowHueRange = 0.1;
    float blueTintAmount = 0.1;
    float brightnessDarken = 0.85;
    
    float hueDist = abs(hsv.x - yellowHueCenter);
    float yellowMask = 1.0 - saturate(hueDist / yellowHueRange);
    
    hsv.z = lerp(hsv.z, hsv.z * brightnessDarken, yellowMask);
    hsv.y = lerp(hsv.y, 0.0, yellowMask * 1.5);
    
    color = HSV2RGB(hsv);
    
    float3 blueTint = float3(0.0, 0.0, blueTintAmount);
    color += blueTint * yellowMask;
    
    return saturate(color);
}

float3 PS_AntiGreen(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!AntiGreen)
        return color;
    
    float3 hsv = RGB2HSV(color);
    
    float greenHueCenter = 0.35;
    float greenHueRange = 0.2;
    float3 blueTint = float3(0.0, 0.411765, 1.0);
    float tintStrength = 0.1;
    float brightnessDarken = 1.0;
    
    float hueDist = abs(hsv.x - greenHueCenter);
    float greenMask = 1.0 - saturate(hueDist / greenHueRange);
    
    hsv.z = lerp(hsv.z, hsv.z * brightnessDarken, greenMask);
    hsv.y = lerp(hsv.y, 0.1, greenMask * 1.5);
    
    color = HSV2RGB(hsv);
    
    color += blueTint * tintStrength * greenMask;
    
    return saturate(color);
}

float3 PS_Sharpen(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (sharpyn)
    {
        float2 pixelSize = ReShade::PixelSize * SHARPNESS_RADIUS;
        
        float3 blur = 0;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(-pixelSize.x, -pixelSize.y)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(0, -pixelSize.y)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(pixelSize.x, -pixelSize.y)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(-pixelSize.x, 0)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(pixelSize.x, 0)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(-pixelSize.x, pixelSize.y)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(0, pixelSize.y)).rgb;
        blur += tex2D(ReShade::BackBuffer, texcoord + float2(pixelSize.x, pixelSize.y)).rgb;
        blur /= 8.0;
        
        float3 sharp = color - blur;
        sharp = clamp(sharp, -SHARPNESS_CLAMP, SHARPNESS_CLAMP);
        
        color = saturate(color + sharp * SHARPNESS_STRENGTH);
    }
    
    return color;
}

float3 PS_Crosshair(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!ShowCrosshair)
        return color;
    
    float2 center = float2(0.5, 0.5075);
    
    float2 pixelPos = texcoord * ReShade::ScreenSize;
    float2 centerPos = center * ReShade::ScreenSize;
    float2 delta = abs(pixelPos - centerPos);
    
    bool isHorizontal = (delta.y < CrosshairThickness) && (delta.x < CrosshairSize);
    bool isVertical = (delta.x < CrosshairThickness) && (delta.y < CrosshairSize);
    
    if (isHorizontal || isVertical)
    {
        color = lerp(color, CrosshairColor, DashLineOpacity);
    }
    
    return color;
}

float3 PS_HuntressCrosshair(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!ShowHuntressCrosshair)
        return color;
    
    float2 center = float2(0.5, HuntressCrosshairVerticalOffset);
    
    float2 pixelPos = texcoord * ReShade::ScreenSize;
    float2 centerPos = center * ReShade::ScreenSize;
    float2 delta = abs(pixelPos - centerPos);
    
    bool isHorizontal = (delta.y < CrosshairThickness) && (delta.x < CrosshairSize);
    bool isVertical = (delta.x < CrosshairThickness) && (delta.y < CrosshairSize);
    
    if (isHorizontal || isVertical)
    {
        color = lerp(color, CrosshairColor, DashLineOpacity);
    }
    
    return color;
}

float3 PS_DashLine(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!ShowDashLine)
        return color;
    
    float horizontalCenter = 0.5;
    float verticalCenter = 0.4;
    
    if (texcoord.y < verticalCenter || abs(texcoord.x - horizontalCenter) > 0.05)
        return color;
    
    float verticalPos = (texcoord.y - verticalCenter) / (1.0 - verticalCenter);
    
    float thicknessAtBottom = 0.025;
    float thicknessAtTop = 0.013;
    float thickness = lerp(thicknessAtTop, thicknessAtBottom, verticalPos);
    
    float distFromCenter = abs(texcoord.x - horizontalCenter);
    float distFromTop = texcoord.y - verticalCenter;
    float roundingRadius = 0.01;
    
    float topCapFactor = 1.0;
    if (distFromTop < roundingRadius)
    {
        float2 capCenter = float2(horizontalCenter, verticalCenter + roundingRadius);
        float distToCapCenter = distance(texcoord, capCenter);

        if (distToCapCenter > roundingRadius)
            return color;
        
        distFromCenter = distToCapCenter - roundingRadius + distFromCenter;
    }
    
    if (distFromCenter < thickness)
    {
        float edgeSoftness = 0.2;
        float edgeDist = distFromCenter / thickness;
        float softEdge = smoothstep(1.0 - edgeSoftness, 1.0, edgeDist);
        
        float topFadeDistance = 0.2;
        float topFade = smoothstep(0.0, topFadeDistance, distFromTop);
        
        float lineOpacity = DashLineOpacity * (1.0 - softEdge) * topFade;
        color = lerp(color, CrosshairColor, lineOpacity);
    }
    
    return color;
}

float DrawText(float2 pixelPos, float2 startPos)
{
    float2 charPos = pixelPos - startPos;
    
    // Calculate slant offset: 7 pixels at top (row 0), decrease by 1 every 2 rows
    int row = int(charPos.y);
    int slantOffset = max(0, 7 - (row / 2));
    
    // Apply slant offset to horizontal position
    float slantedX = charPos.x - slantOffset;
    
    int charIndex = int(slantedX / 6.0); // 5 pixels wide + 1 pixel spacing
    float2 localPos = float2(slantedX - charIndex * 6.0, charPos.y);
    
    if (localPos.x >= 5.0 || localPos.y >= 14.0 || localPos.y < 0 || localPos.x < 0) return 0.0;
    
    int col = int(localPos.x);
    
    // M (modern calligraphy - part 1)
    if (charIndex == 0) {
        int pattern[14] = {
            0x01, 0x03, 0x07, 0x0F, 0x1D, 0x19, 0x19,
            0x19, 0x19, 0x19, 0x19, 0x19, 0x19, 0x08
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // M (modern calligraphy - part 2)
    else if (charIndex == 1) {
        int pattern[14] = {
            0x10, 0x18, 0x1C, 0x0E, 0x07, 0x03, 0x03,
            0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // O (modern calligraphy)
    else if (charIndex == 2) {
        int pattern[14] = {
            0x00, 0x00, 0x0E, 0x1F, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x1F, 0x0E, 0x04, 0x02
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // S (modern calligraphy)
    else if (charIndex == 3) {
        int pattern[14] = {
            0x02, 0x07, 0x0F, 0x18, 0x10, 0x1C, 0x0E,
            0x07, 0x03, 0x01, 0x19, 0x1E, 0x0C, 0x08
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // C (modern calligraphy)
    else if (charIndex == 4) {
        int pattern[14] = {
            0x00, 0x00, 0x0F, 0x1F, 0x18, 0x10, 0x10,
            0x10, 0x10, 0x18, 0x1F, 0x0F, 0x06, 0x02
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // O (modern calligraphy)
    else if (charIndex == 5) {
        int pattern[14] = {
            0x00, 0x00, 0x0E, 0x1F, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x1F, 0x0E, 0x04, 0x02
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // W (modern calligraphy)
    else if (charIndex == 6) {
        int pattern[14] = {
            0x00, 0x00, 0x11, 0x11, 0x11, 0x11, 0x15,
            0x15, 0x15, 0x1F, 0x0A, 0x0A, 0x0A, 0x04
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // G (modern calligraphy)
    else if (charIndex == 7) {
        int pattern[14] = {
            0x00, 0x00, 0x0F, 0x1F, 0x18, 0x10, 0x17,
            0x17, 0x11, 0x19, 0x1F, 0x0F, 0x03, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // H (modern calligraphy)
    else if (charIndex == 8) {
        int pattern[14] = {
            0x10, 0x10, 0x10, 0x10, 0x10, 0x1F, 0x1F,
            0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // O (modern calligraphy)
    else if (charIndex == 9) {
        int pattern[14] = {
            0x00, 0x00, 0x0E, 0x1F, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x1F, 0x0E, 0x04, 0x02
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // U (modern calligraphy)
    else if (charIndex == 10) {
        int pattern[14] = {
            0x00, 0x00, 0x11, 0x11, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x1F, 0x0F, 0x03, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // L (modern calligraphy)
    else if (charIndex == 11) {
        int pattern[14] = {
            0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10,
            0x10, 0x10, 0x10, 0x1F, 0x1F, 0x07, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // S (modern calligraphy)
    else if (charIndex == 12) {
        int pattern[14] = {
            0x02, 0x07, 0x0F, 0x18, 0x10, 0x1C, 0x0E,
            0x07, 0x03, 0x01, 0x19, 0x1E, 0x0C, 0x08
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // H (modern calligraphy)
    else if (charIndex == 13) {
        int pattern[14] = {
            0x10, 0x10, 0x10, 0x10, 0x10, 0x1F, 0x1F,
            0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // A (modern calligraphy)
    else if (charIndex == 14) {
        int pattern[14] = {
            0x00, 0x04, 0x0E, 0x0E, 0x0A, 0x0A, 0x11,
            0x1F, 0x1F, 0x11, 0x11, 0x11, 0x11, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // D (modern calligraphy)
    else if (charIndex == 15) {
        int pattern[14] = {
            0x10, 0x10, 0x1E, 0x1F, 0x13, 0x11, 0x11,
            0x11, 0x11, 0x13, 0x1F, 0x1E, 0x18, 0x00
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // E (modern calligraphy)
    else if (charIndex == 16) {
        int pattern[14] = {
            0x00, 0x00, 0x1F, 0x1F, 0x10, 0x10, 0x1E,
            0x1E, 0x10, 0x10, 0x1F, 0x1F, 0x0E, 0x04
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // R (modern calligraphy)
    else if (charIndex == 17) {
        int pattern[14] = {
            0x00, 0x00, 0x1E, 0x1F, 0x13, 0x13, 0x1F,
            0x1E, 0x16, 0x13, 0x13, 0x11, 0x11, 0x01
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    // S (modern calligraphy)
    else if (charIndex == 18) {
        int pattern[14] = {
            0x02, 0x07, 0x0F, 0x18, 0x10, 0x1C, 0x0E,
            0x07, 0x03, 0x01, 0x19, 0x1E, 0x0C, 0x08
        };
        return ((pattern[row] >> (4 - col)) & 1);
    }
    
    return 0.0;
}

float4 PS_Watermark(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, texcoord);
    
    float2 watermarkPos = float2(10, BUFFER_HEIGHT - 17); // 10px from left, 17px from bottom
    float3 watermarkColor = float3(1.0, 1.0, 1.0); // White
    float watermarkOpacity = 0.6; // 60% opacity
    
    float watermarkMask = DrawText(vpos.xy, watermarkPos);
    
    if (watermarkMask > 0.5) {
        color.rgb = lerp(color.rgb, watermarkColor, watermarkOpacity);
    }
    
    return color;
}

technique all_u_need_4_dbd_by_misha<
    ui_label = "All you need for DBD";
    ui_tooltip = "Comprehensive shader for Dead by Daylight by Misha \"Moscow Ghoul\""; 
>
{
    pass AntiYellowFilter
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AntiYellow;
    }
    
    pass AntiGreenFilter
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AntiGreen;
    }
    
    pass StoreColorMask
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_StoreColorMask;
        RenderTarget = ColorMaskTex;
    }

    pass RedEnhancement
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_RedEnhance;
    }
    
    pass ExtractBloom
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_ExtractBloom;
        RenderTarget = BloomExtractTex;
    }

    pass BrightnessEnhancement
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BrightnessEnhance;
    }
    
    // Kawase downsample chain
    pass BloomDown1
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomDown1;
        RenderTarget = BloomDown1Tex;
    }
    
    pass BloomDown2
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomDown2;
        RenderTarget = BloomDown2Tex;
    }
    
    pass BloomDown3
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomDown3;
        RenderTarget = BloomDown3Tex;
    }
    
    pass BloomUp1
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomUp1;
        RenderTarget = BloomUp1Tex;
    }
    
    pass BloomUp2
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomUp2;
        RenderTarget = BloomUp2Tex;
    }
    
    pass BloomComposite
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomComposite;
    }

    pass Sharpening
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Sharpen;
    }
        
    pass Crosshair
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Crosshair;
    }
    
    pass HuntressCrosshair
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_HuntressCrosshair;
    }
    
    pass DashKillerLine
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_DashLine;
    }

    pass Watermark
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Watermark;
    }
}
