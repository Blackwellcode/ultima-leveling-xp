// Kontaktbogen aller Grafiken auf dunklem Grund als PNG (tools/preview-art.png). Aufruf: node tools/preview-art.js
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const DIR = path.join(__dirname, '..', 'assets', 'branding');
function readTga(file) {
    const b = fs.readFileSync(file), w = b.readUInt16LE(12), h = b.readUInt16LE(14), top = (b[17] & 0x20) !== 0;
    const px = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const sy = top ? y : h - 1 - y, i = 18 + (sy * w + x) * 4, o = (y * w + x) * 4;
        px[o] = b[i + 2]; px[o + 1] = b[i + 1]; px[o + 2] = b[i]; px[o + 3] = b[i + 3];
    }
    return { w, h, px };
}
const files = fs.readdirSync(DIR).filter(f => f.endsWith('.tga')).sort();
const CELL = 140, COLS = 5, W = CELL * COLS, H = CELL * Math.ceil(files.length / COLS);
const img = new Uint8Array(W * H * 3);
for (let i = 0; i < W * H; i++) { img[i * 3] = 36; img[i * 3 + 1] = 40; img[i * 3 + 2] = 48; }
files.forEach((f, n) => {
    const t = readTga(path.join(DIR, f)), scale = Math.min(1, 128 / Math.max(t.w, t.h));
    const ox = (n % COLS) * CELL + 6, oy = Math.floor(n / COLS) * CELL + 6;
    for (let y = 0; y < Math.round(t.h * scale); y++) for (let x = 0; x < Math.round(t.w * scale); x++) {
        const sx = Math.floor(x / scale), sy = Math.floor(y / scale), s = (sy * t.w + sx) * 4, a = t.px[s + 3] / 255;
        const d = ((oy + y) * W + ox + x) * 3;
        for (let k = 0; k < 3; k++) img[d + k] = Math.round(img[d + k] * (1 - a) + t.px[s + k] * a);
    }
});
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) { raw[y * (W * 3 + 1)] = 0; Buffer.from(img.buffer, y * W * 3, W * 3).copy(raw, y * (W * 3 + 1) + 1); }
const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = buf => { let c = 0xffffffff; for (const v of buf) c = crcTable[(c ^ v) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
fs.writeFileSync(path.join(__dirname, 'preview-art.png'), png);
console.log(files.join(', '));
