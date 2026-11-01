# font-zy

Blazing fast single-threaded font rasterizer written in zig. (WIP)

**Note:** The TTF parser is minimal and exists only to demonstrate the rasterization algorithm. It is not meant for production use. It is a stripped-down version of Andrew Kelley's [TrueType](https://codeberg.org/andrewrk/TrueType/src/branch/main), which started off as a port of [stb_truetype](https://github.com/nothings/stb/blob/master/stb_truetype.h).

The core technique comes from [font-rs](https://github.com/raphlinus/font-rs), explained in the author's [post](https://medium.com/@raphlinus/inside-the-fastest-font-renderer-in-the-world-75ae5270c445).<br>
Other fast renderers also inspired this project, such as [fontdue](https://github.com/mooman219/fontdue/tree/master) and [titanf](https://github.com/Hoteira/titanf).

## Example

A minimal implementation lives in the `example` folder. To run it:
```bash
zig build example
```

## Performance

To run the benchmark provided in the repo :
```bash
zig build bench
```

fontdue was the fastest alternative I found, so I benchmarked against it (the bench draft used is provided in the repo).

The advantage of font-zy technic shows strongly in very big sizes but since no one is realisticlly gonna render text at 300px/em, I divided the benchmark results into two charts: below 100px/em and above it.<br>
At very large sizes, font-zy can reaches up to a 2x speedup!

<img width="1453" height="555" alt="Pic1" src="https://github.com/user-attachments/assets/f84a0f34-b718-4e25-9e6f-369d8017e2de" />

<img width="1468" height="605" alt="Pic2" src="https://github.com/user-attachments/assets/76a21002-67e1-4d2d-b381-f10cd9f6014c" />

## How it works

- **Line rasterization:** traversal algorithm similar to [Fast Voxel Traversal](http://www.cse.yorku.ca/~amana/research/grid.pdf).
- **Double buffers:** one buffer (f32) holds area coverage and accumulation, and a second one (u8) used both for flagging pixels and the final bitmap.
- **No zeroing of the large buffer:** font-zy skips clearing the biggest buffer. Instead it zeros only the small flag buffer and uses it to track touched pixels.
- **Accelerated accumulation:** edge data is very sparse, and the flag buffer uses a single byte per channel. This lets accumulation skip large untouched chunks by reading several bytes as one value and comparing it to 0.
