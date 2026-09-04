import { rb64, ruuid } from './rand'

// 构造 s-ui client 对象(含各协议 config),用于 save('clients','new', obj)。
// 与 s-ui 前端 randomConfigs 结构一致。
export interface BuildOpts {
  inbounds?: number[]      // 绑定入站 id —— 必须传 s-ui 真实 id(store.nodes[].id),没有默认值
  volumeGiB?: number       // 流量上限(GiB,0=不限)
  expiryMs?: number        // 到期时间戳(ms,0=长期)
  uuid?: string
  hy2pw?: string
  group?: string
  enable?: boolean         // 停用的会员保留配置但连不上
  desc?: string
  flow?: string            // VLESS flow;留空 = 不用 vision
  autoReset?: boolean
  resetDays?: number
  delayStart?: boolean     // 首次连接才开始算到期
  extLinks?: string[]      // 外部订阅/分享链接;s-ui 只保留 type != 'local' 的条目
}

export function buildClient(name: string, o: BuildOpts = {}) {
  // 绑不到真实入站的会员 = 订阅里没有节点 = 链接不可用。宁可报错也不要造一个坏会员。
  if (!o.inbounds || o.inbounds.length === 0) throw new Error('未选择节点:请先在「节点」页确认已有入站')
  const u1 = o.uuid || ruuid()
  const u2 = ruuid()
  const mp = rb64(10)
  const config: Record<string, any> = {
    mixed: { username: name, password: mp },
    socks: { username: name, password: mp },
    http: { username: name, password: mp },
    shadowsocks: { name, password: rb64(32) },
    shadowsocks16: { name, password: rb64(16) },
    shadowtls: { name, password: rb64(32) },
    vmess: { name, uuid: u1, alterId: 0 },
    vless: { name, uuid: u1, flow: o.flow ?? 'xtls-rprx-vision' },
    anytls: { name, password: mp },
    trojan: { name, password: mp },
    naive: { username: name, password: mp },
    hysteria: { name, auth_str: mp },
    tuic: { name, uuid: u2, password: mp },
    hysteria2: { name, password: o.hy2pw || mp },
  }
  return {
    enable: o.enable ?? true, name, config,
    inbounds: o.inbounds,
    // s-ui 会重建 type='local' 的链接,只保留非 local 的,所以外部链接放这里不会被冲掉
    links: (o.extLinks ?? []).filter(u => u.trim())
      .map(uri => ({ remark: 'external', type: 'external', uri: uri.trim() })),
    volume: Math.round((o.volumeGiB || 0) * 1073741824),
    expiry: o.expiryMs || 0,
    up: 0, down: 0, desc: o.desc || '', group: o.group || '',
    delayStart: o.delayStart ?? false,
    autoReset: o.autoReset ?? false,
    resetDays: o.autoReset ? (o.resetDays || 30) : 0,
  }
}
