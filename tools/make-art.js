// Erzeugt alle Ultima-Grafiken als TGA, kantengeglaettet durch 4x4-Supersampling.
// Ersetzt im Build jede gleichnamige Grafik (Logo, Banner, Kopf, Minimap, Pfeil).
// Aufruf: node tools/make-art.js
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, '..', 'assets', 'branding');
const ACCENT = [51, 214, 176];      // #33D6B0
const DARK = [17, 19, 22];
const OUTLINE = [6, 7, 8];
const SS = 4;                        // Unterabtastung je Achse

function writeTga(file, w, h, rgba) {
    const header = Buffer.alloc(18);
    header[2] = 2;
    header.writeUInt16LE(w, 12);
    header.writeUInt16LE(h, 14);
    header[16] = 32;
    header[17] = 0x28;               // 8 Alpha-Bits, Ursprung oben links
    const px = Buffer.alloc(w * h * 4);
    for (let i = 0; i < w * h; i++) {
        px[i * 4] = rgba[i * 4 + 2];
        px[i * 4 + 1] = rgba[i * 4 + 1];
        px[i * 4 + 2] = rgba[i * 4];
        px[i * 4 + 3] = rgba[i * 4 + 3];
    }
    fs.writeFileSync(path.join(OUT, file), Buffer.concat([header, px]));
    return 18 + px.length;
}

function inPolygon(x, y, pts) {
    let inside = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const [xi, yi] = pts[i], [xj, yj] = pts[j];
        if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
}

function inRoundRect(x, y, w, h, r) {
    const cx = Math.min(Math.max(x, r), w - r), cy = Math.min(Math.max(y, r), h - r);
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

// Rendert Ebenen (unten zuerst): jede Ebene = { test(x, y) -> bool, color: [r, g, b] }.
function render(w, h, layers) {
    const out = new Float32Array(w * h * 4);
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            let r = 0, g = 0, b = 0, a = 0;
            for (let sy = 0; sy < SS; sy++) {
                for (let sx = 0; sx < SS; sx++) {
                    const fx = x + (sx + 0.5) / SS, fy = y + (sy + 0.5) / SS;
                    let cr = 0, cg = 0, cb = 0, ca = 0;
                    for (const layer of layers) {
                        if (layer.test(fx, fy)) {
                            [cr, cg, cb] = typeof layer.color === 'function' ? layer.color(fx, fy) : layer.color;
                            ca = 1;
                        }
                    }
                    r += cr * ca; g += cg * ca; b += cb * ca; a += ca;
                }
            }
            const n = SS * SS, i = (y * w + x) * 4;
            out[i + 3] = a / n * 255;
            if (a > 0) { out[i] = r / a; out[i + 1] = g / a; out[i + 2] = b / a; }
        }
    }
    return Uint8Array.from(out, v => Math.max(0, Math.min(255, Math.round(v))));
}

const scale = (pts, s) => pts.map(([x, y]) => [x * s, y * s]);

// Logo: dunkles abgerundetes Quadrat mit zwei tuerkisen Winkeln nach oben (Aufstieg).
function logo(size) {
    const s = size / 128;
    const chevron = dy => scale([[30, 76 + dy], [64, 42 + dy], [98, 76 + dy], [98, 94 + dy], [64, 60 + dy], [30, 94 + dy]], s);
    return render(size, size, [
        { test: (x, y) => inRoundRect(x, y, size, size, 26 * s), color: DARK },
        { test: (x, y) => !inRoundRect(x, y, size, size, 26 * s) ? false
            : !inRoundRect(x - 3 * s, y - 3 * s, size - 6 * s, size - 6 * s, 23 * s), color: [40, 44, 50] },
        { test: (x, y) => inPolygon(x, y, chevron(-14)), color: ACCENT },
        { test: (x, y) => inPolygon(x, y, chevron(16)), color: [36, 150, 124] },
    ]);
}

