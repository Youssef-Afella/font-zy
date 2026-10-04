# font-zy

Fastest single-threaded font rasterizer in the world, with no SIMD.

**Note:** The TTF parser is minimal and exists only to demonstrate the rasterization algorithm. It is not meant for production use.

## Background

I started this project after  watching[Sebastian Lague's video](https://youtu.be/SO83KQuuZvg) on text rendering and wanted to try my own approach to speed it up.

The technic is somewhat inspired by [font-rs](https://github.com/raphlinus/font-rs), but the two differ in a few ways with font-zy giving high priority to not use any SIMD instructions for maximum portability.

## How it works

- Line rasterization: font-zy uses a traversal algorithm similar to [Fast Voxel Traversal](http://www.cse.yorku.ca/~amana/research/grid.pdf), while I'm not sure exactly what font-rs is using.
- Buffers: Both use double buffers, one for area coverage and one for accumulation. (f32 and u8)
- No zeroing of the large buffer: font-zy avoids zeroing the biggest buffer, instead it zeros the smallest one and use it as a flag buffer to flag the touched pixels. 
- Accelerated accumulation: Because edge data is very sparse, and our flag buffer is single byte per channel, we can accelerate accumulation by avoiding large chunks where accumulated value doesn't changes (reading multiple bytes as one value and compairing with 0).