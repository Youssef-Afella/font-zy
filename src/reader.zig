pub const Reader = struct {
    pos: u32 = 0,
    buffer: []const u8,

    pub fn init(buffer: []const u8) Reader {
        return .{
            .buffer = buffer,
        };
    }

    pub fn readInt(f: *Reader, comptime T: type) T {
        const size = @divExact(@typeInfo(T).int.bits, 8);
        const value = parseInt(T, f.buffer[f.pos..][0..size]);
        f.pos += size;
        return value;
    }

    pub fn getPosition(f: *Reader) u32 {
        return f.pos;
    }

    pub fn setPosition(f: *Reader, p: u32) void {
        f.pos = p;
    }

    pub fn skipBytes(f: *Reader, count: u32) void {
        f.pos += count;
    }

    inline fn parseInt(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8) T {
        const value: T = @bitCast(buffer.*);
        return @byteSwap(value);
    }
};
