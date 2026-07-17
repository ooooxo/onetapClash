<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { store } from '../store'
import { copyText } from '../lib/qr'
import { toast } from '../ui'
import { convRules, convSetRules } from '../api/client'
import Icon from '../components/Icon.vue'
import Switch from '../components/Switch.vue'
import XSelect from '../components/XSelect.vue'

interface Provider { key: string; behavior?: string; url: string }
interface Module { id: string; name: string; policy: string; enabled: boolean; providers: Provider[]; rules: string[] }
interface RulesCfg { dns?: any; groups?: string[]; final?: string; modules: Module[] }

const POLICIES = ['DIRECT', 'REJECT', '🚀 手动选择', '♻️ 自动选择', '🎬 看视频']
const DEFAULT: RulesCfg = {
  groups: ['♻️ 自动选择', '🚀 手动选择', '🎬 看视频'], final: '♻️ 自动选择',
  modules: [
    { id: 'reject', name: '广告拦截', policy: 'REJECT', enabled: true, providers: [{ key: 'ads', url: '' }], rules: [] },
    { id: 'cn', name: '国内直连', policy: 'DIRECT', enabled: true, providers: [{ key: 'cn', url: '' }], rules: ['GEOIP,CN,DIRECT'] },
    { id: 'custom', name: '自定义', policy: '🚀 手动选择', enabled: true, providers: [], rules: [] },
  ],
}
const cfg = ref<RulesCfg>(JSON.parse(JSON.stringify(DEFAULT)))
const loaded = ref(false)
const saving = ref(false)

onMounted(async () => {
  try {
    const r: any = await convRules()
    if (r && Array.isArray(r.modules)) { cfg.value = r; loaded.value = true }
  } catch { /* 无后端/未接:用默认演示 */ }
})

const dragI = ref(-1)
function onDrop(i: number) {
  if (dragI.value < 0 || dragI.value === i) return
  const m = cfg.value.modules
  const [x] = m.splice(dragI.value, 1); m.splice(i, 0, x); dragI.value = -1
}
function addRule(mod: Module) { mod.rules.push('') }
function delRule(mod: Module, i: number) { mod.rules.splice(i, 1) }

async function saveRules() {
  saving.value = true
  try {
    await convSetRules(cfg.value)
    toast('分流已保存 · 客户端更新订阅即生效')
  } catch (e: any) { toast('保存失败: ' + (e?.message || e)) }
  saving.value = false
}

const yaml = computed(() => {
  const on = cfg.value.modules.filter(m => m.enabled)
  let y = '# copr.site 分流 · 预览(顺序=优先级)\nmode: rule\n'
  y += 'dns:\n  enhanced-mode: fake-ip\n  fake-ip-filter: ["*.lan", geosite:cn]\n  proxy-server-nameserver: [https://1.1.1.1/dns-query]\n'
  const provs = on.flatMap(m => m.providers.map(p => p.key))
  if (provs.length) { y += 'rule-providers:\n'; provs.forEach(k => y += `  ${k}: {type: http, format: mrs, url: ".../${k}.mrs"}\n`) }
  y += 'rules:\n'
  on.forEach(m => { m.providers.forEach(p => y += `  - RULE-SET,${p.key},${m.policy}\n`); m.rules.forEach(r => { if (r) y += `  - ${r}\n` }) })
  y += `  - MATCH,${cfg.value.final || '🚀 手动选择'}\n`
  return y
})
const base = () => `http://${store.domain}/get/<会员名>`
</script>

