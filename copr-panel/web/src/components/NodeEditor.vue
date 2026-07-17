<script setup lang="ts">
import { ref } from 'vue'
import Modal from './Modal.vue'
import XSelect from './XSelect.vue'
import Switch from './Switch.vue'
import Icon from './Icon.vue'
import { rb64, rhex } from '../lib/rand'
import { toast } from '../ui'
import { store } from '../store'
const emit = defineEmits<{ (e: 'close'): void }>()
function openSui() { window.open(store.suiUrl(), '_blank') }

const tab = ref<'reality' | 'hy2' | 'tuic'>('reality')
function preset(p: 'reality' | 'hy2' | 'tuic') { tab.value = p; toast('已套用预设') }

// Reality
const rTag = ref('reality-in'); const rPort = ref('443')
const tlsMode = ref('Reality(推荐,借真站点证书)')
const dest = ref('www.apple.com:443'); const sni = ref('www.apple.com')
const privKey = ref(rb64(43)); const pubKey = ref(rb64(43)); const shortId = ref(rhex(8))
const flow = ref('xtls-rprx-vision'); const utls = ref('chrome'); const transport = ref('none · 裸 TCP(最快)')
const sniff = ref(true)
const certR = ref('ACME 自动'); const sniR = ref('copr.site'); const alpn = ref('h2, http/1.1')
function regenRK() { privKey.value = rb64(43); pubKey.value = rb64(43) }

// HY2
const hTag = ref('hysteria2-in'); const hPort = ref('443'); const ignoreBw = ref(true)
const up = ref('900'); const dn = ref('900'); const obfs = ref(false); const obfsPw = ref(rb64(12))
const masq = ref('https://bing.com'); const certH = ref('ACME 自动(copr.site)'); const sniH = ref('copr.site')

// TUIC
const tTag = ref('tuic-in'); const tPort = ref('2053'); const cc = ref('bbr'); const relay = ref('native')
const certT = ref('ACME 自动'); const sniT = ref('copr.site')

const adv = () => openSui()
// 节点 = inbound + tls_id,改错会断所有用户;安全起见走 s-ui 原面板(此表单为参数参考)
const saveNode = () => { openSui(); toast('已打开 s-ui 开节点(节点配置直接改核心,故走原面板最稳)'); emit('close') }
</script>

