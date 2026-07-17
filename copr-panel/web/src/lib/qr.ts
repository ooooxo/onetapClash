// 装饰性 QR(确定性,非真扫码) — 上线后服务端生成真码。用于原型/预览。
export function qrSvg(text: string): string {
  const N = 25, cell = 100 / N
  let h = 0
  for (let i = 0; i < text.length; i++) h = (h * 131 + text.charCodeAt(i)) >>> 0
  const g: number[][] = []
  for (let y = 0; y < N; y++) {
    g[y] = []
    for (let x = 0; x < N; x++) { h = (h * 1103515245 + 12345) >>> 0; g[y][x] = (h >> 16) & 1 }
  }
  const fin = (ox: number, oy: number) => {
    for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) {
      const b = x === 0 || x === 6 || y === 0 || y === 6 || (x >= 2 && x <= 4 && y >= 2 && y <= 4)
      g[oy + y][ox + x] = b ? 1 : 0
    }
  }
  fin(0, 0); fin(N - 7, 0); fin(0, N - 7)
  let r = ''
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (g[y][x])
    r += `<rect x="${(x * cell).toFixed(2)}" y="${(y * cell).toFixed(2)}" width="${cell.toFixed(2)}" height="${cell.toFixed(2)}"/>`
  return `<svg viewBox="0 0 100 100" role="img" aria-label="订阅二维码"><g fill="#111">${r}</g></svg>`
}

export function copyText(t: string) {
  if (navigator.clipboard?.writeText) navigator.clipboard.writeText(t).catch(() => fallback(t))
  else fallback(t)
}
function fallback(t: string) {
  const a = document.createElement('textarea')
  a.value = t; document.body.appendChild(a); a.select()
  try { document.execCommand('copy') } catch { /* noop */ }
  a.remove()
}
