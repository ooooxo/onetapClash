<script setup lang="ts">
import { computed, onMounted, onUnmounted } from 'vue'
import Icon from './Icon.vue'
import { store } from '../store'
import { save } from '../api/client'
import { qrSvg, copyText } from '../lib/qr'
import { toast } from '../ui'
const props = defineProps<{ name: string }>()
const emit = defineEmits<{ (e: 'close'): void; (e: 'edit', name: string): void }>()
const m = computed(() => store.members.find(x => x.name === props.name)!)
async function revoke() {
  if (m.value.id == null) { toast('演示数据无法吊销'); emit('close'); return }
  const id = m.value.id, nm = m.value.name
  // 乐观移除:列表立即更新、抽屉立即关(s-ui 删除会重载 sing-box,较慢,后台跑)
  const idx = store.members.findIndex(x => x.id === id)
  const removed = idx >= 0 ? store.members.splice(idx, 1)[0] : null
  emit('close')
  toast('吊销中… ' + nm)
  try {
    await save('clients', 'del', id)
    await store.load()
    toast('已吊销 ' + nm)
  } catch (e: any) {
    if (removed && idx >= 0) store.members.splice(idx, 0, removed)  // 失败回滚
    toast('吊销失败: ' + (e?.message || e))
  }
}
const mx = computed(() => Math.max(...store.members.map(x => x.gb)))
const url = computed(() => store.subUrl(props.name))
function onKey(e: KeyboardEvent) { if (e.key === 'Escape') emit('close') }
onMounted(() => document.addEventListener('keydown', onKey))
onUnmounted(() => document.removeEventListener('keydown', onKey))
</script>
<template>
  <div class="bd" @click="emit('close')" />
  <div class="dr open">
    <div class="drh">
      <div class="av">{{ m.name[0].toUpperCase() }}</div>
      <div><b>{{ m.name }}</b><div class="mst">{{ m.on ? '在线' : '离线' }} · {{ m.exp }}</div></div>
      <div class="sp" />
      <button class="dredit" @click="emit('edit', m.name)">编辑</button>
      <button class="mox" aria-label="关闭" @click="emit('close')"><Icon name="close" :size="14" /></button>
    </div>
    <div class="qr" v-html="qrSvg(url)" />
    <div class="qrcap">示例二维码 · 上线后服务端生成可扫码</div>
    <div class="url"><code>{{ url }}</code><button class="cpy" @click="copyText(url)">复制</button></div>
    <div class="lb" style="margin-top:8px">本月用量</div>
    <div class="urow"><b class="num">{{ m.gb }} GB</b><span>占比 {{ (m.gb / mx * 100).toFixed(0) }}%</span></div>
    <div class="ubar"><i :style="{ width: (m.gb / mx * 100) + '%' }" /></div>
    <div class="kv"><span>状态</span><b>{{ m.on ? '在线' : '离线' }}</b></div>
    <div class="kv"><span>到期</span><b>{{ m.exp }}</b></div>
    <div class="kv"><span>订阅格式</span><b>clash</b></div>
    <div class="dract"><button class="g" @click="toast('重置流量:下一步接入')">重置流量</button><button class="r" @click="revoke">吊销会员</button></div>
  </div>
</template>
<style scoped>
.bd{position:fixed;inset:0;z-index:40;background:rgba(4,5,8,.5);animation:fade .2s}@keyframes fade{from{opacity:0}}
.dr{position:fixed;top:0;right:0;bottom:0;width:min(400px,100%);background:var(--panel);z-index:41;box-shadow:var(--shadow-pop);overflow:auto;padding:24px;animation:sl .3s var(--ease-out)}
@keyframes sl{from{transform:translateX(100%)}}
.drh{display:flex;align-items:center;gap:10px;margin-bottom:20px}
.drh .av{width:40px;height:40px;border-radius:var(--r-pill);background:var(--accent-soft);color:var(--accent-ink);display:flex;align-items:center;justify-content:center;font-weight:700}
.drh b{font-size:17px;font-weight:700}.drh .mst{font-size:12px;color:var(--ink-3)}.drh .sp{flex:1}
.dredit{background:var(--inset);color:var(--ink-2);border-radius:var(--r-xs);padding:6px 12px;font-size:12px;font-weight:600;margin-right:6px}
.dredit:hover{background:var(--hover-2)}
.mox{width:30px;height:30px;border-radius:var(--r-sm);background:var(--inset);color:var(--ink-3);display:flex;align-items:center;justify-content:center}
.qr{width:176px;height:176px;margin:6px auto;background:#fff;border-radius:var(--r-md);padding:11px}
.qr :deep(svg){width:100%;height:100%}
.qrcap{text-align:center;font-size:11px;color:var(--ink-4);margin-bottom:16px}
.urow{display:flex;justify-content:space-between;align-items:baseline;margin-top:4px}
.urow b{font-size:22px;font-weight:700}.urow span{font-size:12px;color:var(--ink-4)}
.ubar{height:9px;border-radius:5px;background:var(--inset);overflow:hidden;margin:8px 0}
.ubar i{display:block;height:100%;border-radius:5px;background:var(--accent)}
.kv{display:flex;justify-content:space-between;padding:9px 0;font-size:13px}.kv+.kv{border-top:1px solid var(--hairline)}
.kv span{color:var(--ink-3)}.kv b{font-weight:600}
.dract{display:flex;gap:9px;margin-top:20px}
.dract button{flex:1;padding:11px;border-radius:var(--r-sm);font-size:13px;font-weight:600}
.dract .g{background:var(--inset);color:var(--ink-2)}
.dract .r{background:color-mix(in srgb,var(--crit) 15%,transparent);color:var(--crit)}
</style>
