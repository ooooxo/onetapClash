import { reactive } from 'vue'
import { loadData, hooks } from './api/client'

// 本地日期 YYYY-MM-DD。toISOString 是 UTC:UTC+8 的管理员会看到前一天,编辑再保存就存错日
export const ymd = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

export interface Member { name: string; gb: number; on: boolean; exp: string; id?: number }
// id/tag 是 s-ui 真实入站主键 —— 新建会员时按 id 绑定,绝不写死 [1,2]
export interface Node { id: number; name: string; proto: string; port: number; net: string }

// s-ui /load 实测结构:client {name, up, down, volume, expiry, inbounds[]}; online 看 onlines.user[]。
function mapClient(c: any, onlineUsers: string[]): Member {
  const bytes = (Number(c.up) || 0) + (Number(c.down) || 0)
  let exp = '长期'
  const e = Number(c.expiry)
  // expiry 应为秒;> 1e12 的是旧版面板误写的毫秒,照样能读
  if (e > 0) exp = ymd(new Date(e > 1e12 ? e : e * 1000))
  return { id: c.id, name: c.name ?? c.username ?? '?', gb: Math.round(bytes / 1e9), on: onlineUsers.includes(c.name), exp }
}
function mapInbound(i: any): Node {
  const net = /hysteria|tuic|quic/i.test(i.type || '') ? 'UDP' : 'TCP'
  return { id: Number(i.id), name: i.tag || i.type || 'node', proto: i.type || '?', port: i.listen_port || i.port || 443, net }
}

export type ViewId = 'dash' | 'nodes' | 'members' | 'sub' | 'traffic' | 'settings'

export const store = reactive({
  loggedIn: false,
  view: 'dash' as ViewId,
  theme: (localStorage.getItem('theme') as 'dark' | 'light') || 'dark',
  domain: (typeof location !== 'undefined' && location.hostname) || 'panel',  // 自动取当前访问域名,不写死
  live: false,      // true = 已接 s-ui 真数据
  loading: false,
  error: '',
  // 初始为空 —— 没接上后端就什么都不显示,绝不用演示数据冒充真实状态
  members: [] as Member[],
  nodes: [] as Node[],
  onlineInbounds: [] as string[],  // 有活跃连接的节点 tag(真数据,来自 onlines）
  onlineUsers: [] as string[],
  // 跟随面板协议/端口(HTTPS 面板→HTTPS 订阅);名称要编码,否则中文进二维码(byte 模式)会被截断
  subUrl(name: string) { return `${location.origin}/get/${encodeURIComponent(name)}` },
  suiPort: 2095,        // s-ui 原面板端口(仅供「设置」页展示,访问不再用它)
  suiPath: '/app/',
  // 同源 HTTPS 反代,不再直连 :2095 —— 那个口是明文 HTTP 且已在防火墙关掉
  suiUrl() { return `${location.origin}${this.suiPath}` },
  async load() {
    this.loading = true; this.error = ''
    try {
      const r: any = await loadData()
      // 会话过期由 req 统一识别(Invalid login / 被 307);其余非 JSON 响应同样没有 success 字段。
      // 判活只看 success===true;clients/inbounds 在全新安装时是 null(不是 []),按空数组处理,
      // 否则"后端一切正常但还没建会员"会被误判成后端不可达。
      if (!r || typeof r !== 'object' || r.success !== true) {
        throw new Error(r?.msg || '未登录或后端未返回数据')
      }
      const o = r.obj ?? {}
      const onlineUsers: string[] = o?.onlines?.user ?? []
      this.onlineUsers = onlineUsers
      this.onlineInbounds = o?.onlines?.inbound ?? []
      this.members = (o.clients ?? []).map((c: any) => mapClient(c, onlineUsers))
      this.nodes = (o.inbounds ?? []).map(mapInbound)
      this.live = true
    } catch (e: any) {
      this.error = String(e?.message || e); this.live = false
      throw e   // 让 onMounted(回登录页)/doLogin(报错)知道没成功,绝不假装演示数据
    } finally { this.loading = false }
  },
  toggleTheme() {
    this.theme = this.theme === 'light' ? 'dark' : 'light'
    document.documentElement.dataset.theme = this.theme === 'light' ? 'light' : ''
    localStorage.setItem('theme', this.theme)
  },
})

if (store.theme === 'light') document.documentElement.dataset.theme = 'light'

// 任一请求发现会话过期 → 回登录页,不留在一个所有操作都失败的面板里
hooks.unauthorized = () => { store.loggedIn = false; store.live = false }