// Navigationspfeil nach oben, dunkler Rand fuer Kontrast auf hellem Boden.
function arrow(size) {
    const s = size / 128;
    const shape = [[64, 10], [108, 104], [64, 82], [20, 104]];
    const outline = shape.map(([x, y]) => [64 + (x - 64) * 1.14, 60 + (y - 60) * 1.14]);
    return render(size, size, [
        { test: (x, y) => inPolygon(x, y, scale(outline, s)), color: OUTLINE },
        { test: (x, y) => inPolygon(x, y, scale(shape, s)),
          color: (x, y) => { const t = y / size; return [ACCENT[0] * (1.1 - 0.3 * t), ACCENT[1] * (1.1 - 0.3 * t), ACCENT[2] * (1.1 - 0.3 * t)]; } },
    ]);
}

// Banner und Kopfgrafik: Glasverlauf mit tuerkiser Unterkante, zu den Seiten auslaufend.
function banner(w, h) {
    const rgba = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) {
        const t = y / (h - 1);
        for (let x = 0; x < w; x++) {
            let c = [30 - 18 * t, 31 - 18 * t, 35 - 19 * t];
            if (y < 2) c = c.map(v => v + 22);
            if (y >= h - 3) {
                const fade = Math.min(1, Math.min(x, w - 1 - x) / 96);
                c = c.map((v, k) => v + (ACCENT[k] - v) * fade);
            }
            const i = (y * w + x) * 4;
            rgba[i] = c[0]; rgba[i + 1] = c[1]; rgba[i + 2] = c[2]; rgba[i + 3] = 255;
        }
    }
    return rgba;
}

// ---------------------------------------------------------------------------
// Keynote-Bausteine: Signierte Abstaende (SDF) geben glatte Kanten ohne Treppen.
// Alle Formen sind weiss; die Farbe setzt das Addon per SetVertexColor.
// ---------------------------------------------------------------------------
function sdRoundRect(px, py, w, h, r) {
    const qx = Math.abs(px - w / 2) - (w / 2 - r), qy = Math.abs(py - h / 2) - (h / 2 - r);
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}
function sdSegment(px, py, ax, ay, bx, by) {
    const pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay;
    const h = Math.max(0, Math.min(1, (pax * bax + pay * bay) / (bax * bax + bay * bay)));
    return Math.hypot(pax - bax * h, pay - bay * h);
}
function fromAlpha(w, h, alphaFn) {
    const rgba = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4, a = Math.max(0, Math.min(1, alphaFn(x + 0.5, y + 0.5)));
        rgba[i] = rgba[i + 1] = rgba[i + 2] = 255;
        rgba[i + 3] = Math.round(a * 255);
    }
    return rgba;
}
// Gefuellte Rundung (9-Teile): Groesse 64, Radius 16 -> Ecken = 25 % der Textur.
const roundFill = (s, r) => fromAlpha(s, s, (x, y) => 0.5 - sdRoundRect(x, y, s, s, r));
// Ring derselben Rundung, Strichstaerke t (Pixel der Textur).
const roundRing = (s, r, t) => fromAlpha(s, s, (x, y) => {
    const d = sdRoundRect(x, y, s, s, r);
    return Math.min(0.5 - d, d + t + 0.5);
});
// Weicher Schatten: Rundung mit Gauss-aehnlichem Auslauf ueber m Pixel.
const shadow = (s, r, m) => fromAlpha(s, s, (x, y) => {
    const d = sdRoundRect(x - m, y - m, s - 2 * m, s - 2 * m, r);
    if (d <= 0) return 0.55;
    const t = Math.min(1, d / m);
    return 0.55 * Math.pow(1 - t, 2.2);
});
// Glyphen aus Linienzuegen, Strichstaerke t.
const glyph = (s, t, segments) => fromAlpha(s, s, (x, y) => {
    let d = Infinity;
    for (const [ax, ay, bx, by] of segments) d = Math.min(d, sdSegment(x, y, ax * s, ay * s, bx * s, by * s));
    return 0.5 - (d - t / 2);
});
// Glasscheibe fuer den Pfeil: dunkler Kreis, oben heller, Ring mit Akzentverlauf.
function disc(s) {
    const rgba = new Uint8Array(s * s * 4), c = s / 2, R = s / 2 - 2;
    for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
        const i = (y * s + x) * 4, d = Math.hypot(x + 0.5 - c, y + 0.5 - c) - R;
        const fill = Math.max(0, Math.min(1, 0.5 - d));
        const ring = Math.max(0, Math.min(1, Math.min(0.5 - d, d + 3.5)));
        const t = y / s;
        const base = [16 + 14 * (1 - t), 17 + 14 * (1 - t), 21 + 16 * (1 - t)];
        const acc = [51 + (59 - 51) * (x / s), 214 + (167 - 214) * (x / s), 176 + (255 - 176) * (x / s)];
        const col = base.map((v, k) => v + (acc[k] - v) * ring);
        rgba[i] = col[0]; rgba[i + 1] = col[1]; rgba[i + 2] = col[2];
        rgba[i + 3] = Math.round(fill * (0.86 + 0.14 * ring) * 255);
    }
    return rgba;
}

