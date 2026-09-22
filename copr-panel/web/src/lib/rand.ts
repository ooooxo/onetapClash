// 这些是会员凭证(UUID/密码/Reality short-id),必须用密码学随机数;Math.random 可被预测
const bytes = (n: number) => crypto.getRandomValues(new Uint8Array(n))
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
export const rb64 = (n: number) => Array.from(bytes(n), b => B64[b & 63]).join('')
// randomUUID 只在安全上下文(HTTPS/localhost)存在;HTTP 访问面板时退回手拼 v4
export const ruuid = (): string => crypto.randomUUID?.() ?? 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, ch => {
  const r = bytes(1)[0] & 15
  return (ch === 'x' ? r : (r & 3) | 8).toString(16)
})
export const rhex = (n: number) => Array.from(bytes(n), b => (b & 15).toString(16)).join('')
