<script setup lang="ts">
import { ref } from 'vue'
const props = defineProps<{ modelValue: string }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: string): void }>()
const open = ref(false)
const view = ref(props.modelValue ? new Date(props.modelValue + 'T00:00:00') : new Date(2026, 6, 17))

const WD = ['日', '一', '二', '三', '四', '五', '六']
function cells() {
  const y = view.value.getFullYear(), m = view.value.getMonth()
  const first = new Date(y, m, 1).getDay(), days = new Date(y, m + 1, 0).getDate()
  const out: { d: number; ds: string }[] = []
  for (let i = 0; i < first; i++) out.push({ d: 0, ds: '' })
  for (let d = 1; d <= days; d++) out.push({ d, ds: `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}` })
  return out
}
const title = () => `${view.value.getFullYear()} 年 ${view.value.getMonth() + 1} 月`
function nav(n: number) { view.value = new Date(view.value.getFullYear(), view.value.getMonth() + n, 1) }
function pick(ds: string) { emit('update:modelValue', ds); open.value = false }
function clear() { emit('update:modelValue', ''); open.value = false }
</script>
<template>
  <div class="xdate">
    <div class="xdate-t" :class="{ open, ph: !modelValue }" @click="open = !open">
      <span>{{ modelValue || '选择日期' }}</span>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="4.5" width="18" height="16" rx="2" /><path d="M3 9.5h18M8 2.5v4M16 2.5v4" stroke-linecap="round" /></svg>
    </div>
    <template v-if="open">
      <div class="bd" @click="open = false" />
      <div class="cal">
        <div class="cal-h"><button @click="nav(-1)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 6l-6 6 6 6" stroke-linecap="round" /></svg></button><b>{{ title() }}</b><div class="sp" /><button @click="nav(1)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 6l6 6-6 6" stroke-linecap="round" /></svg></button></div>
        <div class="cal-g">
          <div v-for="w in WD" :key="w" class="wd">{{ w }}</div>
          <div v-for="(c, i) in cells()" :key="i" class="cal-d" :class="{ mut: !c.d, sel: c.ds === modelValue }" @click="c.d && pick(c.ds)">{{ c.d || '' }}</div>
        </div>
        <div class="cal-x"><button @click="clear">清除</button></div>
      </div>
    </template>
  </div>
</template>
<style scoped>
.xdate{position:relative;user-select:none}
.xdate-t{display:flex;align-items:center;gap:8px;background:var(--inset);border:1px solid transparent;border-radius:var(--r-sm);padding:11px 13px;font-size:14px;color:var(--ink);cursor:pointer;transition:border-color var(--t-fast)}
.xdate-t.open{border-color:var(--accent)}.xdate-t.ph span{color:var(--ink-4)}
.xdate-t svg{width:15px;height:15px;color:var(--ink-3);margin-left:auto;flex:none}
.bd{position:fixed;inset:0;z-index:18}
.cal{position:absolute;top:calc(100% + 5px);left:0;z-index:19;width:258px;background:var(--panel-strong);border:1px solid var(--sep);border-radius:var(--r-md);box-shadow:var(--shadow-pop);padding:12px;animation:dp .16s var(--ease-out)}
@keyframes dp{from{opacity:0;transform:translateY(-6px)}}
.cal-h{display:flex;align-items:center;margin-bottom:9px}.cal-h b{font-size:13px;font-weight:650}.cal-h .sp{flex:1}
.cal-h button{width:26px;height:26px;border-radius:var(--r-xs);color:var(--ink-3);display:flex;align-items:center;justify-content:center}
.cal-h button:hover{background:var(--hover);color:var(--ink)}.cal-h button svg{width:14px;height:14px}
.cal-g{display:grid;grid-template-columns:repeat(7,1fr);gap:2px}
.wd{font-size:10px;color:var(--ink-4);text-align:center;padding:3px 0;font-weight:600}
.cal-d{aspect-ratio:1;display:flex;align-items:center;justify-content:center;font-size:12px;border-radius:var(--r-xs);cursor:pointer;color:var(--ink-2);font-variant-numeric:tabular-nums}
.cal-d:hover{background:var(--hover)}.cal-d.mut{pointer-events:none}
.cal-d.sel{background:var(--accent);color:#fff;font-weight:600}
.cal-x{display:flex;margin-top:8px;padding-top:8px;border-top:1px solid var(--sep)}
.cal-x button{flex:1;font-size:12px;color:var(--ink-3);padding:6px;border-radius:var(--r-xs)}
.cal-x button:hover{background:var(--hover);color:var(--ink)}
</style>
