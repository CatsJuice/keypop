// 扫描 main.js 里用到的 emoji，从 Twemoji 下载对应的 SVG 到 emoji/ 目录。
// 新增 emoji 后重新运行：node fetch-emoji.mjs
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';

const BASE = 'https://cdn.jsdelivr.net/gh/jdecked/twemoji@15.1.0/assets/svg/';
const src = await readFile(new URL('./main.js', import.meta.url), 'utf8');
const SKIP = new Set(['⛶']); // 全屏按钮上的符号，不是 emoji 图
const emojis = [...new Set(src.match(/\p{Extended_Pictographic}️?/gu) || [])].filter((ch) => !SKIP.has(ch));
const dir = new URL('./emoji/', import.meta.url);
await mkdir(dir, { recursive: true });

let failed = 0;
for (const ch of emojis) {
  const name = [...ch].map((c) => c.codePointAt(0).toString(16)).filter((h) => h !== 'fe0f').join('-') + '.svg';
  const file = new URL(name, dir);
  try { await access(file); continue; } catch {}
  const res = await fetch(BASE + name);
  if (!res.ok) { console.error(`✗ ${ch} ${name} (${res.status})`); failed++; continue; }
  await writeFile(file, await res.text());
  console.log(`✓ ${ch} ${name}`);
}
console.log(`${emojis.length} emoji, ${failed} failed`);
process.exit(failed ? 1 : 0);
