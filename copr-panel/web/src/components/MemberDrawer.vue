<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import Icon from './Icon.vue'
import { store } from '../store'
import { save } from '../api/client'
import { qrSvg, copyText } from '../lib/qr'
import { toast } from '../ui'
const props = defineProps<{ name: string }>()
const emit = defineEmits<{ (e: 'close'): void; (e: 'edit', name: string): void }>()
const m = computed(() => store.members.find(x => x.name === props.name)!)
async function revoke() {
  if (m.value.id == null) { toast('该会员没有 id,无法吊销'); emit('close'); return }
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
// 空列表 / 全 0 时兜底 1,避免除零得到 NaN%
const mx = computed(() => Math.max(1, ...store.members.map(x => x.gb)))
const url = computed(() => store.subUrl(props.name))
// s-ui 的 api/resetTraffic 是【全局】清零(无 client 参数),按单人用会把所有人流量清掉;
// 单人重置只能去 s-ui 原面板操作,这里不做假按钮。
function openSui() { window.open(store.suiUrl(), '_blank') }
// 手机上发订阅:系统分享面板(微信/Telegram/短信…);不支持的浏览器(多数桌面)只给复制
const canShare = typeof navigator !== 'undefined' && !!navigator.share
const copied = ref(false)
let copiedT = 0
function copy() {
  copyText(url.value)
  copied.value = true; clearTimeout(copiedT)
  copiedT = window.setTimeout(() => { copied.value = false }, 1600)
}
async function share() {
  try { await navigator.share({ title: `${props.name} 的订阅`, url: url.value }) }
  catch (e: any) { if (e?.name !== 'AbortError') copy() }   // 用户取消分享不算失败;其他失败退回复制
}
function onKey(e: KeyboardEvent) { if (e.key === 'Escape') emit('close') }
onMounted(() => document.addEventListener('keydown', onKey))
onUnmounted(() => { document.removeEventListener('keydown', onKey); clearTimeout(copiedT) })
</script>
<template>
  <div class="bd" @click="emit('close')" />
  <div class="dr open">
    <div class="drh">
      <div class="av">{{ m.name[0].toUpperCase() }}</div>
      <div><b>{{ m.name }}</b><div class="mst"><span class="chip" :class="m.on ? 'on' : 'gray'">{{ m.on ? '在线' : '离线' }}</span><span class="chip gray">到期 {{ m.exp }}</span></div></div>
      <div class="sp" />
      <button class="dredit" @click="emit('edit', m.name)">编辑</button>
      <button class="mox" aria-label="关闭" @click="emit('close')"><Icon name="close" :size="14" /></button>
    </div>
    <div class="qr" v-html="qrSvg(url)" />
    <div class="qrcap">扫码导入订阅(Clash Verge / mihomo)</div>
    <div class="url"><code class="sel">{{ url }}</code></div>
    <div class="shr">
      <button v-if="canShare" class="sp1" @click="share">分享订阅</button>
      <button :class="canShare ? 'sp2' : 'sp1'" @click="copy">{{ copied ? '已复制' : '复制链接' }}</button>
    </div>
    <div class="lb" style="margin-top:8px">累计用量</div>
    <div class="urow"><b class="num">{{ m.gb }} GB</b><span>占比 {{ (m.gb / mx * 100).toFixed(0) }}%</span></div>
    <div class="ubar"><i :style="{ width: (m.gb / mx * 100) + '%' }" /></div>
    <div class="kv"><span>状态</span><b>{{ m.on ? '在线' : '离线' }}</b></div>
    <div class="kv"><span>到期</span><b>{{ m.exp }}</b></div>
    <div class="kv"><span>订阅格式</span><b>clash</b></div>
    <div class="dract"><button class="g" @click="openSui">在 s-ui 重置流量</button><button class="r" @click="revoke">吊销会员</button></div>
  </div>
</template>
<style scoped>
.bd{position:fixed;inset:0;z-index:40;background:rgba(4,5,8,.5);animation:fade .2s}@keyframes fade{from{opacity:0}}
.dr{position:fixed;top:0;right:0;bottom:0;width:min(400px,100%);background:var(--panel);z-index:41;box-shadow:var(--shadow-pop);overflow:auto;padding:24px;animation:sl .3s var(--ease-out)}
@keyframes sl{from{transform:translateX(100%)}}
.drh{display:flex;align-items:center;gap:10px;margin-bottom:20px}
.drh .av{width:40px;height:40px;border-radius:var(--r-pill);background:var(--accent-soft);color:var(--accent-ink);display:flex;align-items:center;justify-content:center;font-weight:700}
.drh b{font-size:17px;font-weight:700}.drh .mst{display:flex;gap:6px;margin-top:4px}.drh .sp{flex:1}
.sel{user-select:text}
.shr{display:flex;gap:9px;margin:10px 0 22px}
.shr button{flex:1;min-height:44px;border-radius:var(--r-sm);font-size:14px;font-weight:650;transition:filter var(--t-fast),transform var(--t-fast) var(--ease-out)}
.shr .sp1{background:var(--accent);color:#fff}
.shr .sp2{background:var(--inset);color:var(--ink-2)}
.shr button:active{transform:scale(.97)}
.shr button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
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
/* 窄屏:底部弹层,与 Modal 一致 */
@media (max-width:820px){
  .dr{top:auto;left:0;width:100%;max-height:92dvh;border-radius:var(--r-xl) var(--r-xl) 0 0;
      padding:20px 16px calc(20px + env(safe-area-inset-bottom));animation:up .3s var(--ease-out);overscroll-behavior:contain}
  @keyframes up{from{transform:translateY(100%)}}
  .mox,.dredit{min-height:44px}.mox{width:44px}
  .dract button{min-height:44px}
}
</style>
