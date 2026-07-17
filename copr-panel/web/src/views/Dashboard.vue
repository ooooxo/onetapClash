<script setup lang="ts">
import { computed, ref, reactive, onMounted, onUnmounted } from 'vue'
import { store } from '../store'
import { loadData } from '../api/client'
import Icon from '../components/Icon.vue'

const total = computed(() => store.members.reduce((a, m) => a + m.gb, 0))
const online = computed(() => store.members.filter(m => m.on).length)
const mx = computed(() => Math.max(1, ...store.members.map(m => m.gb)))
const stats = computed(() => [
  { k: '会员', v: store.members.length, u: '', icon: 'members' },
  { k: '在线', v: online.value, u: '', icon: 'members' },
  { k: '节点', v: store.nodes.length, u: '', icon: 'nodes' },
  { k: '累计流量', v: total.value, u: 'GB', icon: 'traffic' },
])
const onlineMembers = computed(() => [...store.members].filter(m => m.on).sort((a, b) => b.gb - a.gb))
const nodeActive = (n: { name: string }) => store.onlineInbounds.includes(n.name)

// ── 实时吞吐:轮询累计流量差值(btop 同理,真数据)──────────────────────────
const hist = reactive<{ up: number; down: number }[]>([])
const curUp = ref(0), curDown = ref(0)
const peak = computed(() => hist.length ? Math.max(...hist.map(s => s.up + s.down)) : 0)
let prevUp = 0, prevDown = 0, prevT = 0, timer = 0
const N = 40

function fmtR(m: number) { return m >= 1 ? m.toFixed(1) + ' Mbps' : (m * 1000).toFixed(0) + ' Kbps' }
const totVals = computed(() => hist.map(s => s.up + s.down))
const linePath = computed(() => {
  const v = totVals.value; if (v.length < 2) return ''
  const mxv = Math.max(0.01, ...v)
  return 'M' + v.map((x, i) => `${(i / (v.length - 1) * 100).toFixed(1)} ${(56 - x / mxv * 50).toFixed(1)}`).join(' L ')
})
const areaPath = computed(() => linePath.value ? `${linePath.value} L 100 60 L 0 60 Z` : '')

async function poll() {
  try {
    const r: any = await loadData()
    const o = r?.obj ?? r
    const clients: any[] = o?.clients ?? []
    if (Array.isArray(clients) && clients.length) {
      store.members = clients.map((c: any) => ({
        id: c.id, name: c.name, gb: Math.round(((+c.up || 0) + (+c.down || 0)) / 1e9),
        on: (o?.onlines?.user ?? []).includes(c.name),
        exp: c.expiry > 0 ? new Date((+c.expiry > 1e12 ? +c.expiry : +c.expiry * 1000)).toISOString().slice(0, 10) : '长期',
      }))
    }
    store.onlineInbounds = o?.onlines?.inbound ?? []
    const tu = clients.reduce((s, c) => s + (+c.up || 0), 0)
    const td = clients.reduce((s, c) => s + (+c.down || 0), 0)
    const now = performance.now() / 1000
    if (prevT) {
      const dt = Math.max(0.5, now - prevT)
      curUp.value = Math.max(0, (tu - prevUp) * 8 / 1e6 / dt)
      curDown.value = Math.max(0, (td - prevDown) * 8 / 1e6 / dt)
      hist.push({ up: curUp.value, down: curDown.value })
      while (hist.length > N) hist.shift()
    }
    prevUp = tu; prevDown = td; prevT = now
  } catch { /* keep last */ }
}
onMounted(() => { if (store.live) { poll(); timer = window.setInterval(poll, 3000) } })
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <div class="grid g4" style="margin-bottom:18px">
    <div v-for="s in stats" :key="s.k" class="stat">
      <div class="k"><div class="ti"><Icon :name="s.icon" :size="15" /></div><span>{{ s.k }}</span></div>
      <div class="v">{{ s.v.toLocaleString() }}<u v-if="s.u">{{ s.u }}</u></div>
      <div class="d">{{ store.live ? '实时' : '演示数据' }}</div>
    </div>
  </div>
  <div class="grid g2">
    <div class="panel">
      <div class="sect"><h3>实时吞吐</h3><div class="sp" /><span class="chip" :class="store.live ? 'on' : 'gray'">{{ store.live ? '每 3s' : '演示' }}</span></div>
      <div class="rrow">
        <div class="rc"><span class="rl">↑ 上行</span><b class="rv">{{ fmtR(curUp) }}</b></div>
        <div class="rc"><span class="rl">↓ 下行</span><b class="rv">{{ fmtR(curDown) }}</b></div>
        <div class="rc"><span class="rl">峰值</span><b class="rv mut">{{ fmtR(peak) }}</b></div>
      </div>
      <svg v-if="totVals.length >= 2" viewBox="0 0 100 60" preserveAspectRatio="none" width="100%" height="120" role="img" aria-label="实时吞吐">
        <defs><linearGradient id="tg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--accent)" stop-opacity=".28" /><stop offset="1" stop-color="var(--accent)" stop-opacity="0" /></linearGradient></defs>
        <path :d="areaPath" fill="url(#tg)" />
        <path :d="linePath" fill="none" stroke="var(--accent)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
      <div v-else class="empty">{{ store.live ? '采样中…(3s 后出曲线)' : '演示模式' }}</div>
      <div class="nstrip">
        <span v-for="n in store.nodes" :key="n.name" class="nchip" :class="{ on: nodeActive(n) }">
          <span class="dot" :class="{ on: nodeActive(n) }" />{{ n.name }} · {{ n.net }}
        </span>
      </div>
    </div>

    <div class="panel">
      <div class="sect"><h3>当前在线</h3><div class="sp" /><span class="chip on">{{ online }} 人</span></div>
      <template v-if="onlineMembers.length">
        <div v-for="m in onlineMembers" :key="m.name" class="row">
          <div class="ti2">{{ m.name[0].toUpperCase() }}</div>
          <div class="who"><b>{{ m.name }}</b><span>累计 {{ m.gb }} GB</span></div>
          <div class="bar"><i :style="{ width: (m.gb / mx * 100) + '%', background: 'var(--online)' }" /></div>
          <div class="val">{{ m.gb }} GB</div>
        </div>
      </template>
      <div v-else class="empty" style="padding:20px 0;text-align:center">暂无在线用户</div>
    </div>
  </div>
</template>

<style scoped>
.ti2{width:32px;height:32px;border-radius:var(--r-sm);background:var(--inset);display:flex;align-items:center;justify-content:center;color:var(--ink-3);flex:none;font-size:13px;font-weight:700}
.rrow{display:flex;gap:24px;margin-bottom:12px}
.rc{display:flex;flex-direction:column;gap:2px}
.rl{font-size:11px;color:var(--ink-3);font-weight:500}
.rv{font-size:20px;font-weight:700;font-variant-numeric:tabular-nums}.rv.mut{color:var(--ink-3);font-size:16px}
.empty{height:120px;display:flex;align-items:center;justify-content:center;font-size:12px;color:var(--ink-4)}
.nstrip{display:flex;flex-wrap:wrap;gap:6px;margin-top:12px}
.nchip{display:inline-flex;align-items:center;gap:6px;font-size:11px;color:var(--ink-3);background:var(--inset);padding:4px 9px;border-radius:var(--r-pill)}
.nchip.on{color:var(--ink-2)}
</style>
