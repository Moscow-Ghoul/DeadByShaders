#include "ReShade.fxh"

uniform float Brightness <
    ui_type = "slider";
    ui_label = "Brightness";
    ui_tooltip = "Makes the game brighter, duh";
    ui_category = "Overall";
    ui_min = 0.8; ui_max = 1.5;
    ui_step = 0.01;
> = 1.25;

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
    ui_tooltip = "Makes Autoheaven less sickly-looking (why do i even have to do this, bhvr, it was fine before)";
    ui_category = "Overall";
> = false;

uniform float3 TargetColor <
    ui_type = "color";
    ui_label = "Target Color";
    ui_tooltip = "Pick the exact color you want to replace (e.g., scratch marks, blood)";
    ui_category = "Color Replacement";
> = float3(1.0, 0.392157, 0.392157);

uniform float3 DesiredColor <
    ui_type = "color";
    ui_label = "Desired Color";
    ui_tooltip = "Pick the color you want target colors to become";
    ui_category = "Color Replacement";
> = float3(1.0, 0.392157, 0.392157);

uniform float ColorLikeness <
    ui_type = "slider";
    ui_label = "Color Similarity";
    ui_tooltip = "How similar a color must be to the target to be replaced (lower = more strict)";
    ui_category = "Color Replacement";
    ui_min = 0.05; ui_max = 0.5;
    ui_step = 0.01;
> = 0.4;

uniform float BlendStrength <
    ui_type = "slider";
    ui_label = "Blend Strength";
    ui_tooltip = "How strongly to apply the color replacement";
    ui_category = "Color Replacement";
    ui_min = 0.5; ui_max = 3.0;
    ui_step = 0.1;
> = 1.5;

uniform bool ChromaMode <
    ui_label = "Enable Chroma Mode";
    ui_tooltip = "Automatically cycle through hue shifts (rainbow effect)";
    ui_category = "Color Replacement";
> = false;

uniform float ChromaPeriod <
    ui_type = "slider";
    ui_label = "Chroma Cycle Speed";
    ui_tooltip = "Time in seconds for one full color cycle";
    ui_category = "Color Replacement";
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
    ui_label = "Wesker Crosshair Opacity";
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

// Helper function to calculate mask for a single color
float CalculateColorMask(float3 color, float3 target, float likeness)
{
    // Convert both colors to HSV
    float3 colorHSV = RGB2HSV(color);
    float3 targetHSV = RGB2HSV(target);
    
    // Calculate hue distance (circular distance, accounting for wraparound)
    float hueDist = abs(colorHSV.x - targetHSV.x);
    if (hueDist > 0.5) hueDist = 1.0 - hueDist;
    
    // STRICT HUE FILTER: Only process colors close to the target hue
    float hueRange = 0.075;
    bool isMatchingHue = (hueDist < hueRange);
    
    // If not in the target hue range, reject immediately
    if (!isMatchingHue)
        return 0.0;
    
    // For colors in target hue range, require minimum saturation
    float minSaturation = 0.1;
    if (colorHSV.y < minSaturation)
        return 0.0;
    
    // Calculate saturation distance (moderate weight)
    float satDist = abs(colorHSV.y - targetHSV.y) * 0.7;
    
    // Value/brightness distance gets low weight (inclusive for dark/bright variations)
    float valDist = abs(colorHSV.z - targetHSV.z) * 0.15;
    
    // Combine distances with hue being most important
    float totalDist = 2.0 * hueDist + satDist + valDist;
    
    // Convert likeness to threshold (tighter threshold)
    float threshold = likeness * 2.5;
    
    // Smooth falloff with sharper curve
    float mask = saturate(1.0 - (totalDist / threshold));
    
    // Apply power curve to make falloff more aggressive
    mask = pow(mask, 1.2);
    
    return mask;
}

