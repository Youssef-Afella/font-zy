# font-zy

Fastest single-threaded font rasterizer in the world, with no SIMD.

**Note:** The TTF parser is minimal and exists only to demonstrate the rasterization algorithm. It is not meant for production use.

## Background

I started this project after watching [Sebastian Lague's video](https://youtu.be/SO83KQuuZvg) on text rendering and wanted to try my own approach to speed it up.

My method ended up converging toward the one used in [font-rs](https://github.com/raphlinus/font-rs), though I didn't know about it beforehand. The two differ in a few ways.

## How it works

- Curve rasterization: font-rs flattens curves via tessellation. font-zy operates directly on the quadratic and uses a technique inspired by the DDA algorithm, using double plane intersection tests.
- Buffers: Both use two buffers, one for area coverage and one for accumulation. (f32 and u8)
- No zeroing of the large buffer: font-zy avoids zeroing the biggest buffer, instead it zeros the smallest one and use it as a flag buffer to flag the touched pixels. 
- Accelerated accumulation: Because edge data is very sparse, and our flag buffer is single byte per channel, you can accelerate accumulation by avoiding large chunks where accumulated value doesn't changes.

The result is significantly faster rendering with no SIMD, which also keeps the code portable.
