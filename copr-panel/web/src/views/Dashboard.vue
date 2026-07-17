<script setup lang="ts">
import { reactive, onMounted, onUnmounted, computed } from 'vue'
import { store } from '../store'
import Icon from '../components/Icon.vue'

const total = computed(() => store.members.reduce((a, m) => a + m.gb, 0))
const online = computed(() => store.members.filter(m => m.on).length)
const mx = computed(() => Math.max(...store.members.map(m => m.gb)))

const stats = computed(() => [
  { k: '会员', v: store.members.length, u: '', icon: 'members', d: '实时' },
  { k: '在线', v: online.value, u: '', icon: 'members', d: '实时' },
  { k: '节点', v: store.nodes.length, u: '', icon: 'nodes', d: '实时' },
  { k: '总流量', v: total.value, u: 'GB', icon: 'traffic', d: store.live ? '累计' : '示例' },
])

interface Probe { name: string; net: string; base: number; loss: number; up: number; dn: number; hist: number[] }
const probes = reactive<Probe[]>(store.nodes.map((n, i) => ({
  name: n.name, net: n.net, base: i === 0 ? 44 : 26, loss: i === 0 ? 0.4 : 0.1,
  up: i === 0 ? 60 : 180, dn: i === 0 ? 150 : 340, hist: Array.from({ length: 24 }, () => (i === 0 ? 44 : 26) + (Math.random() * 18 - 8)),
})))
// 固定刻度(0–120ms),曲线稳定小幅波动,不再是满屏噪声
function sparkPath(h: number[]) {
  const MAX = 120
  return 'M' + h.map((v, i) => `${(i / (h.length - 1) * 100).toFixed(1)} ${(32 - Math.min(v, MAX) / MAX * 28).toFixed(1)}`).join(' L ')
}
let timer: number
onMounted(() => {
  timer = window.setInterval(() => {
    probes.forEach(p => {
      p.hist.push(Math.max(8, p.base + (Math.random() * 12 - 6))); if (p.hist.length > 24) p.hist.shift()
      p.loss = Math.max(0, Math.min(3, p.loss + (Math.random() * 0.4 - 0.2)))
      p.up = Math.max(10, p.up + (Math.random() * 44 - 22)); p.dn = Math.max(20, p.dn + (Math.random() * 70 - 35))
    })
  }, 1600)
})
onUnmounted(() => clearInterval(timer))
const onlineMembers = computed(() => store.members.filter(m => m.on))
</script>

<template>
  <div class="grid g4" style="margin-bottom:18px">
    <div v-for="s in stats" :key="s.k" class="stat">
      <div class="k"><div class="ti"><Icon :name="s.icon" :size="15" /></div><span>{{ s.k }}</span></div>
      <div class="v">{{ s.v.toLocaleString() }}<u v-if="s.u">{{ s.u }}</u></div>
      <div class="d">{{ s.d }}</div>
    </div>
  </div>
  <div class="grid g2">
    <div class="panel">
      <div class="sect"><h3>近 7 日流量</h3><div class="sp" /><span class="chip gray">示例</span></div>
      <svg viewBox="0 0 100 90" preserveAspectRatio="none" width="100%" height="150" role="img" aria-label="流量趋势">
        <defs><linearGradient id="ar" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--accent)" stop-opacity=".24" /><stop offset="1" stop-color="var(--accent)" stop-opacity="0" /></linearGradient></defs>
        <path d="M0 55 L16.7 48 L33.3 40 L50 30 L66.7 18 L83.3 4 L100 12 L100 90 L0 90 Z" fill="url(#ar)" />
        <path d="M0 55 L16.7 48 L33.3 40 L50 30 L66.7 18 L83.3 4 L100 12" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
      <div class="ins"><i />周末峰值,jf 贡献最高</div>
    </div>
    <div class="panel">
      <div class="sect"><h3>节点探针</h3><div class="sp" /><span class="chip on">实时</span></div>
      <div v-for="p in probes" :key="p.name" class="probe">
        <div class="ph"><span class="dot on" /><b>{{ p.name }}</b><span class="chip gray">{{ p.net }}</span><div class="sp" /><span class="ms">{{ Math.round(p.hist[p.hist.length - 1]) }}<u>ms</u></span></div>
        <svg class="spark" viewBox="0 0 100 34" preserveAspectRatio="none" role="img" aria-label="延迟"><path :d="sparkPath(p.hist)" fill="none" stroke="var(--accent)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" /></svg>
        <div class="pf"><span>丢包 <b>{{ p.loss.toFixed(1) }}%</b></span><span>↑ <b>{{ Math.round(p.up) }}</b> · ↓ <b>{{ Math.round(p.dn) }}</b> Mbps</span></div>
      </div>
    </div>
  </div>
  <div class="panel" style="margin-top:16px">
    <div class="sect"><h3>当前在线</h3><div class="sp" /><span class="chip on">{{ online }} 人</span></div>
    <div v-for="m in onlineMembers" :key="m.name" class="row">
      <div class="ti2">{{ m.name[0].toUpperCase() }}</div>
      <div class="who"><b>{{ m.name }}</b><span>get/{{ m.name }}</span></div>
      <div class="bar"><i :style="{ width: (m.gb / mx * 100) + '%', background: 'var(--online)' }" /></div>
      <div class="val">{{ m.gb }} GB</div>
    </div>
  </div>
</template>

<style scoped>
.probe{padding:13px 4px}.probe+.probe{border-top:1px solid var(--hairline)}
.ph{display:flex;align-items:center;gap:9px;margin-bottom:7px}.ph b{font-size:13px;font-weight:600}.ph .sp{flex:1}
.ph .ms{font-size:18px;font-weight:700;font-variant-numeric:tabular-nums}.ph .ms u{font-size:11px;font-style:normal;color:var(--ink-3);font-weight:600;margin-left:2px}
.spark{width:100%;height:34px;display:block}
.pf{display:flex;justify-content:space-between;margin-top:5px;font-size:11px;color:var(--ink-4)}.pf b{color:var(--ink-3);font-weight:600;font-variant-numeric:tabular-nums}
.ti2{width:34px;height:34px;border-radius:var(--r-sm);background:var(--inset);display:flex;align-items:center;justify-content:center;color:var(--ink-3);flex:none;font-size:13px;font-weight:700}
</style>