// Main mask function with spatial coherence check
float GetColorMask(float3 color, float3 target, float likeness, float2 texcoord)
{
    // Calculate base mask for current pixel
    float mask = CalculateColorMask(color, target, likeness);
    
    // Early exit for no match
    if (mask < 0.01)
        return 0.0;
    
    // Sample neighboring pixels for edge detection
    float2 pixelSize = ReShade::PixelSize;
    
    // Get neighbor colors
    float3 left = tex2D(ReShade::BackBuffer, texcoord + float2(-pixelSize.x, 0)).rgb;
    float3 right = tex2D(ReShade::BackBuffer, texcoord + float2(pixelSize.x, 0)).rgb;
    float3 up = tex2D(ReShade::BackBuffer, texcoord + float2(0, -pixelSize.y)).rgb;
    float3 down = tex2D(ReShade::BackBuffer, texcoord + float2(0, pixelSize.y)).rgb;
    
    // Calculate neighbor masks
    float leftMask = CalculateColorMask(left, target, likeness);
    float rightMask = CalculateColorMask(right, target, likeness);
    float upMask = CalculateColorMask(up, target, likeness);
    float downMask = CalculateColorMask(down, target, likeness);
    
    // Average neighbor mask
    float neighborMask = (leftMask + rightMask + upMask + downMask) / 4.0;
    
    // Edge detection based on color differences
    float colorDiff = 0.0;
    colorDiff += length(color - left);
    colorDiff += length(color - right);
    colorDiff += length(color - up);
    colorDiff += length(color - down);
    colorDiff /= 4.0;
    
    // If pixel is on an edge (high color difference with neighbors)
    // and neighbors don't match the target, reduce mask strength
    if (colorDiff > 0.15 && neighborMask < 0.3)
    {
        // Strong edge penalty
        mask *= 0.2;
    }
    // If pixel has some matching neighbors, boost mask slightly
    else if (neighborMask > 0.1)
    {
        mask = lerp(mask, 1.0, 0.1);
    }
    
    return saturate(mask);
}

// Simple Brightness with Contrast Preservation
float3 PS_BrightnessEnhance(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    // Calculate luminance
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    
    // Shadow lift curve that keeps very dark lows dark, but lifts low-mid values
    // Peaks around 0.2-0.4 luminance range, minimal effect on very dark (<0.1) and bright (>0.5)
    float shadowMask = luma * pow(1.0 - luma, 1.8);
    float shadowLift = (Brightness - 1.0) * 4.0;
    color += shadowLift * shadowMask;
    
    // Add subtle 15% contrast boost
    float midpoint = 0.5;
    color = (color - midpoint) * 1.15 + midpoint;
    
    return saturate(color);
}

// Smart Color Replacement
float3 PS_RedEnhance(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float3 originalColor = color;
    
    // Get color similarity mask
    float colorMask = GetColorMask(color, TargetColor, ColorLikeness, texcoord);
    
    // Only process if there's a significant match
    if (colorMask > 0.01)
    {
        // Calculate original pixel properties
        float originalLuminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        float3 originalHSV = RGB2HSV(color);
        
        // Desired color properties
        float desiredLuminance = dot(DesiredColor, float3(0.2126, 0.7152, 0.0722));
        float3 desiredHSV = RGB2HSV(DesiredColor);
        
        // For Chroma Mode, override hue
        if (ChromaMode)
        {
            float timeInSeconds = timer * 0.001;
            float cycle = frac(timeInSeconds / ChromaPeriod);
            desiredHSV.x = cycle;
        }
        
        // Check if desired color is grayscale
        bool desiredIsGray = desiredHSV.y < 0.01;
        
        if (desiredIsGray)
        {
            // For grayscale replacement, preserve luminance details
            // Scale desired color based on original pixel brightness
            float luminanceFactor = originalLuminance / max(desiredLuminance, 0.001);
            luminanceFactor = clamp(luminanceFactor, 0.5, 2.0);
            
            // Apply the desired color with brightness adjustment
            float3 result = DesiredColor * luminanceFactor;
            
            // Blend with original based on mask strength
            color = lerp(color, result, colorMask * BlendStrength);
        }
        else
        {
            // For colored replacement
            // Start with the exact desired color
            float3 result = DesiredColor;
            
            // Preserve some of the original brightness for texture
            float brightnessPreservation = 0.4;
            float targetBrightness = desiredHSV.z;
            float blendedBrightness = lerp(originalHSV.z, targetBrightness, 1.0 - brightnessPreservation);
            
            // Convert desired color to HSV for brightness adjustment
            float3 desiredHSVAdjusted = desiredHSV;
            desiredHSVAdjusted.z = blendedBrightness;
            result = HSV2RGB(desiredHSVAdjusted);
            
            // Use overlay blending for better texture integration
            if (originalLuminance > 0.5)
            {
                // Screen blend for bright areas
                float3 screenBlend = 1.0 - (1.0 - result) * (1.0 - color);
                result = lerp(result, screenBlend, 0.4);
            }
            else
            {
                // Multiply blend for dark areas
                float3 multiplyBlend = result * color * 1.5;
                result = lerp(result, multiplyBlend, 0.4);
            }
            
            // Final blend with original
            float blendAmount = colorMask * BlendStrength;
            color = lerp(originalColor, result, blendAmount);
        }
    }
    
    return saturate(color);
}

