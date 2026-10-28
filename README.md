# font-zy

Fastest single-threaded font rasterizer in the world, with no explicit SIMD. (WIP)

**Note:** The TTF parser is minimal and exists only to demonstrate the rasterization algorithm. It is not meant for production use.
It's a stripped down version of Andrew Kelley [TrueType](https://codeberg.org/andrewrk/TrueType/src/branch/main) project which started of as a port of [stb_truetype](https://github.com/nothings/stb/blob/master/stb_truetype.h)

The original technic used here is from [font-rs](https://github.com/raphlinus/font-rs) explained in the author [post](https://medium.com/@raphlinus/inside-the-fastest-font-renderer-in-the-world-75ae5270c445).

Also lot of other fast renderers libs inspired this projet such as: [fontdue](https://github.com/mooman219/fontdue/tree/master), and [titanf](https://github.com/Hoteira/titanf)


## How it works

- Line rasterization: traversal algorithm similar to [Fast Voxel Traversal](http://www.cse.yorku.ca/~amana/research/grid.pdf).
- Buffers: Double buffers, one for area coverage and one for accumulation. (f32 and u8)
- No zeroing of the large buffer: font-zy avoids zeroing the biggest buffer, instead it zeros the smallest one and use it as a flag buffer to flag the touched pixels. 
- Accelerated accumulation: Because edge data is very sparse, and our flag buffer is single byte per channel, we can accelerate accumulation by avoiding large chunks where accumulated value doesn't changes (reading multiple bytes as one value and compairing with 0).
