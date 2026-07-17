<script setup lang="ts">
import { computed, reactive, watch } from 'vue'
import { store } from '../store'
import { getStats } from '../api/client'
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
const nodeIcon = (p: string) => /hysteria|tuic/i.test(p) ? 'bolt' : 'shield'

interface NS { spark: number[]; peak: number; up: number; down: number; loaded: boolean }
const nodeStats = reactive<Record<string, NS>>({})

function fmtB(b: number) {
  if (b >= 1e9) return (b / 1e9).toFixed(1) + ' GB'
  if (b >= 1e6) return (b / 1e6).toFixed(0) + ' MB'
  if (b >= 1e3) return (b / 1e3).toFixed(0) + ' KB'
  return b + ' B'
}
function sparkPath(vals: number[]) {
  if (vals.length < 2) return ''
  const mn = Math.min(...vals), mx2 = Math.max(...vals), rng = Math.max(1, mx2 - mn)
  const n = vals.length
  return 'M' + vals.map((v, i) => `${(i / (n - 1) * 100).toFixed(1)} ${(30 - (v - mn) / rng * 26).toFixed(1)}`).join(' L ')
}

async function fetchNodeStats() {
  if (!store.live) return
  for (const n of store.nodes) {
    try {
      const r: any = await getStats('inbound', n.name)
      const rows: any[] = r?.obj || []
      const buckets: Record<number, { up: number; down: number }> = {}
      for (const e of rows) {
        const t = e.dateTime
        if (!buckets[t]) buckets[t] = { up: 0, down: 0 }
        if (e.direction) buckets[t].up += e.traffic; else buckets[t].down += e.traffic
      }
      const ts = Object.keys(buckets).map(Number).sort((a, b) => a - b)
      const spark = ts.map(t => buckets[t].up + buckets[t].down)
      const up = ts.reduce((s, t) => s + buckets[t].up, 0)
      const down = ts.reduce((s, t) => s + buckets[t].down, 0)
      nodeStats[n.name] = { spark, peak: spark.length ? Math.max(...spark) : 0, up, down, loaded: true }
    } catch { nodeStats[n.name] = { spark: [], peak: 0, up: 0, down: 0, loaded: true } }
  }
}
// 真节点名到位(load 完成)就抓流量;避免挂载时还是 mock 名导致查空
watch(() => store.live + '|' + store.nodes.map(n => n.name).join('|'), fetchNodeStats, { immediate: true })
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
      <div class="sect"><h3>节点流量</h3><div class="sp" /><span class="chip" :class="store.live ? 'on' : 'gray'">{{ store.live ? '实时' : '演示' }}</span></div>
      <div v-for="n in store.nodes" :key="n.name" class="pnode">
        <div class="ph">
          <span class="dot" :class="{ on: nodeActive(n) }" />
          <div class="ti2"><Icon :name="nodeIcon(n.proto)" :size="15" /></div>
          <b>{{ n.name }}</b><span class="chip gray">{{ n.net }}</span>
          <div class="sp" />
          <span class="chip" :class="nodeActive(n) ? 'on' : 'gray'">{{ nodeActive(n) ? '活跃' : '空闲' }}</span>
        </div>
        <svg v-if="nodeStats[n.name]?.spark.length >= 2" class="spark" viewBox="0 0 100 32" preserveAspectRatio="none" role="img" aria-label="流量趋势">
          <path :d="sparkPath(nodeStats[n.name].spark)" fill="none" stroke="var(--accent)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
        <div v-else class="spark-empty">{{ store.live ? '暂无足够流量样本' : '演示模式无数据' }}</div>
        <div class="pf">
          <span>峰值 <b>{{ fmtB(nodeStats[n.name]?.peak || 0) }}</b></span>
          <span>↑ <b>{{ fmtB(nodeStats[n.name]?.up || 0) }}</b> · ↓ <b>{{ fmtB(nodeStats[n.name]?.down || 0) }}</b></span>
        </div>
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
      <div v-else class="spark-empty" style="padding:20px 0;text-align:center">暂无在线用户</div>
    </div>
  </div>
</template>

<style scoped>
.ti2{width:32px;height:32px;border-radius:var(--r-sm);background:var(--inset);display:flex;align-items:center;justify-content:center;color:var(--ink-3);flex:none;font-size:13px;font-weight:700}
.pnode{padding:12px 2px}.pnode+.pnode{border-top:1px solid var(--hairline)}
.ph{display:flex;align-items:center;gap:9px;margin-bottom:7px}.ph b{font-size:13px;font-weight:600}.ph .sp{flex:1}
.spark{width:100%;height:32px;display:block}
.spark-empty{height:32px;display:flex;align-items:center;font-size:11px;color:var(--ink-4)}
.pf{display:flex;justify-content:space-between;margin-top:5px;font-size:11px;color:var(--ink-4)}
.pf b{color:var(--ink-3);font-weight:600;font-variant-numeric:tabular-nums}
</style>
