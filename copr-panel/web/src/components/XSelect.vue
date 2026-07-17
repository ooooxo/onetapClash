<script setup lang="ts">
import { ref } from 'vue'
const props = defineProps<{ modelValue: string; options: string[] }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: string): void }>()
const open = ref(false)
function pick(o: string) { emit('update:modelValue', o); open.value = false }
</script>
<template>
  <div class="xsel">
    <div class="xsel-t" :class="{ open }" @click="open = !open">
      <span class="v">{{ modelValue }}</span>
      <span class="cv" :class="{ open }"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 9l6 6 6-6" stroke-linecap="round" stroke-linejoin="round" /></svg></span>
    </div>
    <template v-if="open">
      <div class="bd" @click="open = false" />
      <div class="xpop">
        <div v-for="o in options" :key="o" class="xopt" :class="{ sel: o === modelValue }" @click="pick(o)">{{ o }}</div>
      </div>
    </template>
  </div>
</template>
<style scoped>
.xsel{position:relative;user-select:none}
.xsel-t{display:flex;align-items:center;gap:8px;background:var(--inset);border:1px solid transparent;border-radius:var(--r-sm);padding:11px 13px;font-size:14px;color:var(--ink);cursor:pointer;transition:border-color var(--t-fast)}
.xsel-t.open{border-color:var(--accent)}
.xsel-t .v{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cv{margin-left:auto;color:var(--ink-3);transition:transform var(--t-fast)}.cv.open{transform:rotate(180deg)}.cv svg{width:14px;height:14px}
.bd{position:fixed;inset:0;z-index:18}
.xpop{position:absolute;top:calc(100% + 5px);left:0;right:0;z-index:19;background:var(--panel-strong);border:1px solid var(--sep);border-radius:var(--r-sm);box-shadow:var(--shadow-pop);padding:5px;max-height:220px;overflow:auto;animation:dp .16s var(--ease-out)}
@keyframes dp{from{opacity:0;transform:translateY(-6px)}}
.xopt{padding:9px 11px;border-radius:var(--r-xs);font-size:13px;color:var(--ink-2);cursor:pointer;display:flex;align-items:center;gap:8px}
.xopt:hover{background:var(--hover)}
.xopt.sel{color:var(--accent-ink);font-weight:600}
.xopt.sel::after{content:"";margin-left:auto;width:6px;height:6px;border-radius:99px;background:var(--accent)}
</style>