<template>
  <div class="grid g2">
    <div class="panel">
      <div class="sect"><h3>订阅地址</h3><div class="sp" /><span class="chip">已优化</span></div>
      <p class="hint">对外统一入口(经 converter),地址不变。</p>
      <div class="url"><code>{{ base() }}</code><button class="cpy" @click="copyText(base())">复制</button></div>
      <div class="krow"><span>协议格式</span><b>clash / sing-box</b></div>
      <div class="krow"><span>规则来源</span><b>{{ loaded ? 'converter(线上)' : '默认(未接)' }}</b></div>
    </div>

    <div class="panel">
      <div class="sect"><h3>分流模块</h3><div class="sp" />
        <span class="chip gray" style="margin-right:8px">{{ cfg.modules.filter(m => m.enabled).length }} 启用</span>
        <button class="pri" :disabled="saving" @click="saveRules"><Icon name="add" :size="14" />{{ saving ? '保存中…' : '保存' }}</button>
      </div>
      <p class="hint">拖拽排序=优先级;点开加/删规则;开关停用。保存写进 converter。</p>
      <div v-for="(m, i) in cfg.modules" :key="m.id" class="mod" :class="{ dim: !m.enabled }"
        draggable="true" @dragstart="dragI = i" @dragover.prevent @drop="onDrop(i)">
        <div class="mh">
          <span class="grip"><Icon name="dashboard" :size="13" /></span>
          <b @click="(m as any)._o = !(m as any)._o">{{ m.name }}</b>
          <span class="chip gray">{{ m.policy }}</span>
          <div class="sp" />
          <Switch v-model="m.enabled" />
        </div>
        <div v-if="(m as any)._o" class="mbody">
          <div class="ml"><label>落地策略</label><XSelect v-model="m.policy" :options="POLICIES" /></div>
          <div v-if="m.providers.length" class="provs">规则集:<span v-for="p in m.providers" :key="p.key" class="chip gray">{{ p.key }}.mrs</span></div>
          <div v-for="(_, ri) in m.rules" :key="ri" class="rrow">
            <input v-model="m.rules[ri]" placeholder="如 DOMAIN-SUFFIX,example.com,DIRECT" />
            <button class="del" @click="delRule(m, ri)"><Icon name="close" :size="12" /></button>
          </div>
          <button class="addr" @click="addRule(m)"><Icon name="add" :size="12" />添加规则</button>
        </div>
      </div>
    </div>
  </div>

  <div class="panel" style="margin-top:16px">
    <div class="sect"><h3>生成的 Clash 配置(预览)</h3><div class="sp" /><button class="cpy" @click="copyText(yaml)">复制</button></div>
    <pre class="yaml">{{ yaml }}</pre>
  </div>
</template>

<style scoped>
.hint{font-size:12px;color:var(--ink-3);margin-bottom:12px;line-height:1.6}
.krow{display:flex;justify-content:space-between;padding:7px 0;font-size:13px;border-top:1px solid var(--hairline)}
.krow span{color:var(--ink-3)}.krow b{font-weight:600;font-family:var(--font-mono);font-size:12px}
.mod{border:1px solid var(--sep);border-radius:var(--r-md);margin-bottom:8px;background:var(--panel-strong);transition:opacity var(--t-fast)}
.mod.dim{opacity:.5}
.mh{display:flex;align-items:center;gap:9px;padding:11px 12px}
.grip{color:var(--ink-4);cursor:grab;display:flex}
.mh b{font-size:13px;font-weight:600;cursor:pointer}.mh .sp{flex:1}
.mbody{padding:0 12px 12px;border-top:1px solid var(--sep)}
.ml{margin:12px 0}.ml label{display:block;font-size:11px;font-weight:600;color:var(--ink-3);margin-bottom:6px}
.provs{font-size:11px;color:var(--ink-4);margin-bottom:10px;display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.rrow{display:flex;gap:7px;margin-bottom:7px;align-items:center}
.rrow input{flex:1;background:var(--inset);border:1px solid transparent;border-radius:var(--r-sm);padding:9px 11px;color:var(--ink);font-size:13px;font-family:var(--font-mono)}
.rrow input:focus{outline:none;border-color:var(--accent)}
.del{width:30px;height:30px;flex:none;border-radius:var(--r-xs);background:var(--inset);color:var(--ink-4);display:flex;align-items:center;justify-content:center}
.del:hover{color:var(--crit)}
.addr{display:flex;align-items:center;gap:5px;font-size:12px;color:var(--ink-3);padding:7px 10px;border-radius:var(--r-xs);background:var(--inset);margin-top:2px}
.addr:hover{color:var(--accent-ink)}
.yaml{background:var(--bg-window);border:1px solid var(--sep);border-radius:var(--r-md);padding:15px;font-family:var(--font-mono);font-size:11.5px;line-height:1.65;color:var(--ink-2);white-space:pre;overflow:auto;max-height:420px}
</style>