fs.mkdirSync(OUT, { recursive: true });
const files = [
    ['ulx_logo-128.tga', 128, 128, logo(128)],
    ['ulx_logo-64.tga', 64, 64, logo(64)],
    ['ulx-icon-logo.tga', 128, 128, logo(128)],
    ['ulx-minimap-icon.tga', 64, 64, logo(64)],
    ['ulx-banner.tga', 512, 64, banner(512, 64)],
    ['ulx-header-texture.tga', 512, 64, banner(512, 64)],
    ['ulx_navigation_arrow-1.tga', 128, 128, arrow(128)],
    ['ulx-round.tga', 64, 64, roundFill(64, 16)],
    ['ulx-ring.tga', 64, 64, roundRing(64, 16, 2)],
    ['ulx-circle.tga', 64, 64, roundFill(64, 32)],
    ['ulx-shadow.tga', 128, 128, shadow(128, 16, 32)],
    ['ulx-disc.tga', 128, 128, disc(128)],
    ['ulx-glyph-left.tga', 64, 64, glyph(64, 6, [[0.6, 0.25, 0.38, 0.5], [0.38, 0.5, 0.6, 0.75]])],
    ['ulx-glyph-right.tga', 64, 64, glyph(64, 6, [[0.4, 0.25, 0.62, 0.5], [0.62, 0.5, 0.4, 0.75]])],
    ['ulx-glyph-list.tga', 64, 64, glyph(64, 6, [[0.25, 0.3, 0.75, 0.3], [0.25, 0.5, 0.75, 0.5], [0.25, 0.7, 0.75, 0.7]])],
    ['ulx-glyph-minus.tga', 64, 64, glyph(64, 6, [[0.28, 0.5, 0.72, 0.5]])],
    ['ulx-glyph-plus.tga', 64, 64, glyph(64, 6, [[0.28, 0.5, 0.72, 0.5], [0.5, 0.28, 0.5, 0.72]])],
    ['ulx-glyph-check.tga', 64, 64, glyph(64, 7, [[0.27, 0.52, 0.43, 0.68], [0.43, 0.68, 0.74, 0.34]])],
    ['ulx-glyph-ship.tga', 64, 64, glyph(64, 5, [[0.2, 0.62, 0.8, 0.62], [0.2, 0.62, 0.3, 0.76], [0.8, 0.62, 0.7, 0.76],
        [0.3, 0.76, 0.7, 0.76], [0.5, 0.2, 0.5, 0.62], [0.5, 0.24, 0.72, 0.54], [0.72, 0.54, 0.5, 0.54]])],
    // Zeilen-Glyphen der Schritt-Karte (ein Strichstil wie die Knoepfe)
    ['ulx-glyph-accept.tga', 64, 64, glyph(64, 7, [[0.5, 0.2, 0.5, 0.56], [0.5, 0.76, 0.5, 0.77]])],
    ['ulx-glyph-turnin.tga', 64, 64, glyph(64, 6, [[0.5, 0.2, 0.5, 0.6], [0.34, 0.46, 0.5, 0.62], [0.66, 0.46, 0.5, 0.62], [0.26, 0.78, 0.74, 0.78]])],
    ['ulx-glyph-goto.tga', 64, 64, glyph(64, 5, [[0.28, 0.74, 0.5, 0.22], [0.5, 0.22, 0.72, 0.74], [0.72, 0.74, 0.5, 0.6], [0.5, 0.6, 0.28, 0.74]])],
    ['ulx-glyph-kill.tga', 64, 64, glyph(64, 6, [[0.28, 0.28, 0.72, 0.72], [0.72, 0.28, 0.28, 0.72]])],
    ['ulx-glyph-collect.tga', 64, 64, glyph(64, 5, [[0.28, 0.38, 0.72, 0.38], [0.72, 0.38, 0.72, 0.76], [0.72, 0.76, 0.28, 0.76], [0.28, 0.76, 0.28, 0.38],
        [0.4, 0.38, 0.4, 0.26], [0.4, 0.26, 0.6, 0.26], [0.6, 0.26, 0.6, 0.38]])],
    ['ulx-glyph-talk.tga', 64, 64, glyph(64, 5, [[0.24, 0.28, 0.76, 0.28], [0.76, 0.28, 0.76, 0.6], [0.76, 0.6, 0.46, 0.6], [0.46, 0.6, 0.34, 0.74],
        [0.34, 0.74, 0.34, 0.6], [0.34, 0.6, 0.24, 0.6], [0.24, 0.6, 0.24, 0.28]])],
    ['ulx-glyph-xp.tga', 64, 64, glyph(64, 6, [[0.3, 0.5, 0.5, 0.3], [0.5, 0.3, 0.7, 0.5], [0.3, 0.72, 0.5, 0.52], [0.5, 0.52, 0.7, 0.72]])],
    ['ulx-glyph-train.tga', 64, 64, glyph(64, 5, [[0.26, 0.3, 0.5, 0.36], [0.5, 0.36, 0.74, 0.3], [0.26, 0.3, 0.26, 0.68], [0.74, 0.3, 0.74, 0.68],
        [0.26, 0.68, 0.5, 0.74], [0.5, 0.74, 0.74, 0.68], [0.5, 0.36, 0.5, 0.74]])],
    ['ulx-glyph-home.tga', 64, 64, glyph(64, 5, [[0.24, 0.5, 0.5, 0.26], [0.5, 0.26, 0.76, 0.5], [0.32, 0.46, 0.32, 0.74], [0.68, 0.46, 0.68, 0.74], [0.32, 0.74, 0.68, 0.74]])],
    ['ulx-glyph-fly.tga', 64, 64, glyph(64, 5, [[0.22, 0.5, 0.78, 0.26], [0.78, 0.26, 0.56, 0.76], [0.56, 0.76, 0.46, 0.56], [0.46, 0.56, 0.22, 0.5], [0.46, 0.56, 0.78, 0.26]])],
    ['ulx-glyph-use.tga', 64, 64, glyph(64, 6, [[0.56, 0.2, 0.36, 0.52], [0.36, 0.52, 0.6, 0.52], [0.6, 0.52, 0.42, 0.8]])],
    // Einstellungen: drei Schieberegler mit Griffen
    ['ulx-glyph-settings.tga', 64, 64, glyph(64, 5, [[0.24, 0.3, 0.76, 0.3], [0.24, 0.5, 0.76, 0.5], [0.24, 0.7, 0.76, 0.7],
        [0.4, 0.22, 0.4, 0.38], [0.62, 0.42, 0.62, 0.58], [0.34, 0.62, 0.34, 0.78]])],
];
for (const [name, w, h, rgba] of files) {
    console.log(`${name.padEnd(28)} ${w}x${h}  ${writeTga(name, w, h, rgba)} Byte`);
}
