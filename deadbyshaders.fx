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
    ui_label = "Enable Vivid";
    ui_tooltip = "Makes colors more saturated, duh";
    ui_category = "Overall";
> = false;

//static const bool VibrantMode = false;

uniform bool EnableBloom <
    ui_label = "Enable Bloom";
    ui_tooltip = "Add a glowing effect to your scratchies";
    ui_category = "Overall";
> = true;

uniform float3 TargetColor <
    ui_type = "color";
    ui_label = "Target Color";
    ui_tooltip = "Pick the exact color you want to enhance (e.g., scratch marks, blood)";
    ui_category = "Red Enhancement + colorshift";
> = float3(1.0, 0.392157, 0.392157);

uniform float ColorLikeness <
    ui_type = "slider";
    ui_label = "Color Likeness";
    ui_tooltip = "Determines how similar a color can be to the target color in order to be changed, lesser values are more strict and greater values are more inclusive";
    ui_category = "Red Enhancement + colorshift";
    ui_min = 0.05; ui_max = 0.5;
    ui_step = 0.01;
> = 0.3;

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
    ui_min = 0.1; ui_max = 1.0;
    ui_step = 0.05;
> = 0.5;

static const float SHARPNESS_STRENGTH = 1.30;
static const float SHARPNESS_RADIUS = 0.5;
static const float SHARPNESS_CLAMP = 0.3;
static const float CrosshairThickness = 1.0;
static const float CrosshairSize = 5.0;
static const float HuntressCrosshairVerticalOffset = 0.527;
static const float BLOOM_INTENSITY = 4;
static const float BLOOM_RADIUS = 1;


texture BloomMaskTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler BloomMaskSampler { Texture = BloomMaskTex; };


texture EnhancedColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler EnhancedColorSampler { 
    Texture = EnhancedColorTex;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};


texture BloomHorizontalTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler BloomHorizontalSampler { 
    Texture = BloomHorizontalTex;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

texture ColorMaskTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler ColorMaskSampler { Texture = ColorMaskTex; };

float cheapDither(float2 uv) {
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}


float2 cheapJitter(float2 uv, float seed) {
    float random1 = frac(sin(dot(uv, float2(12.9898, 78.233 + seed))) * 43758.5453);
    float random2 = frac(sin(dot(uv, float2(92.9898, 38.233 + seed))) * 65437.5453);
    return float2(random1, random2) * 0.1 - 0.15; // Â±15% jitter
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
    
    float hueDist = abs(colorHSV.x - targetHSV.x);
    if (hueDist > 0.5) hueDist = 1.0 - hueDist;
    
    float hueRange = 0.075;
    bool isMatchingHue = (hueDist < hueRange);
    if (!isMatchingHue)
        return 0.0;
    
    float minSaturation = 0.0;
    if (colorHSV.y < minSaturation)
        return 0.0;
    
    float satDist = abs(colorHSV.y - targetHSV.y) * 0.5;
    
    float valDist = abs(colorHSV.z - targetHSV.z) * 0.15;
    
    float totalDist = 2.0 * hueDist + satDist + valDist;
    
    float threshold = likeness * 2.5;
    
    float mask = saturate(1.0 - (totalDist / threshold));
    
    return pow(mask, 1.2);
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

float PS_GenerateBloomMask(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return 0.0;
        
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float colorMask = GetColorMask(color, TargetColor, ColorLikeness);
    
    return colorMask;
}

float PS_StoreColorMask(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    return GetColorMask(color, TargetColor, ColorLikeness);
}

float4 PS_StoreEnhancedColors(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0.0, 0.0, 0.0, 0.0);
        
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float colorMask = tex2D(ColorMaskSampler, texcoord).r; // Use pre-stored mask
    
    float dither = cheapDither(texcoord);
    float threshold = 0.15 + (dither - 0.5) * 0.09;
    
    if (colorMask > threshold)
    {
        float smoothMask = pow((colorMask - threshold) / (1.0 - threshold), 3.0);
        return float4(color * smoothMask, smoothMask);
    }
    
    return float4(0.0, 0.0, 0.0, 0.0);
}

float3 PS_RedEnhance(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float3 originalColor = color;
    
    float colorMask = GetColorMask(color, TargetColor, ColorLikeness);
    
 
    float saturationBoost = VibrantMode ? 2.7 : 1.1;
    float hueShiftFalloff = VibrantMode ? 2.7 : 1.2;
    
    if (colorMask > 0.01)
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
        
        hsv.z = saturate(hsv.z * 1.01);
        
        float3 shiftedColor = HSV2RGB(hsv);

        float mixAmount = colorMask * hueShiftFalloff;
        color = lerp(originalColor, shiftedColor, mixAmount);
    }
    
    return saturate(color);
}


