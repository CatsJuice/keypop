/* KeyPop —— 给幼儿玩的键盘特效玩具
 * 每个按键：一个固定的视觉特效 + 一个固定且各不相同的音效（Web Audio 实时合成，无素材文件）
 */

// ───────────────────────── 工具 ─────────────────────────
const rand = (a, b) => a + Math.random() * (b - a);
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const hash = (s) => { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) >>> 0; return h; };
const COLORS = ['#ff5e7e', '#ffb02e', '#ffe94a', '#5ee67a', '#4ad9ff', '#7c8cff', '#d77bff', '#ff8ad8'];

// ───────────────────────── 音频 ─────────────────────────
let ac = null, master = null, noiseBuf = null;

function initAudio() {
  if (ac) { if (ac.state === 'suspended') ac.resume(); return; }
  ac = new (window.AudioContext || window.webkitAudioContext)();
  const comp = ac.createDynamicsCompressor(); // 压限，防止乱按时爆音
  master = ac.createGain();
  master.gain.value = 0.55;
  master.connect(comp).connect(ac.destination);
  noiseBuf = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
}

// 基础发声：freqs 可以是单个频率，也可以是 [起, 止] 或多段滑音
function tone({ freq, type = 'sine', dur = 0.4, vol = 0.3, delay = 0, attack = 0.006, lowpass }) {
  const t = ac.currentTime + delay;
  const osc = ac.createOscillator();
  const g = ac.createGain();
  osc.type = type;
  const fs = Array.isArray(freq) ? freq : [freq];
  osc.frequency.setValueAtTime(fs[0], t);
  fs.slice(1).forEach((f, i) => osc.frequency.exponentialRampToValueAtTime(f, t + (dur * (i + 1)) / (fs.length - 1)));
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  let node = osc;
  if (lowpass) {
    const f = ac.createBiquadFilter();
    f.type = 'lowpass'; f.frequency.value = lowpass;
    node = osc.connect(f);
  }
  node.connect(g).connect(master);
  osc.start(t); osc.stop(t + dur + 0.05);
}

function noise({ dur = 0.3, vol = 0.3, delay = 0, cutoff = 1200, type = 'lowpass' }) {
  const t = ac.currentTime + delay;
  const src = ac.createBufferSource(); src.buffer = noiseBuf;
  const f = ac.createBiquadFilter(); f.type = type; f.frequency.value = cutoff;
  const g = ac.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(g).connect(master);
  src.start(t); src.stop(t + dur + 0.05);
}

// 乐器
const voices = {
  marimba: (f) => { tone({ freq: f, dur: 0.5, vol: 0.4 }); tone({ freq: f * 4, dur: 0.12, vol: 0.12 }); },
  pluck:   (f) => { tone({ freq: f, type: 'triangle', dur: 0.6, vol: 0.4 }); tone({ freq: f * 2, dur: 0.2, vol: 0.1 }); },
  bass:    (f) => { tone({ freq: f, type: 'square', dur: 0.45, vol: 0.22, lowpass: 900 }); tone({ freq: f / 2, dur: 0.5, vol: 0.3 }); },
  bell:    (f) => { tone({ freq: f, dur: 1.2, vol: 0.3 }); tone({ freq: f * 2.76, dur: 0.8, vol: 0.1 }); tone({ freq: f * 5.4, dur: 0.3, vol: 0.05 }); },
  pop:     (f) => tone({ freq: [f, f * 2.2], dur: 0.09, vol: 0.4 }),
  boing:   (f) => tone({ freq: [f, f * 2.5, f * 0.8, f * 1.6], type: 'triangle', dur: 0.45, vol: 0.35 }),
  chirp:   (f) => { tone({ freq: [f * 3, f * 5, f * 4], dur: 0.12, vol: 0.25 }); tone({ freq: [f * 3.5, f * 5.5], dur: 0.1, vol: 0.25, delay: 0.13 }); },
  wah:     (f) => tone({ freq: [f, f * 1.5, f], type: 'sawtooth', dur: 0.4, vol: 0.2, lowpass: 1400 }),
};
const FUN_VOICES = ['pop', 'boing', 'chirp', 'wah'];

// 五声音阶（怎么乱按都好听）
const PENTA = [0, 2, 4, 7, 9];
const pentaFreq = (base, i) => base * 2 ** ((Math.floor(i / 5) * 12 + PENTA[i % 5]) / 12);
const MAJOR = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16];

// ───────────────────────── 粒子（Canvas） ─────────────────────────
const canvas = document.getElementById('fx');
const ctx = canvas.getContext('2d');
const stage = document.getElementById('stage');
let W = 0, H = 0;
const particles = [];
const MAX_PARTICLES = 1500;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  W = window.innerWidth; H = window.innerHeight;
  canvas.width = W * dpr; canvas.height = H * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
