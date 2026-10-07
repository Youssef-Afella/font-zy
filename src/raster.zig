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
            r.drawLine(x0, y0, x2, y2); //Directly draw straight paths
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

    inline fn add(r: *Raster, index: usize, v: f32) void {
        const flag = r.bitmap[index];
        if (flag == 0) {
            r.buffer[index] = v * 255;
            r.bitmap[index] = 255;
        } else {
            r.buffer[index] += v * 255;
        }
    }

    fn drawLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        if (@abs(y0 - y1) <= std.math.floatEps(f32)) return; //Reject horizontal lines

        const w: i32 = @intCast(r.width);

        const dx = x1 - x0;
        const dy = y1 - y0;

        const sx: i32 = if (dx < 0) -1 else 1;
        const sy: i32 = if (dy < 0) -w else w;
        const sx_f: f32 = if (dx < 0) -1.0 else 1.0;
        const sy_f: f32 = if (dy < 0) -1.0 else 1.0;
        const ssx = @sqrt(1.0 / (dx * dx));
        const ssy = @sqrt(1.0 / (dy * dy));

        var plane_x: f32 = if (dx < 0) @floor(x0) - x0 else @floor(x0) + 1 - x0;
        var plane_y: f32 = if (dy < 0) @floor(y0) - y0 else @floor(y0) + 1 - y0;
        var tx: f32 = if (dx < 0) -plane_x * ssx else plane_x * ssx;
        var ty: f32 = if (dy < 0) -plane_y * ssy else plane_y * ssy;

        var px: f32 = @floor(x0) - x0;
        var x: f32 = 0;
        var y: f32 = 0;

        var index: i32 = @as(i32, @intFromFloat(x0)) + @as(i32, @intFromFloat(y0)) * w;
        var iter: u32 = @intFromFloat(@abs(@floor(x0) - @floor(x1)) + @abs(@floor(y0) - @floor(y1)));

        std.mem.doNotOptimizeAway(tx);
        std.mem.doNotOptimizeAway(ty);

        if (true) return;

        while (iter > 0) : (iter -= 1) {
            const prev_index = index;
            const prev_x = x;
            const prev_y = y;
            const prev_px = px;

            if (tx < ty) {
                x = plane_x;
                y = tx * dy;
                tx += ssx;
                index += sx;
                px += sx_f;
                plane_x += sx_f;
            } else {
                x = ty * dx;
                y = plane_y;
                ty += ssy;
                index += sy;
                plane_y += sy_f;
            }

            const height = y - prev_y;
            const left = ((x + prev_x) * 0.5 - prev_px) * height;
            const right = height - left;

            r.add(@intCast(prev_index), right);
            r.add(@intCast(prev_index + 1), left);
        }

        const height = y1 - y0 - y;
        const left = ((x1 - x0 + x) * 0.5 - px) * height;
        const right = height - left;

        r.add(@intCast(index), right);
        r.add(@intCast(index + 1), left);
    }
};
