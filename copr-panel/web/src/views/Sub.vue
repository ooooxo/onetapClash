<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { store } from '../store'
import { copyText } from '../lib/qr'
import { toast } from '../ui'
import { convRules, convSetRules } from '../api/client'
import Icon from '../components/Icon.vue'
import Switch from '../components/Switch.vue'
import XSelect from '../components/XSelect.vue'

// 结构必须与 sui-converter/rules.default.json 一致 —— converter 只认 geosite/geoip/rules。
// (旧版这里用的是 providers[]/.mrs,converter 根本不读,存下去等于把分流规则清空。)
interface Module { id: string; name: string; policy: string; enabled: boolean; geosite: string[]; geoip: string[]; rules: string[] }
interface RulesCfg { groups: string[]; final: string; modules: Module[] }

const cfg = ref<RulesCfg | null>(null)
const loadErr = ref('')
const saving = ref(false)
const POLICIES = computed(() => ['DIRECT', 'REJECT', ...(cfg.value?.groups ?? [])])

onMounted(async () => {
  try {
    const r: any = await convRules()
    if (r && Array.isArray(r.modules)) cfg.value = r
    else loadErr.value = 'converter 返回的规则格式不对'
  } catch (e: any) { loadErr.value = String(e?.message || e) }
})

const dragI = ref(-1)
function onDrop(i: number) {
  if (!cfg.value || dragI.value < 0 || dragI.value === i) return
  const m = cfg.value.modules
  const [x] = m.splice(dragI.value, 1); m.splice(i, 0, x); dragI.value = -1
}
function addRule(mod: Module) { mod.rules.push('') }
function delRule(mod: Module, i: number) { mod.rules.splice(i, 1) }

async function saveRules() {
  if (!cfg.value) return
  saving.value = true
  try {
    // 存前清掉空规则行,避免写出 " - " 这种坏规则
    cfg.value.modules.forEach(m => { m.rules = m.rules.filter(r => r.trim()) })
    await convSetRules(cfg.value)
    toast('分流已保存 · 客户端更新订阅即生效')
  } catch (e: any) { toast('保存失败: ' + (e?.message || e)) }
  saving.value = false
}

// 预览按 converter 的 build_clash_config 同一套逻辑拼:内联 GEOSITE/GEOIP,无 rule-providers。
const rulesPreview = computed(() => {
  if (!cfg.value) return ''
  const out: string[] = [`DOMAIN-SUFFIX,${store.domain},DIRECT   # 管理域名强制直连`]
  for (const m of cfg.value.modules) {
    if (!m.enabled) continue
    for (const gs of m.geosite ?? []) out.push(`GEOSITE,${gs},${m.policy}`)
    for (const gi of m.geoip ?? []) out.push(`GEOIP,${gi},${m.policy},no-resolve`)
    for (const r of m.rules ?? []) if (r.trim()) out.push(r)
  }
  out.push(`MATCH,${cfg.value.final}`)
  return out.map(r => `  - ${r}`).join('\n')
})
const base = () => store.subUrl('<会员名>')
</script>

<template>
  <div class="grid g2">
    <div class="panel">
      <div class="sect"><h3>订阅地址</h3><div class="sp" /><span class="chip" :class="cfg ? 'on' : 'gray'">{{ cfg ? '线上' : '未接' }}</span></div>
      <p class="hint">对外统一入口(经 converter),地址不变。协议跟随面板,面板是 HTTPS 订阅就是 HTTPS。</p>
      <div class="url"><code>{{ base() }}</code><button class="cpy" @click="copyText(base())">复制</button></div>
      <div class="krow"><span>输出格式</span><b>Clash / mihomo</b></div>
      <div class="krow"><span>规则来源</span><b>{{ cfg ? 'converter(线上)' : '读取失败' }}</b></div>
      <div class="krow"><span>节点数</span><b>{{ store.nodes.length }}</b></div>
    </div>

    <div class="panel">
      <div class="sect"><h3>分流模块</h3><div class="sp" />
        <span v-if="cfg" class="chip gray" style="margin-right:8px">{{ cfg.modules.filter(m => m.enabled).length }} 启用</span>
        <button class="pri" :disabled="saving || !cfg" @click="saveRules"><Icon name="add" :size="14" />{{ saving ? '保存中…' : '保存' }}</button>
      </div>
      <div v-if="loadErr" class="hint" style="color:var(--crit)">读不到 converter 规则:{{ loadErr }}</div>
      <template v-else-if="cfg">
        <p class="hint">拖拽排序=优先级;点标题展开加/删规则;开关停用。保存直接写进 converter。</p>
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
            <div v-if="(m.geosite?.length || m.geoip?.length)" class="provs">内置规则集:
              <span v-for="g in m.geosite" :key="'gs' + g" class="chip gray">GEOSITE,{{ g }}</span>
              <span v-for="g in m.geoip" :key="'gi' + g" class="chip gray">GEOIP,{{ g }}</span>
            </div>
            <div v-for="(_, ri) in m.rules" :key="ri" class="rrow">
              <input v-model="m.rules[ri]" placeholder="如 DOMAIN-SUFFIX,example.com,DIRECT" />
              <button class="del" @click="delRule(m, ri)"><Icon name="close" :size="12" /></button>
            </div>
            <button class="addr" @click="addRule(m)"><Icon name="add" :size="12" />添加规则</button>
          </div>
        </div>
      </template>
      <div v-else class="hint">读取中…</div>
    </div>
  </div>

  <div v-if="cfg" class="panel" style="margin-top:16px">
    <div class="sect"><h3>生成的 rules 段(预览)</h3><div class="sp" /><button class="cpy" @click="copyText(rulesPreview)">复制</button></div>
    <pre class="yaml">rules:
{{ rulesPreview }}</pre>
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
