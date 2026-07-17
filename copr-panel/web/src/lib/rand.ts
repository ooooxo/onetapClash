const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
export const rb64 = (n: number) => Array.from({ length: n }, () => B64[Math.floor(Math.random() * B64.length)]).join('')
export const ruuid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, ch => {
  const r = Math.floor(Math.random() * 16)
  return (ch === 'x' ? r : (r & 3) | 8).toString(16)
})
export const rhex = (n: number) => Array.from({ length: n }, () => Math.floor(Math.random() * 16).toString(16)).join('')