window.addEventListener('resize', resize);
resize();

function addParticle(p) {
  if (particles.length >= MAX_PARTICLES) particles.shift();
  particles.push({ life: 0, max: 1, size: 8, g: 300, drag: 0.98, rot: rand(0, 6.28), vr: rand(-6, 6), shape: 'circle', ...p });
}

function burst(x, y, { n = 40, speed = 420, colors = COLORS, shapes = ['circle', 'star'], size = [5, 14], g = 320, life = [0.7, 1.4] } = {}) {
  for (let i = 0; i < n; i++) {
    const a = rand(0, Math.PI * 2), v = rand(speed * 0.25, speed);
    addParticle({
      x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, g,
      color: pick(colors), shape: pick(shapes), size: rand(size[0], size[1]), max: rand(life[0], life[1]),
    });
  }
}

function starPath(r) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const rr = i % 2 ? r * 0.45 : r, a = (i * Math.PI) / 5 - Math.PI / 2;
    ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  ctx.closePath();
}

let lastT = performance.now();
function frame(now) {
  const dt = Math.min((now - lastT) / 1000, 0.05);
  lastT = now;
  ctx.clearRect(0, 0, W, H);
  ctx.globalCompositeOperation = 'lighter';
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.life += dt;
    if (p.life >= p.max) { particles.splice(i, 1); continue; }
    p.vy += p.g * dt;
    p.vx *= p.drag; p.vy *= p.drag;
    p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt;
    const k = 1 - p.life / p.max;
    ctx.globalAlpha = Math.min(1, k * 1.6);
    ctx.fillStyle = p.color;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.rot);
    const s = p.size * (0.5 + k * 0.5);
    if (p.shape === 'star') { starPath(s); ctx.fill(); }
    else if (p.shape === 'square') ctx.fillRect(-s * 0.7, -s * 0.7, s * 1.4, s * 1.4);
    else if (p.shape === 'ring') { ctx.strokeStyle = p.color; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(0, 0, s * (2 - k) * 1.5, 0, 6.28); ctx.stroke(); }
    else { ctx.beginPath(); ctx.arc(0, 0, s, 0, 6.28); ctx.fill(); }
    ctx.restore();
  }
  ctx.globalAlpha = 1;
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// ───────────────────────── DOM 大字 ─────────────────────────
// emoji 用 emoji/ 目录下的 Twemoji 矢量图（系统 emoji 是位图，放大会糊）
const emojiSrc = (ch) => 'emoji/' + [...ch].map((c) => c.codePointAt(0).toString(16)).filter((h) => h !== 'fe0f').join('-') + '.svg';
function emojiImg(ch) {
  const img = new Image();
  img.className = 'emoji';
  img.alt = ch;
  img.draggable = false;
  img.src = emojiSrc(ch);
  return img;
}

function glyph(x, y, text, { emoji = '', color = '#fff', size = 0.28 } = {}) {
  const el = document.createElement('div');
  el.className = 'glyph';
  el.style.left = x + 'px'; el.style.top = y + 'px';
  el.style.color = color;
  el.style.fontSize = Math.min(W, H) * size + 'px';
  el.style.setProperty('--r0', rand(-40, 40) + 'deg');
  el.style.setProperty('--r1', rand(-12, 12) + 'deg');
  if (text) { const s = document.createElement('span'); s.textContent = text; el.append(s); }
  if (emoji) { const s = document.createElement('span'); s.className = 'em'; s.append(emojiImg(emoji)); el.append(s); }
  el.addEventListener('animationend', () => el.remove());
  stage.append(el);
  if (stage.childElementCount > 60) stage.firstElementChild.remove();
}

function emojiRain(list, n = 22) {
  for (let i = 0; i < n; i++) {
    const el = document.createElement('div');
    el.className = 'drop';
    el.append(emojiImg(pick(list)));
    el.style.left = rand(2, 95) + 'vw';
    el.style.fontSize = rand(36, 84) + 'px';
    el.style.animationDuration = rand(1.6, 3.2) + 's';
    el.style.animationDelay = rand(0, 0.6) + 's';
    el.style.setProperty('--spin', rand(-360, 360) + 'deg');
    el.addEventListener('animationend', () => el.remove());
    stage.append(el);
  }
}

const randomSpot = () => [rand(W * 0.15, W * 0.85), rand(H * 0.2, H * 0.8)];

