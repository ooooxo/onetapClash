import { reactive } from 'vue'
import { loadData } from './api/client'

export interface Member { name: string; gb: number; on: boolean; exp: string; id?: number }
export interface Node { name: string; proto: string; port: number; net: string }

// 演示数据 — 接线上(store.load)后由 s-ui getData 覆盖
const MOCK_MEMBERS: Member[] = [
  { name: 'jf', gb: 210, on: true, exp: '长期' },
  { name: 'suki', gb: 156, on: true, exp: '2026-12-31' },
  { name: 'shaoye', gb: 132, on: false, exp: '2026-10-01' },
  { name: 'nox', gb: 98, on: true, exp: '长期' },
  { name: 'xuan', gb: 76, on: false, exp: '2026-09-15' },
  { name: 'tuxh', gb: 54, on: false, exp: '2026-08-20' },
  { name: 'alb', gb: 41, on: false, exp: '长期' },
  { name: 'test', gb: 12, on: false, exp: '2026-07-31' },
  { name: 'outbound', gb: 8, on: false, exp: '长期' },
]
const MOCK_NODES: Node[] = [
  { name: 'VLESS · Reality', proto: 'vless', port: 443, net: 'TCP' },
  { name: 'Hysteria2', proto: 'hysteria2', port: 443, net: 'UDP' },
]

// s-ui /load 实测结构:client {name, up, down, volume, expiry, inbounds[]}; online 看 onlines.user[]。
function mapClient(c: any, onlineUsers: string[]): Member {
  const bytes = (Number(c.up) || 0) + (Number(c.down) || 0)
  let exp = '长期'
  const e = Number(c.expiry)
  if (e > 0) { try { exp = new Date(e > 1e12 ? e : e * 1000).toISOString().slice(0, 10) } catch { /* keep */ } }
  return { id: c.id, name: c.name ?? c.username ?? '?', gb: Math.round(bytes / 1e9), on: onlineUsers.includes(c.name), exp }
}
function mapInbound(i: any): Node {
  const net = /hysteria|tuic|quic/i.test(i.type || '') ? 'UDP' : 'TCP'
  return { name: i.tag || i.type || 'node', proto: i.type || '?', port: i.listen_port || i.port || 443, net }
}

export type ViewId = 'dash' | 'nodes' | 'members' | 'sub' | 'traffic' | 'settings'

export const store = reactive({
  loggedIn: false,
  view: 'dash' as ViewId,
  theme: (localStorage.getItem('theme') as 'dark' | 'light') || 'dark',
  domain: 'copr.site',
  live: false,      // true = 已接 s-ui 真数据
  loading: false,
  error: '',
  members: MOCK_MEMBERS as Member[],
  nodes: MOCK_NODES as Node[],
  subUrl(name: string) { return `${location.origin}/get/${name}` }, // 跟随面板协议/端口(HTTPS 面板→HTTPS 订阅)
  suiUrl() { return `http://${this.domain}:2020/app/` }, // s-ui 原面板(深水区:开节点/改凭证)
  async load() {
    this.loading = true; this.error = ''
    try {
      const r: any = await loadData()
      const o = r?.obj ?? r
      const onlineUsers: string[] = o?.onlines?.user ?? []
      if (Array.isArray(o?.clients)) this.members = o.clients.map((c: any) => mapClient(c, onlineUsers))
      if (Array.isArray(o?.inbounds)) this.nodes = o.inbounds.map(mapInbound)
      this.live = true
    } catch (e: any) {
      this.error = String(e?.message || e); this.live = false   // 保持演示数据
    } finally { this.loading = false }
  },
  toggleTheme() {
    this.theme = this.theme === 'light' ? 'dark' : 'light'
    document.documentElement.dataset.theme = this.theme === 'light' ? 'light' : ''
    localStorage.setItem('theme', this.theme)
  },
})

if (store.theme === 'light') document.documentElement.dataset.theme = 'light'
