<script setup lang="ts">
import { computed } from 'vue'
import { store } from '../store'
const total = computed(() => store.members.reduce((a, m) => a + m.gb, 0))
const online = computed(() => store.members.filter(m => m.on).length)
// 空列表时 Math.max(...[]) = -Infinity,会让进度条宽度变 NaN%;兜底 1
const mx = computed(() => Math.max(1, ...store.members.map(m => m.gb)))
const sorted = computed(() => [...store.members].sort((a, b) => b.gb - a.gb))
</script>
<template>
  <div class="grid g4" style="margin-bottom:18px">
    <div class="stat"><div class="k"><span>累计用量</span></div><div class="v">{{ total.toLocaleString() }}<u>GB</u></div></div>
    <div class="stat"><div class="k"><span>会员数</span></div><div class="v">{{ store.members.length }}</div></div>
    <div class="stat"><div class="k"><span>在线</span></div><div class="v">{{ online }}</div></div>
    <div class="stat"><div class="k"><span>人均</span></div><div class="v">{{ store.members.length ? Math.round(total / store.members.length) : 0 }}<u>GB</u></div></div>
  </div>
  <div class="panel">
    <!-- s-ui 给的是 up+down 累计值(自上次重置起),不是自然月,别标"本月" -->
    <div class="sect"><h3>会员流量排行</h3><div class="sp" /><span class="chip gray">累计 · 自上次重置</span></div>
    <div v-if="sorted.length">
      <div v-for="m in sorted" :key="m.name" class="row" :class="{ top: m.gb === mx && m.gb > 0 }">
        <div class="who"><b>{{ m.name }}</b></div>
        <div class="bar"><i :style="{ width: (m.gb / mx * 100) + '%' }" /></div>
        <div class="val">{{ m.gb }} GB</div>
      </div>
    </div>
    <div v-else style="padding:20px 0;text-align:center;font-size:12px;color:var(--ink-4)">还没有会员</div>
  </div>
</template>