// ───────────────────────── 按键表 ─────────────────────────
const ROWS = [
  { keys: 'QWERTYUIOP', voice: 'marimba', base: 293.66 }, // 上排：木琴
  { keys: 'ASDFGHJKL',  voice: 'pluck',   base: 196.0 },  // 中排：拨弦
  { keys: 'ZXCVBNM',    voice: 'bass',    base: 130.81 }, // 下排：低音
];
const LETTER_EMOJI = {
  A: '🍎', B: '🐻', C: '🐱', D: '🐶', E: '🐘', F: '🐸', G: '🦒', H: '🐴', I: '🍦', J: '🧃', K: '🐨', L: '🦁', M: '🐵',
  N: '🌰', O: '🐙', P: '🐼', Q: '👑', R: '🐰', S: '⭐', T: '🐯', U: '🦄', V: '🎻', W: '🐳', X: '🎄', Y: '🪀', Z: '🦓',
};
const FUN_EMOJI = ['🎈', '🫧', '🌈', '🍭', '🦋', '🐥', '🌸', '🍓', '🚀', '🐠', '🎀', '🍩', '🌞', '🐞', '🧸', '🪁'];

// 预加载，避免第一次按键时图片还没到
[...Object.values(LETTER_EMOJI), ...FUN_EMOJI, '🌀', '☄️', '🐟', '🐦'].forEach((ch) => { new Image().src = emojiSrc(ch); });

const KEYMAP = {};

// 字母：大字母 + 小动物 + 彩色爆炸
ROWS.forEach((row) => [...row.keys].forEach((ch, i) => {
  const color = COLORS[hash(ch) % COLORS.length];
  const f = pentaFreq(row.base, i);
  KEYMAP['Key' + ch] = () => {
    const [x, y] = randomSpot();
    voices[row.voice](f);
    glyph(x, y, ch, { emoji: LETTER_EMOJI[ch], color });
    burst(x, y, { colors: [color, '#fff', pick(COLORS)] });
  };
}));

// 数字：铃铛音 + 对应数量的星星
'1234567890'.split('').forEach((d, i) => {
  const f = 523.25 * 2 ** (MAJOR[i] / 12);
  const color = COLORS[i % COLORS.length];
  const fn = () => {
    const [x, y] = randomSpot();
    voices.bell(f);
    glyph(x, y, d, { color, size: 0.34 });
    const n = i + 1;
    for (let k = 0; k < n; k++) {
      const a = (k / n) * Math.PI * 2 - Math.PI / 2;
      addParticle({ x, y, vx: Math.cos(a) * 380, vy: Math.sin(a) * 380, g: 0, drag: 0.96, color: '#ffe94a', shape: 'star', size: 30, max: 1.5 });
    }
  };
  KEYMAP['Digit' + d] = fn;
  KEYMAP['Numpad' + d] = fn;
});

// 空格：烟花
KEYMAP.Space = () => {
  tone({ freq: [160, 40], dur: 0.5, vol: 0.6 });
  noise({ dur: 0.35, vol: 0.35, cutoff: 700 });
  for (let i = 0; i < 4; i++) {
    const delay = i * 0.16;
    setTimeout(() => {
      const x = rand(W * 0.12, W * 0.88), y = rand(H * 0.12, H * 0.6);
      const c = pick(COLORS);
      burst(x, y, { n: 90, speed: 620, colors: [c, '#fff'], shapes: ['circle'], size: [3, 8], g: 180, life: [1, 1.9] });
      addParticle({ x, y, vx: 0, vy: 0, g: 0, color: c, shape: 'ring', size: 40, max: 0.7 });
    }, delay * 1000);
    noise({ dur: 0.5, vol: 0.12, cutoff: 5000, type: 'highpass', delay: delay + 0.05 });
    tone({ freq: rand(900, 1800), dur: 0.25, vol: 0.08, delay: delay + 0.05 });
  }
};

// 回车：emoji 雨 + 琶音
KEYMAP.Enter = KEYMAP.NumpadEnter = () => {
  [261.63, 329.63, 392, 523.25, 659.25].forEach((f, i) => tone({ freq: f, type: 'triangle', dur: 0.5, vol: 0.3, delay: i * 0.09 }));
  emojiRain(FUN_EMOJI);
};

// 退格 / 删除：弹簧 + 旋涡
const swirl = (f) => () => {
  const [x, y] = randomSpot();
  voices.boing(f);
  glyph(x, y, '', { emoji: '🌀', size: 0.3 });
  for (let i = 0; i < 50; i++) {
    const a = (i / 50) * Math.PI * 6, r = i * 5;
    addParticle({ x: x + Math.cos(a) * r, y: y + Math.sin(a) * r, vx: -Math.sin(a) * 200, vy: Math.cos(a) * 200, g: 0, color: COLORS[i % COLORS.length], size: 9, max: 1.1 });
  }
};
KEYMAP.Backspace = swirl(180);
KEYMAP.Delete = swirl(260);

