import qrcode from 'qrcode-generator'

// 真·可扫二维码(byte 模式 + 纠错级 M,版本自适应)。
// 旧版这里是"确定性伪随机点阵",扫出来是垃圾 —— 订阅二维码扫不出等于功能不存在。
export function qrSvg(text: string): string {
  const qr = qrcode(0, 'M')          // 0 = 自动选版本
  qr.addData(text)                   // 默认 Byte 模式,URL 安全
  qr.make()
  const n = qr.getModuleCount()
  const quiet = 4                    // 静区,少于 4 模块很多扫码器读不出
  const size = n + quiet * 2
  let path = ''
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (qr.isDark(y, x)) path += `M${x + quiet} ${y + quiet}h1v1h-1z`
    }
  }
  return `<svg viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges" role="img" aria-label="订阅二维码">` +
    `<rect width="${size}" height="${size}" fill="#fff"/><path d="${path}" fill="#111"/></svg>`
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