<template>
  <Modal wide @close="emit('close')">
    <div class="mh3">开设节点</div>
    <div class="msub">选预设自动拉满,或手动调 · 保存后 s-ui 重载(用户短暂重连)</div>
    <div class="psets">
      <div class="pset" :class="{ on: tab === 'reality' }" @click="preset('reality')"><b>极速抗封锁</b><span>VLESS·Vision·Reality</span></div>
      <div class="pset" :class="{ on: tab === 'hy2' }" @click="preset('hy2')"><b>高速 UDP</b><span>Hysteria2·BBR 拉满</span></div>
      <div class="pset" :class="{ on: tab === 'tuic' }" @click="preset('tuic')"><b>备选 QUIC</b><span>TUIC v5·BBR</span></div>
    </div>
    <div class="mtabs">
      <button :class="{ on: tab === 'reality' }" @click="tab = 'reality'">VLESS·Reality</button>
      <button :class="{ on: tab === 'hy2' }" @click="tab = 'hy2'">Hysteria2</button>
      <button :class="{ on: tab === 'tuic' }" @click="tab = 'tuic'">TUIC</button>
    </div>

    <div v-if="tab === 'reality'">
      <div class="frow"><div class="fld"><label>备注 / tag</label><input v-model="rTag" /></div><div class="fld"><label>监听端口</label><input v-model="rPort" /></div></div>
      <div class="ssec">TLS</div>
      <div class="fld"><label>TLS 模式</label><XSelect v-model="tlsMode" :options="['Reality(推荐,借真站点证书)', '标准 TLS']" /></div>
      <template v-if="tlsMode.startsWith('Reality')">
        <div class="fld"><label>握手目标 dest(真站点)</label><input v-model="dest" /><div class="fnote">须 TLS1.3、非 CDN,端口通常 443</div></div>
        <div class="fld"><label>SNI / serverNames</label><input v-model="sni" /></div>
        <div class="fld gen"><label>私钥 x25519</label><input v-model="privKey" readonly /><button class="rg" @click="regenRK">重新生成</button><div class="fnote">公钥: {{ pubKey }}</div></div>
        <div class="fld gen"><label>Short ID</label><input v-model="shortId" readonly /><button class="rg" @click="shortId = rhex(8)">刷新</button></div>
      </template>
      <template v-else>
        <div class="frow"><div class="fld"><label>证书</label><XSelect v-model="certR" :options="['ACME 自动', '自签名', '已有证书']" /></div><div class="fld"><label>SNI</label><input v-model="sniR" /></div></div>
        <div class="fld"><label>ALPN</label><input v-model="alpn" /></div>
      </template>
      <div class="ssec">协议 / 传输</div>
      <div class="frow"><div class="fld"><label>Flow</label><XSelect v-model="flow" :options="['xtls-rprx-vision', '(空)']" /></div><div class="fld"><label>uTLS 指纹</label><XSelect v-model="utls" :options="['chrome', 'firefox', 'safari', 'ios', 'edge', 'random']" /></div></div>
      <div class="fld"><label>传输</label><XSelect v-model="transport" :options="['none · 裸 TCP(最快)', 'ws', 'grpc', 'httpupgrade']" /></div>
      <div class="swrow"><div class="tx"><b>流量嗅探</b><span>识别域名以分流</span></div><Switch v-model="sniff" /></div>
      <div class="adv" @click="adv"><Icon name="bolt" :size="14" />高级设置(ACME / 传输 / mux)→ s-ui 原面板</div>
    </div>

    <div v-else-if="tab === 'hy2'">
      <div class="frow"><div class="fld"><label>备注 / tag</label><input v-model="hTag" /></div><div class="fld"><label>监听端口</label><input v-model="hPort" /></div></div>
      <div class="ssec">带宽 / 拥塞</div>
      <div class="swrow"><div class="tx"><b>忽略客户端带宽(BBR)</b><span>解掉限速,推荐开 —— 正是你 10MB/s 的修法</span></div><Switch v-model="ignoreBw" /></div>
      <div class="frow"><div class="fld"><label>上行 Mbps(brutal 时)</label><input v-model="up" /></div><div class="fld"><label>下行 Mbps</label><input v-model="dn" /></div></div>
      <div class="ssec">混淆 / 伪装</div>
      <div class="swrow"><div class="tx"><b>obfs salamander</b><span>抗主动探测,需客户端一致</span></div><Switch v-model="obfs" /></div>
      <div v-if="obfs" class="fld"><label>obfs 密码</label><input v-model="obfsPw" /></div>
      <div class="fld"><label>masquerade 伪装</label><input v-model="masq" /></div>
      <div class="ssec">TLS</div>
      <div class="frow"><div class="fld"><label>证书</label><XSelect v-model="certH" :options="['ACME 自动(copr.site)', '自签名', '已有证书']" /></div><div class="fld"><label>SNI</label><input v-model="sniH" /></div></div>
      <div class="adv" @click="adv"><Icon name="bolt" :size="14" />高级设置 → s-ui 原面板</div>
    </div>

    <div v-else>
      <div class="frow"><div class="fld"><label>备注 / tag</label><input v-model="tTag" /></div><div class="fld"><label>监听端口</label><input v-model="tPort" /></div></div>
      <div class="ssec">拥塞</div>
      <div class="frow"><div class="fld"><label>拥塞控制</label><XSelect v-model="cc" :options="['bbr', 'cubic', 'new_reno']" /></div><div class="fld"><label>UDP relay</label><XSelect v-model="relay" :options="['native', 'quic']" /></div></div>
      <div class="ssec">TLS</div>
      <div class="frow"><div class="fld"><label>证书</label><XSelect v-model="certT" :options="['ACME 自动', '自签名']" /></div><div class="fld"><label>SNI</label><input v-model="sniT" /></div></div>
      <div class="fnote">凭证在会员「配置」里自动分配(uuid + password)。</div>
      <div class="adv" @click="adv"><Icon name="bolt" :size="14" />高级设置 → s-ui 原面板</div>
    </div>

    <div class="marow"><button class="btn" @click="saveNode">保存节点</button><button class="gh" @click="emit('close')">取消</button></div>
  </Modal>
</template>
