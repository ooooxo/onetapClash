<script setup lang="ts">
import { computed } from 'vue'
import { store } from '../store'
const total = computed(() => store.members.reduce((a, m) => a + m.gb, 0))
const online = computed(() => store.members.filter(m => m.on).length)
const mx = computed(() => Math.max(...store.members.map(m => m.gb)))
const sorted = computed(() => [...store.members].sort((a, b) => b.gb - a.gb))
</script>
<template>
  <div class="grid g4" style="margin-bottom:18px">
    <div class="stat"><div class="k"><span>总用量</span></div><div class="v">{{ total.toLocaleString() }}<u>GB</u></div></div>
    <div class="stat"><div class="k"><span>会员数</span></div><div class="v">{{ store.members.length }}</div></div>
    <div class="stat"><div class="k"><span>在线</span></div><div class="v">{{ online }}</div></div>
    <div class="stat"><div class="k"><span>日均</span></div><div class="v">{{ Math.round(total / 30) }}<u>GB</u></div></div>
  </div>
  <div class="panel">
    <div class="sect"><h3>会员流量排行</h3><div class="sp" /><span class="chip gray">本月 · 示例</span></div>
    <div v-for="m in sorted" :key="m.name" class="row" :class="{ top: m.gb === mx }">
      <div class="who"><b>{{ m.name }}</b></div>
      <div class="bar"><i :style="{ width: (m.gb / mx * 100) + '%' }" /></div>
      <div class="val">{{ m.gb }} GB</div>
    </div>
  </div>
</template>
