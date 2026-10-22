pub const Raster = struct {
    a: []f32,
    b: []u8,
    w: u32,

    pub fn init(buffer: []f32, bitmap: []u8, width: u32) Raster {
        @memset(bitmap, 0);

        return .{
            .a = buffer,
            .b = bitmap,
            .w = width,
        };
    }

    pub inline fn fill(r: *Raster) void {
        var acc: f32 = 0.0;
        var k: u32 = 0;

        const len = r.b.len & ~@as(usize, 7);

        while (k < len) : (k += 8) {
            const p: *align(1) u64 = @ptrCast(r.b[k..].ptr);
            const mask: u64 = p.*;

            if (mask == 0) {
                const v: u8 = @intFromFloat(@max(0.0, @min(acc, 255.0)));
                p.* = @as(u64, v) * 0x0101010101010101;
            } else {
                inline for (0..8) |i| {
                    if (r.b[k + i] != 0) acc += r.a[k + i];
                    r.b[k + i] = @intFromFloat(@max(0.0, @min(acc, 255.0)));
                }
            }
        }

        while (k < r.b.len) : (k += 1) {
            if (r.b[k] != 0) acc += r.a[k];
            r.b[k] = @intFromFloat(@max(0.0, @min(acc, 255.0)));
        }
    }

    inline fn add(r: *Raster, i: usize, v: f32) void {
        const flag = r.b[i];
        if (flag == 0) {
            r.a[i] = v * 255;
            r.b[i] = 255;
        } else {
            r.a[i] += v * 255;
        }
    }

    pub inline fn drawLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        const eps = 0.0001;
        if (@abs(x0 - x1) <= eps) {
            r.drawVLine(x0, y0, y1);
        } else {
            r.drawSLine(x0, y0, x1, y1);
        }
    }

    inline fn drawVLine(r: *Raster, x0: f32, y0: f32, y1: f32) void {
        const w: i32 = @intCast(r.w);

        const x0i: f32 = @floor(x0);
        const y0i: f32 = @floor(y0);
        const y1i: f32 = @floor(y1);

        const dy = y1 - y0;
        const idy = 1.0 / @abs(dy);

        const sy: i32 = if (dy < 0) -w else w;
        const sy_f: f32 = if (dy < 0) -1.0 else 1.0;
        var plane_y = if (dy < 0) y0i - y0 else y0i - y0 + 1;
        var ty = if (dy < 0) -plane_y * idy else plane_y * idy;

        const x: f32 = x0 - x0i;
        var y: f32 = 0;

        var i: i32 = @as(i32, @intFromFloat(x0)) + @as(i32, @intFromFloat(y0)) * w;
        var iter: u32 = @intFromFloat(@abs(y0i - y1i));

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

            r.add(@intCast(prev_i), right);
            r.add(@intCast(prev_i + 1), left);
        }

        const height = dy - y;
        const left = x * height;
        const right = height - left;

        r.add(@intCast(i), right);
        r.add(@intCast(i + 1), left);
    }

    inline fn drawSLine(r: *Raster, x0: f32, y0: f32, x1: f32, y1: f32) void {
        const w: i32 = @intCast(r.w);

        const x0i: f32 = @floor(x0);
        const x1i: f32 = @floor(x1);
        const y0i: f32 = @floor(y0);
        const y1i: f32 = @floor(y1);

        const dx = (x1 - x0) * 0.5;
        const idx = 0.5 / @abs(dx);
        const dy = y1 - y0;
        const idy = 1.0 / @abs(dy);

        const sx: i32 = if (dx < 0) -1 else 1;
        const sx_f: f32 = if (dx < 0) -1.0 else 1.0;
        const sx_hf: f32 = if (dx < 0) -0.5 else 0.5;
        var plane_x = if (dx < 0) x0i - x0 else x0i - x0 + 1;
        var tx = if (dx < 0) -plane_x * idx else plane_x * idx;

        const sy: i32 = if (dy < 0) -w else w;
        const sy_f: f32 = if (dy < 0) -1.0 else 1.0;
        var plane_y = if (dy < 0) y0i - y0 else y0i - y0 + 1;
        var ty = if (dy < 0) -plane_y * idy else plane_y * idy;

        var px: f32 = x0i - x0;
        var x: f32 = 0;
        var y: f32 = 0;
        plane_x *= 0.5;

        var i: i32 = @as(i32, @intFromFloat(x0)) + @as(i32, @intFromFloat(y0)) * w;
        var iter: u32 = @intFromFloat(@abs(x0i - x1i) + @abs(y0i - y1i));

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

            r.add(@intCast(prev_i), right);
            r.add(@intCast(prev_i + 1), left);
        }

        const height = dy - y;
        const left = (dx + x - px) * height;
        const right = height - left;

        r.add(@intCast(i), right);
        r.add(@intCast(i + 1), left);
    }
};
