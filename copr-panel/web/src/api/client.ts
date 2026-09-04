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

// s-ui 面板设置(端口/路径/订阅端口…),用于「设置」页显示真实值而非写死
export const settings = () => req(API, '/settings')

// 单个会员的【完整】记录 —— 只有带 id 的这个接口会返回 config(各协议凭证);
// 不带 id 的 /clients 列表是没有 config 的。编辑会员必须走这里取回整条再改,
// 否则 save('clients','edit') 会把凭证清空,用户链接立刻失效。
export const getClient = async (id: number) => {
  const r: any = await req(API, `/clients?id=${id}`)
  return r?.obj?.clients?.[0] ?? null
}

// Reality x25519 密钥对(s-ui 生成,返回 ["PrivateKey: xxx","PublicKey: yyy"])
export const realityKeypair = async (): Promise<{ priv: string; pub: string }> => {
  const r: any = await req(API, '/keypairs?k=reality')
  const arr: string[] = r?.obj ?? []
  const pick = (p: string) => (arr.find(x => x.startsWith(p)) || '').split(': ')[1] || ''
  return { priv: pick('PrivateKey'), pub: pick('PublicKey') }
}

// 通用保存:object=inbounds|clients|... , action=new|edit|del , data=JSON
//
// ⚠️ data 必须是【紧凑】JSON(JSON.stringify 默认行为,不要加缩进/空格)。
// s-ui 把 client.inbounds 原样当 blob 存进 SQLite,再用 json_each() 查。SQLite 见到 BLOB 会先
// 试着按 JSONB 解析:`[1, 2]`(带空格,6 字节)恰好符合 JSONB 头部长度,于是被当成 JSONB 解出
// 乱码 → "malformed JSON",整个保存失败;`[1,2]`(5 字节)长度对不上,退回文本解析才正常。
// 这就是「会员绑多个节点必失败」的根因 —— 别在这里做美化输出。
export const save = (object: string, action: string, data: unknown, initUsers?: string) => {
  const body: Record<string, string> = { object, action, data: JSON.stringify(data) }
  if (initUsers) body.initUsers = initUsers
  return req(API, '/save', { method: 'POST', body: form(body) })
}

// ---- converter(分流规则)----
export const convRules = () => req(CONV, '/admin/rules')
export const convSetRules = (rules: unknown) =>
  req(CONV, '/admin/rules', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rules) })
