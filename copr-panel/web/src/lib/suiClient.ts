import { rb64, ruuid } from './rand'

// 构造 s-ui client 对象(含各协议 config),用于 save('clients','new', obj)。
// 与 s-ui 前端 randomConfigs 结构一致。
export interface BuildOpts {
  inbounds?: number[]      // 绑定入站 id;默认 [1,2] = HY2 + VLESS
  volumeGiB?: number       // 流量上限(GiB,0=不限)
  expiryMs?: number        // 到期时间戳(ms,0=长期)
  uuid?: string
  hy2pw?: string
  group?: string
}

export function buildClient(name: string, o: BuildOpts = {}) {
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
    vless: { name, uuid: u1, flow: 'xtls-rprx-vision' },
    anytls: { name, password: mp },
    trojan: { name, password: mp },
    naive: { username: name, password: mp },
    hysteria: { name, auth_str: mp },
    tuic: { name, uuid: u2, password: mp },
    hysteria2: { name, password: o.hy2pw || mp },
  }
  return {
    enable: true, name, config,
    inbounds: o.inbounds && o.inbounds.length ? o.inbounds : [1, 2],
    links: [],
    volume: Math.round((o.volumeGiB || 0) * 1073741824),
    expiry: o.expiryMs || 0,
    up: 0, down: 0, desc: '', group: o.group || '',
    delayStart: false, autoReset: false, resetDays: 0,
  }
}
