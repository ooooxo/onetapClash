import { rb64, ruuid } from './rand'

// 构造 s-ui client 对象(含各协议 config),用于 save('clients','new', obj)。
// 与 s-ui 前端 randomConfigs 结构一致。
export interface BuildOpts {
  inbounds?: number[]      // 绑定入站 id —— 必须传 s-ui 真实 id(store.nodes[].id),没有默认值
  volumeGiB?: number       // 流量上限(GiB,0=不限)
  expirySec?: number       // 到期 Unix 时间戳(秒!s-ui 按秒比较,传毫秒=永不过期;0=长期)
  uuid?: string
  hy2pw?: string
  group?: string
  enable?: boolean         // 停用的会员保留配置但连不上
  desc?: string
  flow?: string            // VLESS flow;留空 = 不用 vision
  autoReset?: boolean
  resetDays?: number       // autoReset=重置周期;仅 delayStart=有效期(首次连接起算)
  delayStart?: boolean     // 首次连接才开始算到期
  extLinks?: string[]      // 外部订阅/分享链接;s-ui 只保留 type != 'local' 的条目
}

// 外部链接分类:http(s) 是第三方订阅,s-ui 按 'sub' 拉取展开;其余(vless:// 等)是单条分享链接
export const extLink = (uri: string) =>
  ({ remark: 'external', type: /^https?:\/\//i.test(uri) ? 'sub' : 'external', uri })

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
    links: (o.extLinks ?? []).map(u => u.trim()).filter(Boolean).map(extLink),
    volume: Math.round((o.volumeGiB || 0) * 1073741824),
    // 延迟启动且不自动重置:s-ui 在首次连接时写 expiry = now + resetDays 天,这里必须给 0
    expiry: o.delayStart && !o.autoReset ? 0 : (o.expirySec || 0),
    up: 0, down: 0, desc: o.desc || '', group: o.group || '',
    delayStart: o.delayStart ?? false,
    autoReset: o.autoReset ?? false,
    // delayStart 也要带天数:resetDays=0 会让会员首次连接一分钟后就到期
    resetDays: o.autoReset || o.delayStart ? (o.resetDays || 30) : 0,
  }
}