float4 PS_BloomHorizontal(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!EnableBloom)
        return float4(0.0, 0.0, 0.0, 0.0);
    
    float2 pixelSize = ReShade::PixelSize * BLOOM_RADIUS;
    float4 bloomAccum = 0.0;
    float weightSum = 0.0;
    
    static const int sampleCount = 13;
    static const float offsets[13] = { -6.0, -5.0, -4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
    static const float weights[13] = { 0.008, 0.018, 0.038, 0.062, 0.082, 0.094, 0.100, 0.094, 0.082, 0.062, 0.038, 0.018, 0.008 };
    
    [unroll]
    for (int i = 0; i < sampleCount; i++)
    {
        float2 jitter = cheapJitter(texcoord, i * 0.234) * pixelSize.x;
        
        float2 offset = float2(offsets[i] * pixelSize.x, 0.0) + jitter;
        float weight = weights[i];
        
        float4 sampleColor = tex2D(EnhancedColorSampler, texcoord + offset);
        bloomAccum += sampleColor * weight;
        weightSum += weight;
    }
    
    return bloomAccum / weightSum;
}


float3 PS_BloomVertical(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!EnableBloom)
        return color;
    
    float2 pixelSize = ReShade::PixelSize * BLOOM_RADIUS;
    float4 bloomAccum = 0.0;
    float weightSum = 0.0;
    
    static const int sampleCount = 13;
    static const float offsets[13] = { -5.7, -4.7, -3.7, -2.7, -1.7, -0.7, 0.3, 1.3, 2.3, 3.3, 4.3, 5.3, 6.3 };
    static const float weights[13] = { 0.008, 0.018, 0.038, 0.062, 0.082, 0.094, 0.100, 0.094, 0.082, 0.062, 0.038, 0.018, 0.008 };
    
    [unroll]
    for (int i = 0; i < sampleCount; i++)
    {
        float2 jitter = cheapJitter(texcoord + float2(0.0, i * 0.156), i * 0.345) * pixelSize.y;
        
        float2 offset = float2(0.0, offsets[i] * pixelSize.y) + jitter;
        float weight = weights[i];
        
        float4 sampleColor = tex2D(BloomHorizontalSampler, texcoord + offset);
        bloomAccum += sampleColor * weight;
        weightSum += weight;
    }
    
    float4 bloom = bloomAccum / weightSum;
    
    float3 hsv = RGB2HSV(bloom);
    hsv.y *= 1.2;
    bloom = HSV2RGB(hsv);

    float3 bloomedColor = color + bloom.rgb * BLOOM_INTENSITY;
    
    // Aggressive soft luma limit to prevent whitening while preserving color
    float originalLuma = dot(color, float3(0.2126, 0.7152, 0.0722));
    float bloomedLuma = dot(bloomedColor, float3(0.2126, 0.7152, 0.0722));
    
    // Only compress if luma increased
    if (bloomedLuma > originalLuma)
    {
        float lumaIncrease = bloomedLuma - originalLuma;
        float softLimit = 0.7; 
        float compression = smoothstep(softLimit * 0.35, softLimit, bloomedLuma);

        float targetLuma = originalLuma + lumaIncrease * (1.0 - compression * 0.8);
        float lumaScale = targetLuma / (bloomedLuma + 0.001);
        bloomedColor *= lumaScale;
    }

    color = saturate(bloomedColor);
    return color;
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
    
    hsv.y = lerp(hsv.y, 0.0, yellowMask);
    
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
    
    float greenHueCenter = 0.3;
    float greenHueRange = 0.15;
    float orangeTintAmount = 0.1;
    float brightnessDarken = 0.80;
    
    float hueDist = abs(hsv.x - greenHueCenter);
    
    float greenMask = 1.0 - saturate(hueDist / greenHueRange);
    
    hsv.z = lerp(hsv.z, hsv.z * brightnessDarken, greenMask);
    
    hsv.y = lerp(hsv.y, 0.0, greenMask);
    
    color = HSV2RGB(hsv);
    
    float3 orangeTint = float3(orangeTintAmount, orangeTintAmount * 0.5, 0.0);
    color += orangeTint * greenMask;
    
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
    
    float thicknessAtBottom = 0.025; // Width at bottom
    float thicknessAtTop = 0.013;    // Width at top
    float thickness = lerp(thicknessAtTop, thicknessAtBottom, verticalPos);
    
    float distFromCenter = abs(texcoord.x - horizontalCenter);

    float distFromTop = texcoord.y - verticalCenter;
    float roundingRadius = 0.01; // Radius of the rounded top
    
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
        float edgeSoftness = 0.2; // Higher = more blur
        float edgeDist = distFromCenter / thickness;
        float softEdge = smoothstep(1.0 - edgeSoftness, 1.0, edgeDist);
        
        float topFadeDistance = 0.2;
        float topFade = smoothstep(0.0, topFadeDistance, distFromTop);
        
        float lineOpacity = DashLineOpacity * (1.0 - softEdge) * topFade;
        color = lerp(color, CrosshairColor, lineOpacity);
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
    
    pass StoreEnhancedColors
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_StoreEnhancedColors;
        RenderTarget = EnhancedColorTex;
    }
    
    pass GenerateBloomMask
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_GenerateBloomMask;
        RenderTarget = BloomMaskTex;
    }

    pass BrightnessEnhancement
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BrightnessEnhance;
    }
    
    pass BloomHorizontal
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomHorizontal;
        RenderTarget = BloomHorizontalTex;
    }
    
    pass BloomVerticalAndApply
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BloomVertical;
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
}
