// s-ui REST API client。经 nginx 同源反代:VITE_API_BASE 默认 /panel/api → 127.0.0.1:2020/app/api
// converter(分流)API 走 /panel/conv → 127.0.0.1:25501
const API = import.meta.env.VITE_API_BASE || '/panel/api'
const CONV = import.meta.env.VITE_CONV_BASE || '/panel/conv'

async function req(base: string, path: string, opts: RequestInit = {}) {
  const r = await fetch(`${base}${path}`, {
    credentials: 'include',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...(opts.headers || {}) },
    ...opts,
  })
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`)
  const ct = r.headers.get('content-type') || ''
  return ct.includes('json') ? r.json() : r.text()
}

const form = (o: Record<string, string>) =>
  Object.entries(o).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')

// ---- s-ui cookie-session API ----
export const login = (user: string, pass: string) =>
  req(API, '/login', { method: 'POST', body: form({ user, pass }) })

// s-ui 全量数据在 /load(不是 getData —— 那是内部函数)。返回 {success,msg,obj:{clients,inbounds,onlines,...}}
export const loadData = () => req(API, '/load?lu=0')

// 通用保存:object=inbounds|clients|... , action=new|edit|del , data=JSON
export const save = (object: string, action: string, data: unknown, initUsers?: string) => {
  const body: Record<string, string> = { object, action, data: JSON.stringify(data) }
  if (initUsers) body.initUsers = initUsers
  return req(API, '/save', { method: 'POST', body: form(body) })
}

// ---- converter(分流规则)----
export const convRules = () => req(CONV, '/admin/rules')
export const convSetRules = (rules: unknown) =>
  req(CONV, '/admin/rules', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rules) })
