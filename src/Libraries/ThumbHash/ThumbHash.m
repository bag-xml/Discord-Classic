#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

static inline float clamp(float value, float minVal, float maxVal) {
    return fminf(fmaxf(value, minVal), maxVal);
}

typedef struct {
    int width;
    int height;
    NSData *rgba;
} ThumbHashResult;

ThumbHashResult thumbHashToRGBA(NSData *hash) {
    const uint8_t *bytes = hash.bytes;
    
    uint32_t h0 = bytes[0];
    uint32_t h1 = bytes[1];
    uint32_t h2 = bytes[2];
    uint16_t h3 = bytes[3];
    uint16_t h4 = bytes[4];
    
    uint32_t header24 = h0 | (h1 << 8) | (h2 << 16);
    uint16_t header16 = h3 | (h4 << 8);
    
    uint32_t il_dc = header24 & 63;
    uint32_t ip_dc = (header24 >> 6) & 63;
    uint32_t iq_dc = (header24 >> 12) & 63;
    
    float l_dc = il_dc / 63.0f;
    float p_dc = ip_dc / 31.5f - 1.0f;
    float q_dc = iq_dc / 31.5f - 1.0f;
    
    uint32_t il_scale = (header24 >> 18) & 31;
    float l_scale = il_scale / 31.0f;
    
    BOOL hasAlpha = (header24 >> 23) != 0;
    
    uint32_t ip_scale = (header16 >> 3) & 63;
    uint32_t iq_scale = (header16 >> 9) & 63;
    
    float p_scale = ip_scale / 63.0f;
    float q_scale = iq_scale / 63.0f;
    
    BOOL isLandscape = (header16 >> 15) != 0;
    
    uint32_t lx16 = fmax(3, isLandscape ? (hasAlpha ? 5 : 7) : (header16 & 7));
    uint32_t ly16 = fmax(3, isLandscape ? (header16 & 7) : (hasAlpha ? 5 : 7));
    int lx = (int)lx16;
    int ly = (int)ly16;
    
    float a_dc = 1.0f;
    float a_scale = 1.0f;
    
    if (hasAlpha) {
        uint8_t ia_dc = bytes[5] & 15;
        uint8_t ia_scale = bytes[5] >> 4;
        a_dc = ia_dc / 15.0f;
        a_scale = ia_scale / 15.0f;
    }
    
    int ac_start = hasAlpha ? 6 : 5;
    __block int ac_index = 0;
    
    NSMutableArray *(^decodeChannel)(int, int, float) = ^(int nx, int ny, float scale) {
        NSMutableArray *ac = [NSMutableArray array];
        for (int cy = 0; cy < ny; cy++) {
            int cx = cy > 0 ? 0 : 1;
            while (cx * ny < nx * (ny - cy)) {
                int iac = (bytes[ac_start + (ac_index >> 1)] >> ((ac_index & 1) << 2)) & 15;
                float fac = (iac / 7.5f - 1.0f) * scale;
                [ac addObject:@(fac)];
                ac_index++;
                cx++;
            }
        }
        return ac;
    };
    
    NSArray *l_ac = decodeChannel(lx, ly, l_scale);
    NSArray *p_ac = decodeChannel(3, 3, p_scale * 1.25f);
    NSArray *q_ac = decodeChannel(3, 3, q_scale * 1.25f);
    NSArray *a_ac = hasAlpha ? decodeChannel(5, 5, a_scale) : @[];
    
    // Approximate aspect ratio (simplified)
    float ratio = (float)lx / (float)ly;
    float fw = roundf(ratio > 1 ? 32.0f : 32.0f * ratio);
    float fh = roundf(ratio > 1 ? 32.0f / ratio : 32.0f);
    int w = (int)fw;
    int h = (int)fh;

    NSMutableData *rgba = [NSMutableData dataWithLength:w * h * 4];
    uint8_t *rgbaBytes = (uint8_t *)rgba.mutableBytes;

    int cx_stop = MAX(lx, hasAlpha ? 5 : 3);
    int cy_stop = MAX(ly, hasAlpha ? 5 : 3);
    float *fx = calloc(cx_stop, sizeof(float));
    float *fy = calloc(cy_stop, sizeof(float));

    int offset = 0;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            float l = l_dc, p = p_dc, q = q_dc, a = a_dc;

            for (int cx = 0; cx < cx_stop; cx++) {
                fx[cx] = cosf(M_PI / fw * (x + 0.5f) * cx);
            }
            for (int cy = 0; cy < cy_stop; cy++) {
                fy[cy] = cosf(M_PI / fh * (y + 0.5f) * cy);
            }

            // Decode L
            int j = 0;
            for (int cy = 0; cy < ly; cy++) {
                int cx = cy > 0 ? 0 : 1;
                float fy2 = fy[cy] * 2;
                while (cx * ly < lx * (ly - cy)) {
                    l += [l_ac[j] floatValue] * fx[cx] * fy2;
                    j++;
                    cx++;
                }
            }

            // Decode P, Q
            j = 0;
            for (int cy = 0; cy < 3; cy++) {
                int cx = cy > 0 ? 0 : 1;
                float fy2 = fy[cy] * 2;
                while (cx < 3 - cy) {
                    float f = fx[cx] * fy2;
                    p += [p_ac[j] floatValue] * f;
                    q += [q_ac[j] floatValue] * f;
                    j++;
                    cx++;
                }
            }

            // Decode A
            if (hasAlpha) {
                j = 0;
                for (int cy = 0; cy < 5; cy++) {
                    int cx = cy > 0 ? 0 : 1;
                    float fy2 = fy[cy] * 2;
                    while (cx < 5 - cy) {
                        a += [a_ac[j] floatValue] * fx[cx] * fy2;
                        j++;
                        cx++;
                    }
                }
            }

            // Convert to RGBA
            float b = l - 2.0f / 3.0f * p;
            float r = (3.0f * l - b + q) / 2.0f;
            float g = r - q;

            rgbaBytes[offset++] = (uint8_t)(clamp(r, 0, 1) * 255);
            rgbaBytes[offset++] = (uint8_t)(clamp(g, 0, 1) * 255);
            rgbaBytes[offset++] = (uint8_t)(clamp(b, 0, 1) * 255);
            rgbaBytes[offset++] = (uint8_t)(clamp(a, 0, 1) * 255);
        }
    }

    free(fx);
    free(fy);

    ThumbHashResult result;
    result.width = w;
    result.height = h;
    result.rgba = [rgba copy];
    return result;
}

UIImage *thumbHashToImage(NSData *hash) {
    ThumbHashResult result = thumbHashToRGBA(hash);
    int w = result.width;
    int h = result.height;
    NSMutableData *rgbaData = [result.rgba mutableCopy];
    uint8_t *rgba = (uint8_t *)rgbaData.mutableBytes;
    
    int n = w * h;
    for (int i = 0; i < n; i++) {
        uint8_t *px = rgba + i * 4;
        uint8_t a = px[3];
        if (a < 255) {
            uint16_t r = px[0];
            uint16_t g = px[1];
            uint16_t b = px[2];
            px[0] = (uint8_t)MIN(255, (r * a) / 255);
            px[1] = (uint8_t)MIN(255, (g * a) / 255);
            px[2] = (uint8_t)MIN(255, (b * a) / 255);
        }
    }

    // Create CGImage
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgbaData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast;

    CGImageRef cgImage = CGImageCreate(
        w,
        h,
        8,
        32,
        w * 4,
        colorSpace,
        bitmapInfo,
        provider,
        NULL,
        true,
        kCGRenderingIntentPerceptual
    );

    UIImage *image = [UIImage imageWithCGImage:cgImage];

    // Cleanup
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    return image;
}

