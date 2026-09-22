// s-ui REST API client。经 nginx 同源反代:VITE_API_BASE 默认 <base>api → 127.0.0.1:2020/app/api
// converter(分流)API 走 <base>conv → 127.0.0.1:25501
// <base> 跟随构建时的 --base(部署在 /panel/),换路径部署不用改代码
const API = import.meta.env.VITE_API_BASE || import.meta.env.BASE_URL + 'api'
const CONV = import.meta.env.VITE_CONV_BASE || import.meta.env.BASE_URL + 'conv'

// 会话失效回调,由 store 注册(client 不 import store,避免循环依赖)
export const hooks = { unauthorized: () => {} }

async function req(base: string, path: string, opts: RequestInit = {}) {
  const r = await fetch(`${base}${path}`, {
    credentials: 'include',
    ...opts,
    // headers 必须放在 ...opts 之后,否则 opts.headers 会把合并好的整块替换掉
    // X-Requested-With:会话过期时 s-ui 回 JSON {success:false,msg:'Invalid login'},
    // 不带则 307 到 /login,nginx 回 200 "OK" 文本,前端分不清
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'XMLHttpRequest', ...(opts.headers || {}) },
  })
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`)
  const ct = r.headers.get('content-type') || ''
  const data = ct.includes('json') ? await r.json() : await r.text()
  if (r.redirected || (data?.success === false && data?.msg === 'Invalid login')) {
    hooks.unauthorized()
    throw new Error('登录已过期,请重新登录')
  }
  return data
}

const form = (o: Record<string, string>) =>
  Object.entries(o).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')

// ---- s-ui cookie-session API ----
export const login = (user: string, pass: string) =>
  req(API, '/login', { method: 'POST', body: form({ user, pass }) })

// 退出要让 s-ui 清掉会话,否则 cookie 仍有效,刷新页面又自动登回去
export const logout = () => req(API, '/logout')

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
export const save = async (object: string, action: string, data: unknown, initUsers?: string) => {
  const body: Record<string, string> = { object, action, data: JSON.stringify(data) }
  if (initUsers) body.initUsers = initUsers
  const r: any = await req(API, '/save', { method: 'POST', body: form(body) })
  // s-ui 保存失败也回 HTTP 200 + {success:false,msg},不在这里拦住,调用方就会把失败当成功提示
  if (r?.success !== true) throw new Error(r?.msg || '保存失败')
  return r
}

// ---- converter(分流规则)----
export const convRules = () => req(CONV, '/admin/rules')
export const convSetRules = (rules: unknown) =>
  req(CONV, '/admin/rules', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rules) })
