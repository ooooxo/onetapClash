<script setup lang="ts">
import { computed } from 'vue'
import { store } from '../store'
import { ui } from '../ui'
import Icon from '../components/Icon.vue'
// 空列表时 Math.max(...[]) = -Infinity → 宽度 NaN%;兜底 1
const mx = computed(() => Math.max(1, ...store.members.map(m => m.gb)))
</script>
<template>
  <div class="panel">
    <div class="sect"><h3>会员</h3><span class="chip gray" style="margin-left:8px">{{ store.members.length }} 人</span><div class="sp" />
      <button class="gh2" @click="ui.bulkOpen = true">批量添加</button>
      <button class="pri" @click="ui.memberEditName = ''"><Icon name="add" :size="15" />新增会员</button>
    </div>
    <div v-if="!store.members.length" style="padding:20px 0;text-align:center;font-size:12px;color:var(--ink-4)">
      还没有会员 —— 点右上「新增会员」建一个,订阅地址就是 {{ store.subUrl('') }}&lt;名称&gt;
    </div>
    <div v-for="(m, i) in store.members" :key="m.name" class="row tap rise" :class="{ top: m.gb === mx && m.gb > 0 }"
      :style="{ '--i': Math.min(i, 6) }" @click="ui.drawerName = m.name">
      <span class="dot" :class="{ on: m.on }" />
      <div class="ti2">{{ m.name[0].toUpperCase() }}</div>
      <div class="who"><b>{{ m.name }}</b><span>get/{{ m.name }}</span></div>
      <div class="bar"><i :style="{ width: (m.gb / mx * 100) + '%' }" /></div>
      <div class="val">{{ m.gb }} GB</div>
      <div class="cv"><Icon name="chevron" :size="15" /></div>
    </div>
  </div>
</template>
<style scoped>
.pri{display:flex;align-items:center;gap:7px;background:var(--accent);color:#fff;border-radius:var(--r-sm);padding:9px 15px;font-size:13px;font-weight:650}
.gh2{background:var(--inset);color:var(--ink-2);border-radius:var(--r-sm);padding:9px 14px;font-size:13px;font-weight:600;margin-right:8px}
.ti2{width:34px;height:34px;border-radius:var(--r-sm);background:var(--inset);display:flex;align-items:center;justify-content:center;color:var(--ink-3);flex:none;font-size:13px;font-weight:700}
.cv{flex:none;color:var(--ink-4)}
/* 进入会员页时逐行淡入:前 6 行错峰,之后同时到;transition + @starting-style,中途切走也能从当前帧收回 */
.rise{transition:opacity var(--t-med) var(--ease-out),transform var(--t-med) var(--ease-out),background var(--t-fast);
      transition-delay:calc(var(--stagger) * var(--i)),calc(var(--stagger) * var(--i)),0s}
@starting-style{.rise{opacity:0;transform:translateY(6px)}}
@media (prefers-reduced-motion:reduce){@starting-style{.rise{transform:none}}}
</style>