// Anti-Green Filter
float3 PS_AntiGreen(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!AntiGreen)
        return color;
    
    float3 hsv = RGB2HSV(color);
    
    // Use adjustable green hue target
    float greenHueCenter = 0.3;
    float greenHueRange = 0.1;
    float orangeTintAmount = 0.1;
    float brightnessDarken = 0.85;
    
    // Calculate distance from green hue center
    float hueDist = abs(hsv.x - greenHueCenter);
    
    // Create mask for green colors	
    float greenMask = 1.0 - saturate(hueDist / greenHueRange);
    
    // Reduce brightness of greens
    hsv.z = lerp(hsv.z, hsv.z * brightnessDarken, greenMask);
    
    // Fully desaturate green tones
    hsv.y = lerp(hsv.y, 0.0, greenMask);
    
    // Convert back to RGB
    color = HSV2RGB(hsv);
    
    // Add orange tint to the desaturated greens (additive)
    float3 orangeTint = float3(orangeTintAmount, orangeTintAmount * 0.5, 0.0);
    color += orangeTint * greenMask;
    
    return saturate(color);
}

// Anti-Yellow Filter
float3 PS_AntiYellow(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!AntiYellow)
        return color;
    
    float3 hsv = RGB2HSV(color);
    
    // Hardcoded values that work well
    float yellowHueCenter = 0.125;
    float yellowHueRange = 0.1;
    float blueTintAmount = 0.1;
    float brightnessDarken = 0.85;
    
    // Calculate distance from yellow hue center
    float hueDist = abs(hsv.x - yellowHueCenter);
    
    // Create mask for yellow colors	
    float yellowMask = 1.0 - saturate(hueDist / yellowHueRange);
    
    // Reduce brightness of yellows
    hsv.z = lerp(hsv.z, hsv.z * brightnessDarken, yellowMask);
    
    // Fully desaturate yellow tones
    hsv.y = lerp(hsv.y, 0.0, yellowMask);
    
    // Convert back to RGB
    color = HSV2RGB(hsv);
    
    // Add blue tint to the desaturated yellows (additive)
    float3 blueTint = float3(0.0, 0.0, blueTintAmount);
    color += blueTint * yellowMask;
    
    return saturate(color);
}

// Sharpening
float3 PS_Sharpen(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (sharpyn)
    {
        // Sample surrounding pixels
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
        
        // Calculate sharpening
        float3 sharp = color - blur;
        sharp = clamp(sharp, -SHARPNESS_CLAMP, SHARPNESS_CLAMP);
        
        color = saturate(color + sharp * SHARPNESS_STRENGTH);
    }
    
    return color;
}

