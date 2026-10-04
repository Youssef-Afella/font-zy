const std = @import("std");

pub const Raster = struct {
    width: u32,
    height: u32,
    buffer: []f32,
    bitmap: []u8,
    iter: u32,

    pub fn init(width: u32, height: u32, buffer: []f32, bitmap: []u8) Raster {
        @memset(bitmap, 0);

        return .{
            .width = width,
            .height = height,
            .buffer = buffer,
            .bitmap = bitmap,
            .iter = 0,
        };
    }

    pub fn fill(r: *Raster) void {
        var acc: f32 = 0.0;
        var k: u32 = 0;

        const aligned_len = r.bitmap.len & ~@as(usize, 3);

        while (k < aligned_len) : (k += 4) {
            const p: *align(1) u32 = @ptrCast(r.bitmap[k..].ptr);
            const mask: u32 = p.*;

            if (mask == 0) {
                const v: u8 = @intFromFloat(@max(0.0, @min(acc, 255.0)));
                p.* = @as(u32, v) * 0x01010101;
            } else {
                inline for (0..4) |i| {
                    if (r.bitmap[k + i] != 0) acc += r.buffer[k + i];
                    r.bitmap[k + i] = @intFromFloat(@max(0.0, @min(acc, 255.0)));
                }
            }
        }

        while (k < r.bitmap.len) : (k += 1) {
            if (r.bitmap[k] != 0) acc += r.buffer[k];
            r.bitmap[k] = @intFromFloat(@max(0.0, @min(acc, 255.0)));
        }
    }

    pub fn drawQuadratic(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32) void {
        const eps = std.math.floatEps(f32);
        if (@abs(y0 - y1) <= eps and @abs(y2 - y1) <= eps) return; //Reject horizontal paths

        const devx = x0 - 2.0 * x1 + x2;
        const devy = y0 - 2.0 * y1 + y2;
        const devsq = devx * devx + devy * devy;
        if (devsq < 0.333) {
            r.drawLine(x0, y0, x2, y2); //Directly draw vertical paths
            return;
        }

        const tol = 3.0;
        const n: f32 = 1.0 + @floor(@sqrt(@sqrt(tol * (devx * devx + devy * devy))));

        var px = x0;
        var py = y0;

        const nrecip = 1.0 / n;
        var t: f32 = 0.0;

        for (0..@as(usize, @intFromFloat(n - 1))) |i| {
            _ = i;

            t += nrecip;
            const tt = 1.0 - t;

            const xx0 = tt * x0 + t * x1;
            const xx1 = tt * x1 + t * x2;
            const x = tt * xx0 + t * xx1;

            const yy0 = tt * y0 + t * y1;
            const yy1 = tt * y1 + t * y2;
            const y = tt * yy0 + t * yy1;

            r.drawLine(px, py, x, y);

            px = x;
            py = y;
        }

        r.drawLine(px, py, x2, y2);
    }

    fn drawLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        if (@abs(y0 - y1) <= std.math.floatEps(f32)) return; //Reject horizontal lines

        var px: i32 = @intFromFloat(x0);
        var py: i32 = @intFromFloat(y0);

        const dx = x1 - x0;
        const dy = y1 - y0;
        const dx2 = dx * dx;
        const dy2 = dy * dy;
        const norm = 1.0 / @sqrt(dx2 + dy2);

        const sx: i32 = if (dx < 0) -1 else 1;
        const sy: i32 = if (dy < 0) -1 else 1;
        const ssx = @sqrt(1.0 + dy2 / dx2) * norm;
        const ssy = @sqrt(1.0 + dx2 / dy2) * norm;

        var tx: f32 = if (dx < 0) (x0 - @floor(x0)) * ssx else (@floor(x0) + 1 - x0) * ssx;
        var ty: f32 = if (dy < 0) (y0 - @floor(y0)) * ssy else (@floor(y0) + 1 - y0) * ssy;

        var x: f32 = x0;
        var y: f32 = 0;

        while (true) {
            const t = @min(1.0, @min(tx, ty));

            const ix: f32 = x0 + t * dx;
            const iy: f32 = t * dy;

            const height = iy - y;
            const qx: f32 = @floatFromInt(px);
            const trapzoid_left = ((x + ix) * 0.5 - qx) * height;
            const trapzoid_right = height - trapzoid_left;

            const index: usize = @intCast(py * @as(i32, @intCast(r.width)) + px);

            const flag0 = r.bitmap[index];
            if (flag0 == 0) {
                r.buffer[index] = trapzoid_right * 255;
                r.bitmap[index] = 255;
            } else {
                r.buffer[index] += trapzoid_right * 255;
            }

            const flag1 = r.bitmap[index + 1];
            if (flag1 == 0) {
                r.buffer[index + 1] = trapzoid_left * 255;
                r.bitmap[index + 1] = 255;
            } else {
                r.buffer[index + 1] += trapzoid_left * 255;
            }

            if (t >= 1.0) break;

            x = ix;
            y = iy;

            if (tx < ty) {
                px += sx;
                tx += ssx;
            } else {
                py += sy;
                ty += ssy;
            }

            if (px < 0 or px >= r.width or py < 0 or py >= r.height) break;
        }
    }
};
