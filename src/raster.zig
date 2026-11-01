const std = @import("std");

const Edge = @import("font.zig").Edge;
const GlyphMetrics = @import("font.zig").GlyphMetrics;

pub const Raster = struct {
    a: []f32,
    b: []u8,
    w: u32,
    h: u32,
    mx: f32,
    my: f32,

    pub fn init(buffer: []f32, bitmap: []u8, width: u32, height: u32) Raster {
        @memset(bitmap, 0);

        const mx: u32 = @bitCast(@as(f32, @floatFromInt(width)));
        const my: u32 = @bitCast(@as(f32, @floatFromInt(height)));

        return .{
            .a = buffer,
            .b = bitmap,
            .w = width,
            .h = height,
            .mx = @bitCast(mx -% 1),
            .my = @bitCast(my -% 1),
        };
    }

    pub inline fn draw(r: *Raster, m_lines: []Edge, v_lines: []Edge, metrics: *const GlyphMetrics) void {
        for (v_lines) |line| {
            const cx0 = @min(line.x0 * metrics.scale + metrics.offset_x, r.mx);
            const cy0 = @min(line.y0 * metrics.scale + metrics.offset_y, r.my);
            const cy1 = @min(line.y1 * metrics.scale + metrics.offset_y, r.my);

            r.drawVLine(cx0, cy0, cy1);
        }

        for (m_lines) |line| {
            const cx0 = @min(line.x0 * metrics.scale + metrics.offset_x, r.mx);
            const cx1 = @min(line.x1 * metrics.scale + metrics.offset_x, r.mx);
            const cy0 = @min(line.y0 * metrics.scale + metrics.offset_y, r.my);
            const cy1 = @min(line.y1 * metrics.scale + metrics.offset_y, r.my);

            r.drawMLine(cx0, cy0, cx1, cy1);
        }
    }

    pub inline fn fill(r: *Raster) void {
        const stride = u64;
        const stride_len = @sizeOf(stride);
        const stride_mask = std.math.maxInt(stride) / 0xFF;

        var acc: f32 = 0.0;
        var k: u32 = 0;

        const len = r.b.len & ~@as(usize, stride_len - 1);

        while (k < len) : (k += stride_len) {
            const p: *align(1) stride = @ptrCast(r.b[k..].ptr);
            const mask: stride = p.*;

            if (mask == 0) {
                const v: u8 = @trunc(@max(0.0, @min(acc * 255.9, 255.0)));
                p.* = @as(stride, v) * stride_mask;
            } else {
                inline for (0..stride_len) |i| {
                    if (r.b[k + i] != 0) {
                        acc += r.a[k + i];
                    }
                    r.b[k + i] = @trunc(@max(0.0, @min(acc * 255.9, 255.0)));
                }
            }
        }

        while (k < r.b.len) : (k += 1) {
            if (r.b[k] != 0) {
                acc += r.a[k];
            }
            r.b[k] = @trunc(@max(0.0, @min(acc * 255.9, 255.0)));
        }
    }

    inline fn add(r: *Raster, i: usize, v0: f32, v1: f32) void {
        const flag0 = r.b[i];
        const flag1 = r.b[i + 1];

        if (flag0 == 0) {
            r.a[i] = v0;
            r.b[i] = 255;
        } else {
            r.a[i] += v0;
        }

        if (flag1 == 0) {
            r.a[i + 1] = v1;
            r.b[i + 1] = 255;
        } else {
            r.a[i + 1] += v1;
        }
    }

    inline fn drawVLine(r: *Raster, x0: f32, y0: f32, y1: f32) void {
        const w: i32 = @intCast(r.w);

        const x0i: i32 = @trunc(x0);
        const y0i: i32 = @trunc(y0);
        const y1i: i32 = @trunc(y1);

        const x0f: f32 = @floatFromInt(x0i);
        const y0f: f32 = @floatFromInt(y0i);

        const dy = y1 - y0;

        var sy: i32 = undefined;
        var sy_f: f32 = undefined;
        var idy: f32 = undefined;
        var plane_y: f32 = undefined;
        var ty: f32 = undefined;

        if (dy < 0.0) {
            sy = -w;
            sy_f = -1.0;
            idy = -1.0 / dy;
            plane_y = y0f - y0;
            ty = -plane_y * idy;
        } else {
            sy = w;
            sy_f = 1.0;
            idy = 1.0 / dy;
            plane_y = y0f - y0 + 1;
            ty = plane_y * idy;
        }

        const x: f32 = x0 - x0f;
        var y: f32 = 0;

        var i: i32 = x0i + y0i * w;
        var iter: u32 = @abs(y0i - y1i);

        while (iter > 0) : (iter -= 1) {
            const prev_i = i;
            const prev_y = y;

            y = plane_y;
            ty += idy;
            i += sy;
            plane_y += sy_f;

            const height = y - prev_y;
            const left = x * height;
            r.add(@intCast(prev_i), height - left, left);
        }

        const height = dy - y;
        const left = x * height;
        r.add(@intCast(i), height - left, left);
    }

    inline fn drawMLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        const w: i32 = @intCast(r.w);

        const x0i: i32 = @trunc(x0);
        const x1i: i32 = @trunc(x1);
        const y0i: i32 = @trunc(y0);
        const y1i: i32 = @trunc(y1);

        const x0f: f32 = @floatFromInt(x0i);
        const y0f: f32 = @floatFromInt(y0i);

        const dx = (x1 - x0) * 0.5;
        const dy = y1 - y0;
        var px = x0f - x0;

        var sx: i32 = undefined;
        var sx_f: f32 = undefined;
        var sx_hf: f32 = undefined;
        var idx: f32 = undefined;
        var plane_x: f32 = undefined;
        var tx: f32 = undefined;

        if (dx < 0.0) {
            sx = -1;
            sx_f = -1.0;
            sx_hf = -0.5;
            plane_x = px;
            idx = -0.5 / dx;
            tx = -plane_x * idx;
        } else {
            sx = 1;
            sx_f = 1.0;
            sx_hf = 0.5;
            plane_x = px + 1;
            idx = 0.5 / dx;
            tx = plane_x * idx;
        }

        var sy: i32 = undefined;
        var sy_f: f32 = undefined;
        var idy: f32 = undefined;
        var plane_y: f32 = undefined;
        var ty: f32 = undefined;

        if (dy < 0.0) {
            sy = -w;
            sy_f = -1.0;
            idy = -1.0 / dy;
            plane_y = y0f - y0;
            ty = -plane_y * idy;
        } else {
            sy = w;
            sy_f = 1.0;
            idy = 1.0 / dy;
            plane_y = y0f - y0 + 1;
            ty = plane_y * idy;
        }

        var x: f32 = 0;
        var y: f32 = 0;
        plane_x *= 0.5;

        var i: i32 = x0i + y0i * w;
        var iter: u32 = @abs(x0i - x1i) + @abs(y0i - y1i);

        while (iter > 0) : (iter -= 1) {
            const prev_i = i;
            const prev_x = x;
            const prev_y = y;
            const prev_px = px;

            if (tx < ty) {
                x = plane_x;
                y = tx * dy;
                tx += idx;
                i += sx;
                px += sx_f;
                plane_x += sx_hf;
            } else {
                x = ty * dx;
                y = plane_y;
                ty += idy;
                i += sy;
                plane_y += sy_f;
            }

            const height = y - prev_y;
            const left = (x + prev_x - prev_px) * height;
            r.add(@intCast(prev_i), height - left, left);
        }

        const height = dy - y;
        const left = (dx + x - px) * height;
        r.add(@intCast(i), height - left, left);
    }
};