// 方向键：朝对应方向飞的彗星 + 滑哨
const ARROWS = {
  ArrowUp:    { d: [0, -1], emoji: '🚀', freq: [400, 1400],  type: 'sine' },
  ArrowDown:  { d: [0, 1],  emoji: '☄️', freq: [1400, 300],  type: 'sine' },
  ArrowLeft:  { d: [-1, 0], emoji: '🐟', freq: [900, 350],   type: 'triangle' },
  ArrowRight: { d: [1, 0],  emoji: '🐦', freq: [350, 900],   type: 'triangle' },
};
Object.entries(ARROWS).forEach(([code, { d, emoji, freq, type }]) => {
  KEYMAP[code] = () => {
    tone({ freq, type, dur: 0.45, vol: 0.3 });
    const along = rand(0.2, 0.8);
    const sx = d[0] ? (d[0] > 0 ? 0 : W) : W * along;
    const sy = d[1] ? (d[1] > 0 ? 0 : H) : H * along;
    const color = pick(COLORS);
    for (let i = 0; i < 70; i++) {
      const t = i / 70;
      setTimeout(() => {
        const x = sx + d[0] * W * t, y = sy + d[1] * H * t;
        for (let k = 0; k < 3; k++) addParticle({ x, y, vx: rand(-80, 80) - d[0] * 120, vy: rand(-80, 80) - d[1] * 120, g: 0, color: k ? color : '#fff', shape: k ? 'circle' : 'star', size: rand(5, 14), max: 0.9 });
      }, t * 500);
    }
    glyph(W / 2 + d[0] * W * 0.25, H / 2 + d[1] * H * 0.25, '', { emoji, size: 0.25 });
  };
});

// 其它所有按键（符号、Tab、F1-F12、修饰键…）：按键码哈希出固定的 emoji、音色和音高
function fallback(code) {
  const h = hash(code);
  const emoji = FUN_EMOJI[h % FUN_EMOJI.length];
  const voice = FUN_VOICES[(h >>> 4) % FUN_VOICES.length];
  const f = pentaFreq(220, (h >>> 8) % 15);
  const color = COLORS[(h >>> 12) % COLORS.length];
  return () => {
    const [x, y] = randomSpot();
    voices[voice](f);
    glyph(x, y, '', { emoji, size: 0.26 });
    burst(x, y, { n: 26, speed: 300, colors: [color, '#fff'], shapes: ['ring', 'circle'], g: -120, life: [0.8, 1.5] });
  };
}

// ───────────────────────── 输入 ─────────────────────────
const hint = document.getElementById('hint');
const lastFire = {};

function trigger(code) {
  initAudio();
  hint.classList.add('hidden');
  (KEYMAP[code] ||= fallback(code))();
}

window.addEventListener('keydown', (e) => {
  e.preventDefault();
  const code = e.code || e.key;
  if (!code) return;
  const now = performance.now();
  if (e.repeat && now - (lastFire[code] || 0) < 110) return; // 长按时限速
  lastFire[code] = now;
  trigger(code);
}, { capture: true });
window.addEventListener('keyup', (e) => e.preventDefault(), { capture: true });
window.addEventListener('contextmenu', (e) => e.preventDefault());

// 鼠标 / 触摸：点击冒泡泡，拖动留下星星
let lastTrail = 0;
window.addEventListener('pointerdown', (e) => {
  if (e.target.id === 'fullscreen') return;
  initAudio();
  hint.classList.add('hidden');
  voices.pop(300 + (e.clientX / W) * 600);
  burst(e.clientX, e.clientY, { n: 30, speed: 320 });
});
window.addEventListener('pointermove', (e) => {
  const now = performance.now();
  if (now - lastTrail < 16) return;
  lastTrail = now;
  addParticle({ x: e.clientX, y: e.clientY, vx: rand(-60, 60), vy: rand(-60, 60), g: 80, color: pick(COLORS), shape: 'star', size: rand(5, 11), max: 0.7 });
});

// 全屏：尽量锁定键盘，避免孩子按 Esc / 系统快捷键跳出（仅 Chromium 支持，需长按 Esc 退出）
document.getElementById('fullscreen').addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  btn.blur();
  const root = document.documentElement;
  try {
    if (root.requestFullscreen) await root.requestFullscreen();
    else if (root.webkitRequestFullscreen) root.webkitRequestFullscreen(); // 旧版 Safari
    else throw new Error('unsupported');
  } catch {
    // 内嵌预览窗口等环境会禁止全屏，给出提示而不是毫无反应
    btn.textContent = '这里不能全屏，请用 Chrome / Safari 打开';
    setTimeout(() => { btn.textContent = '⛶ 全屏'; }, 3000);
    return;
  }
  try { await navigator.keyboard?.lock?.(); } catch {}
});
