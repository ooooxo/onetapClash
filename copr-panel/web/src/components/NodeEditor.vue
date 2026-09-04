<script setup lang="ts">
import { ref } from 'vue'
import Modal from './Modal.vue'
import Switch from './Switch.vue'
import Icon from './Icon.vue'
import { rhex } from '../lib/rand'
import { toast } from '../ui'
import { store } from '../store'
import { save as apiSave, realityKeypair } from '../api/client'

// 这个表单是【真的会建节点】的:先建 tls 记录,再建 inbound,s-ui 立刻热加载。
// (旧版所有字段都只是摆设,点保存只是打开 s-ui —— 那才是「假数据」的重灾区。)
const emit = defineEmits<{ (e: 'close'): void }>()
function openSui() { window.open(store.suiUrl(), '_blank') }

type Kind = 'hy2' | 'reality' | 'tuic'
const kind = ref<Kind>('hy2')
const busy = ref(false)
const err = ref('')

const tag = ref('quick')
const port = ref('443')
const domain = ref(store.domain)
const certPath = ref(`/etc/letsencrypt/live/${store.domain}/fullchain.pem`)
const keyPath = ref(`/etc/letsencrypt/live/${store.domain}/privkey.pem`)
const ignoreBw = ref(true)          // hy2:忽略客户端带宽宣告,交给 BBR 跑满
const dest = ref('www.apple.com')   // reality 握手目标

function pick(k: Kind) {
  kind.value = k
  if (k === 'hy2') { tag.value = 'quick'; port.value = '443' }
  if (k === 'reality') { tag.value = 'reality'; port.value = '8443' }   // 443/tcp 通常被 nginx 占着
  if (k === 'tuic') { tag.value = 'tuic'; port.value = '2053' }
}

// save 返回 {obj:{tls:[...]}} —— 从里面取回新建的 tls id
async function createTls(name: string, server: any, client: any): Promise<number> {
  const r: any = await apiSave('tls', 'new', { id: 0, name, server, client })
  if (r?.success !== true) throw new Error(r?.msg || '创建 TLS 失败')
  const list: any[] = r?.obj?.tls ?? []
  const hit = list.find(t => t.name === name)
  if (!hit) throw new Error('创建了 TLS 但拿不到 id')
  return hit.id
}

async function create() {
  err.value = ''
  const t = tag.value.trim(); const p = Number(port.value)
  if (!t) { err.value = '备注 / tag 必填'; return }
  if (!(p > 0 && p < 65536)) { err.value = '端口不合法'; return }
  if (store.nodes.some(n => n.name === t)) { err.value = `tag「${t}」已存在` ; return }
  busy.value = true
  try {
    let tlsId: number
    let inbound: Record<string, any>
    if (kind.value === 'reality') {
      const { priv, pub } = await realityKeypair()
      if (!priv || !pub) throw new Error('拿不到 Reality 密钥对')
      const sid = rhex(8)
      tlsId = await createTls(`reality-${dest.value}`,
        { enabled: true, server_name: dest.value,
          reality: { enabled: true, handshake: { server: dest.value, server_port: 443 }, private_key: priv, short_id: [sid] } },
        { enabled: true, server_name: dest.value,
          utls: { enabled: true, fingerprint: 'chrome' },
          reality: { enabled: true, public_key: pub, short_id: sid } })
      // 注意:不要带 transport:{} —— 空 transport 会让 s-ui 生成链接时报 malformed JSON
      inbound = { id: 0, type: 'vless', tag: t, listen: '::', listen_port: p, tls_id: tlsId,
        addrs: [{ server: domain.value, server_port: p }], out_json: {} }
    } else {
      tlsId = await createTls(`${domain.value}-le-${t}`,
        { enabled: true, server_name: domain.value, alpn: ['h3'], certificate_path: certPath.value, key_path: keyPath.value },
        { enabled: true, server_name: domain.value, insecure: false, alpn: ['h3'] })
      inbound = kind.value === 'hy2'
        ? { id: 0, type: 'hysteria2', tag: t, listen: '::', listen_port: p, tls_id: tlsId,
            ignore_client_bandwidth: ignoreBw.value, addrs: [{ server: domain.value, server_port: p }], out_json: {} }
        : { id: 0, type: 'tuic', tag: t, listen: '::', listen_port: p, tls_id: tlsId,
            congestion_control: 'bbr', addrs: [{ server: domain.value, server_port: p }], out_json: {} }
    }
    const r: any = await apiSave('inbounds', 'new', inbound)
    if (r?.success !== true) throw new Error(r?.msg || '创建入站失败')
    await store.load()
    toast(`节点已开设:${t} :${p}`)
    emit('close')
  } catch (e: any) {
    err.value = String(e?.message || e)
  }
  busy.value = false
}
</script>

<template>
  <Modal wide @close="emit('close')">
    <div class="mh3">开设节点</div>
    <div class="msub">选预设 → 填端口 → 保存。会真的写进 s-ui 并热加载(在线用户短暂重连)。</div>
    <div class="psets">
      <div class="pset" :class="{ on: kind === 'hy2' }" @click="pick('hy2')"><b>高速 UDP</b><span>Hysteria2 · 真实证书</span></div>
      <div class="pset" :class="{ on: kind === 'reality' }" @click="pick('reality')"><b>抗封锁 TCP</b><span>VLESS · Vision · Reality</span></div>
      <div class="pset" :class="{ on: kind === 'tuic' }" @click="pick('tuic')"><b>备选 QUIC</b><span>TUIC v5 · BBR</span></div>
    </div>

    <div class="frow"><div class="fld"><label>备注 / tag</label><input v-model="tag" /></div>
      <div class="fld"><label>监听端口</label><input v-model="port" /></div></div>
    <div class="fld"><label>对外地址(客户端连的域名)</label><input v-model="domain" /></div>

    <template v-if="kind === 'reality'">
      <div class="fld"><label>握手目标 dest(真站点,需 TLS1.3 且非 CDN)</label><input v-model="dest" />
        <div class="fnote">Reality 借这个站点的证书,SNI 也用它;客户端看起来就是在访问它。</div></div>
      <div class="fnote">私钥/公钥/short-id 由 s-ui 生成,保存时自动填。</div>
    </template>
    <template v-else>
      <div class="fld"><label>证书 fullchain.pem</label><input v-model="certPath" /></div>
      <div class="fld"><label>私钥 privkey.pem</label><input v-model="keyPath" /></div>
      <div class="fnote">用 certbot 申的 Let's Encrypt 证书路径;证书续期后要重启 s-ui 才会重新读取。</div>
      <div v-if="kind === 'hy2'" class="swrow"><div class="tx"><b>忽略客户端带宽宣告</b><span>不按客户端报的速率限速,交给 BBR 跑满</span></div><Switch v-model="ignoreBw" /></div>
    </template>

    <div v-if="err" class="lerr">{{ err }}</div>
    <div class="fnote" style="margin-top:10px">
      端口要在防火墙放行:UDP 用于 Hysteria2 / TUIC,TCP 用于 Reality。
      <span class="adv" @click="openSui"><Icon name="bolt" :size="13" />更细的参数(mux / 传输 / ACME)→ s-ui 原面板</span>
    </div>
    <div class="marow"><button class="btn" :disabled="busy" @click="create">{{ busy ? '创建中…' : '创建节点' }}</button><button class="gh" @click="emit('close')">取消</button></div>
  </Modal>
</template>

<style scoped>
.lerr{font-size:12px;color:var(--crit);font-weight:600;margin-top:10px}
</style>
