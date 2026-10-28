const std = @import("std");

pub const Raster = struct {
    a: []f32,
    b: []u8,
    w: u32,
    h: u32,

    pub fn init(buffer: []f32, bitmap: []u8, width: u32, height: u32) Raster {
        @memset(bitmap, 0);

        return .{
            .a = buffer,
            .b = bitmap,
            .w = width,
            .h = height,
        };
    }

    pub inline fn drawLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        const xmax: f32 = @as(f32, @floatFromInt(r.w)) - 0.001;
        const ymax: f32 = @as(f32, @floatFromInt(r.h)) - 0.001;

        const x0c = @min(x0, xmax);
        const y0c = @min(y0, ymax);
        const y1c = @min(y1, ymax);
        const x1c = @min(x1, xmax);

        if (@abs(x0 - x1) < 0.001) {
            r.drawVLine(x0c, y0c, y1c);
        } else {
            r.drawSLine(x0c, y0c, x1c, y1c);
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
                const v: u8 = @intFromFloat(@max(0.0, @min(acc * 255.0, 255.0)));
                p.* = @as(stride, v) * stride_mask;
            } else {
                inline for (0..stride_len) |i| {
                    if (r.b[k + i] != 0) {
                        acc += r.a[k + i];
                    }
                    r.b[k + i] = @intFromFloat(@max(0.0, @min(acc * 255.0, 255.0)));
                }
            }
        }

        while (k < r.b.len) : (k += 1) {
            if (r.b[k] != 0) acc += r.a[k];
            r.b[k] = @intFromFloat(@max(0.0, @min(acc * 255.0, 255.0)));
        }
    }

    inline fn add(r: *Raster, i: usize, v0: f32, v1: f32) void {
        const flag0 = r.b[i];

        if (flag0 == 0) {
            r.a[i] = v0;
            r.b[i] = 255;
        } else {
            r.a[i] += v0;
        }

        if (i == r.b.len - 1) return;

        const flag1 = r.b[i + 1];

        if (flag1 == 0) {
            r.a[i + 1] = v1;
            r.b[i + 1] = 255;
        } else {
            r.a[i + 1] += v1;
        }
    }

    inline fn drawVLine(r: *Raster, x0: f32, y0: f32, y1: f32) void {
        const w: i32 = @intCast(r.w);

        const x0i: i32 = @intFromFloat(x0);
        const y0i: i32 = @intFromFloat(y0);
        const y1i: i32 = @intFromFloat(y1);

        const x0f: f32 = @floatFromInt(x0i);
        const y0f: f32 = @floatFromInt(y0i);

        const dy = y1 - y0;

        const sy: i32 = if (dy < 0) -w else w;
        const sy_f: f32 = if (dy < 0) -1.0 else 1.0;
        const idy = sy_f / dy;
        var plane_y = if (dy < 0) y0f - y0 else y0f - y0 + 1;
        var ty = if (dy < 0) -plane_y * idy else plane_y * idy;

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
            const right = height - left;
            r.add(@intCast(prev_i), right, left);
        }

        const height = dy - y;
        const left = x * height;
        const right = height - left;
        r.add(@intCast(i), right, left);
    }

    inline fn drawSLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        const w: i32 = @intCast(r.w);

        const x0i: i32 = @intFromFloat(x0);
        const x1i: i32 = @intFromFloat(x1);
        const y0i: i32 = @intFromFloat(y0);
        const y1i: i32 = @intFromFloat(y1);

        const x0f: f32 = @floatFromInt(x0i);
        const y0f: f32 = @floatFromInt(y0i);

        const dx = (x1 - x0) * 0.5;
        const dy = y1 - y0;

        const sx: i32 = if (dx < 0) -1 else 1;
        const sx_f: f32 = if (dx < 0) -1.0 else 1.0;
        const sx_hf: f32 = if (dx < 0) -0.5 else 0.5;
        const idx = sx_hf / dx;
        var plane_x = if (dx < 0) x0f - x0 else x0f - x0 + 1;
        var tx = if (dx < 0) -plane_x * idx else plane_x * idx;

        const sy: i32 = if (dy < 0) -w else w;
        const sy_f: f32 = if (dy < 0) -1.0 else 1.0;
        const idy = sy_f / dy;
        var plane_y = if (dy < 0) y0f - y0 else y0f - y0 + 1;
        var ty = if (dy < 0) -plane_y * idy else plane_y * idy;

        var px: f32 = x0f - x0;
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
            const right = height - left;
            r.add(@intCast(prev_i), right, left);
        }

        const height = dy - y;
        const left = (dx + x - px) * height;
        const right = height - left;
        r.add(@intCast(i), right, left);
    }
};