// Deathslinger Crosshair
float3 PS_Crosshair(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!ShowCrosshair)
        return color;
    
    // Calculate center of screen
    float2 center = float2(0.5, 0.5075);
    
    // Calculate distance from center in pixels
    float2 pixelPos = texcoord * ReShade::ScreenSize;
    float2 centerPos = center * ReShade::ScreenSize;
    float2 delta = abs(pixelPos - centerPos);
    
    // Horizontal line
    bool isHorizontal = (delta.y < CrosshairThickness) && (delta.x < CrosshairSize);
    
    // Vertical line
    bool isVertical = (delta.x < CrosshairThickness) && (delta.y < CrosshairSize);
    
    // Draw crosshair
    if (isHorizontal || isVertical)
    {
        color = CrosshairColor;
    }
    
    return color;
}

// Huntress Crosshair
float3 PS_HuntressCrosshair(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!ShowHuntressCrosshair)
        return color;
    
    // Calculate center of screen with adjustable vertical offset
    float2 center = float2(0.5, HuntressCrosshairVerticalOffset);
    
    // Calculate distance from center in pixels
    float2 pixelPos = texcoord * ReShade::ScreenSize;
    float2 centerPos = center * ReShade::ScreenSize;
    float2 delta = abs(pixelPos - centerPos);
    
    // Horizontal line
    bool isHorizontal = (delta.y < CrosshairThickness) && (delta.x < CrosshairSize);
    
    // Vertical line
    bool isVertical = (delta.x < CrosshairThickness) && (delta.y < CrosshairSize);
    
    // Draw crosshair
    if (isHorizontal || isVertical)
    {
        color = CrosshairColor;
    }
    
    return color;
}

// Wesker Crosshair
float3 PS_DashLine(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    
    if (!ShowDashLine)
        return color;
    
    float horizontalCenter = 0.5;
    float verticalCenter = 0.4;
    
    // Only process pixels in the bottom half and center column area
    if (texcoord.y < verticalCenter || abs(texcoord.x - horizontalCenter) > 0.05)
        return color;
    
    // Calculate vertical position (0 at center, 1 at bottom)
    float verticalPos = (texcoord.y - verticalCenter) / (1.0 - verticalCenter);
    
    // Thickness varies: thicker at bottom, thinner at top
    float thicknessAtBottom = 0.025; // Width at bottom
    float thicknessAtTop = 0.013;    // Width at top
    float thickness = lerp(thicknessAtTop, thicknessAtBottom, verticalPos);
    
    // Distance from center horizontally
    float distFromCenter = abs(texcoord.x - horizontalCenter);
    
    // Distance from top edge (for rounding)
    float distFromTop = texcoord.y - verticalCenter;
    float roundingRadius = 0.01; // Radius of the rounded top
    
    // Rounded top cap calculation
    float topCapFactor = 1.0;
    if (distFromTop < roundingRadius)
    {
        // Create a circular cap at the top
        float2 capCenter = float2(horizontalCenter, verticalCenter + roundingRadius);
        float distToCapCenter = distance(texcoord, capCenter);
        
        // Only draw if within the circular radius
        if (distToCapCenter > roundingRadius)
            return color;
        
        // Adjust effective horizontal distance for the rounded top
        distFromCenter = distToCapCenter - roundingRadius + distFromCenter;
    }
    
    // Check if we're within the tapered line width
    if (distFromCenter < thickness)
    {
        // Horizontal edge softness (side blur)
        float edgeSoftness = 0.2; // Higher = more blur
        float edgeDist = distFromCenter / thickness;
        float softEdge = smoothstep(1.0 - edgeSoftness, 1.0, edgeDist);
        
        // Vertical top fade/blur (soft rounded top)
        float topFadeDistance = 0.2;
        float topFade = smoothstep(0.0, topFadeDistance, distFromTop);
        
        // Combine both softness factors
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
    pass AntiGreenFilter
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AntiGreen;
    }

    pass AntiYellowFilter
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AntiYellow;
    }

    pass ColorReplacement
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_RedEnhance;
    }

    pass BrightnessEnhancement
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_BrightnessEnhance;
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
