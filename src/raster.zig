pub const Raster = struct {
    width: u32,
    height: u32,
    buffer: []f32,
    bitmap: []u8,

    pub fn init(width: u32, height: u32, buffer: []f32, bitmap: []u8) Raster {
        @memset(bitmap, 0);

        return .{
            .width = width,
            .height = height,
            .buffer = buffer,
            .bitmap = bitmap,
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
        if (y1 == y0 and y1 == y2) return; //Reject horizontal paths

        const ax = x0 - 2 * x1 + x2;
        const bx = x1 - x0;
        const ay = y0 - 2 * y1 + y2;
        const by = y1 - y0;

        var tx: f32 = 1.0;
        if (@abs(ax) > 0.0001) {
            const ttx = -bx / ax;
            if (ttx > 0.0 and ttx < 1.0) tx = ttx;
        }

        var ty: f32 = 1.0;
        if (@abs(ay) > 0.0001) {
            const tty = -by / ay;
            if (tty > 0.0 and tty < 1.0) ty = tty;
        }

        const tmin = @min(tx, ty);
        const tmax = @max(tx, ty);

        const curve: Quadratic = .{ .x0 = x0, .y0 = y0, .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2 };

        if (tmin >= 1.0) {
            r.rasterMonotoneQuadratic(curve);
        } else if (tmax >= 1.0 or tmin == tmax) {
            const curves = splitCurve(curve, tmin);
            r.rasterMonotoneQuadratic(curves[0]);
            r.rasterMonotoneQuadratic(curves[1]);
        } else {
            const outer = splitCurve(curve, tmax);
            const inner = splitCurve(outer[0], tmin / tmax);
            r.rasterMonotoneQuadratic(inner[0]);
            r.rasterMonotoneQuadratic(inner[1]);
            r.rasterMonotoneQuadratic(outer[1]);
        }
    }

    fn rasterMonotoneQuadratic(r: *Raster, c: Quadratic) void {
        const sx: i32 = if (c.x2 < c.x0) -1 else 1;
        const sy: i32 = if (c.y2 < c.y0) -1 else 1;
        const sx_f: f32 = @floatFromInt(sx);
        const sy_f: f32 = @floatFromInt(sy);

        const ax = c.x0 - 2 * c.x1 + c.x2;
        const iax = 1.0 / ax;
        const bx = c.x1 - c.x0;
        const i2bx = 0.5 / bx;

        var fx: u8 = 3;
        if (@abs(ax) < 0.0001) {
            if (@abs(bx) > 0.0001) {
                fx = 0;
            }
        } else if (sx > 0) {
            fx = 1;
        } else {
            fx = 2;
        }

        const ay = c.y0 - 2 * c.y1 + c.y2;
        const iay = 1.0 / ay;
        const by = c.y1 - c.y0;
        const i2by = 0.5 / by;

        var fy: u8 = 3;
        if (@abs(ay) < 0.0001) {
            if (@abs(by) > 0.0001) {
                fy = 0;
            }
        } else if (sy > 0) {
            fy = 1;
        } else {
            fy = 2;
        }

        var plane_x: f32 = if (sx > 0) @floor(c.x0) + 1 else @ceil(c.x0) - 1;
        var plane_y: f32 = if (sy > 0) @floor(c.y0) + 1 else @ceil(c.y0) - 1;

        const mid_x: f32 = @floor((c.x0 + plane_x) * 0.5);
        const delay: f32 = plane_x - mid_x;
        var cell_x: i32 = @intFromFloat(mid_x);
        var cell_y: i32 = @intFromFloat((c.y0 + plane_y) * 0.5);

        var x = c.x0;
        var y = c.y0;

        while (true) {
            const tx = intersectCurve(ax, iax, bx, i2bx, plane_x - c.x0, fx);
            const ty = intersectCurve(ay, iay, by, i2by, plane_y - c.y0, fy);
            const t = @min(tx, ty);

            var ix: f32 = undefined;
            var iy: f32 = undefined;

            if (t >= 1.0) {
                ix = c.x2;
                iy = c.y2;
            } else if (tx < ty) {
                ix = plane_x;
                iy = ay * tx * tx + 2.0 * by * tx + c.y0;
            } else {
                ix = ax * ty * ty + 2.0 * bx * ty + c.x0;
                iy = plane_y;
            }

            const signed_height = iy - y;
            const trapzoid_right = ((x + ix) * 0.5 - plane_x + delay) * signed_height;
            const trapzoid_left = signed_height - trapzoid_right;

            const index: usize = @intCast(cell_y * @as(i32, @intCast(r.width)) + cell_x);

            const flag0 = r.bitmap[index];
            if (flag0 == 0) {
                r.buffer[index] = trapzoid_left * 255;
                r.bitmap[index] = 255;
            } else {
                r.buffer[index] += trapzoid_left * 255;
            }

            const flag1 = r.bitmap[index + 1];
            if (flag1 == 0) {
                r.buffer[index + 1] = trapzoid_right * 255;
                r.bitmap[index + 1] = 255;
            } else {
                r.buffer[index + 1] += trapzoid_right * 255;
            }

            if (t >= 1.0) break;

            x = ix;
            y = iy;

            if (tx < ty) {
                plane_x += sx_f;
                cell_x += sx;
            } else {
                plane_y += sy_f;
                cell_y += sy;
            }
        }
    }

    fn splitCurve(c: Quadratic, t: f32) [2]Quadratic {
        const apx = c.x0 * (1 - t) + c.x1 * t;
        const apy = c.y0 * (1 - t) + c.y1 * t;

        const bpx = c.x1 * (1 - t) + c.x2 * t;
        const bpy = c.y1 * (1 - t) + c.y2 * t;

        const splitx = apx * (1 - t) + bpx * t;
        const splity = apy * (1 - t) + bpy * t;

        const c0: Quadratic = .{ .x0 = c.x0, .y0 = c.y0, .x1 = apx, .y1 = apy, .x2 = splitx, .y2 = splity };
        const c1: Quadratic = .{ .x0 = splitx, .y0 = splity, .x1 = bpx, .y1 = bpy, .x2 = c.x2, .y2 = c.y2 };

        return .{ c0, c1 };
    }

    inline fn intersectCurve(a: f32, ia: f32, b: f32, i2b: f32, c: f32, s: u8) f32 {
        var t: f32 = 10000.0;
        switch (s) {
            0 => {
                t = c * i2b;
            },
            1 => {
                const d = b * b + a * c;
                if (d >= 0.0) t = (-b + @sqrt(d)) * ia;
            },
            2 => {
                const d = b * b + a * c;
                if (d >= 0.0) t = (-b - @sqrt(d)) * ia;
            },
            else => {},
        }
        return if (t < 0.0 or t > 1.0) 10000.0 else t;
    }

    const Quadratic = struct {
        x0: f32,
        y0: f32,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
    };
};
